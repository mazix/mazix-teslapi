# Architecture

## Address space

The hotspot uses **RFC 5737 TEST-NET-2 (`198.51.100.0/24`)** by default,
not RFC 1918. This is a deliberate choice forced by client-side security
behavior in modern browsers:

- **Tesla's Chromium fork** (and Chromium in general, evolving from 2024+)
  applies a **Private Network Access (PNA)** check: when a public-DNS
  hostname resolves to an RFC 1918 / link-local / CGNAT / loopback address,
  the browser silently aborts the connection. No TCP SYN is even sent.
  Pi's previous `10.42.0.1` default tripped this and produced
  `ERR_CONNECTION_REFUSED` on Tesla while everything else worked.
- TEST-NET ranges are reserved for documentation, **not in PNA's private
  address-space list**, and **not announced in BGP** — so they can't
  collide with anything real on the public internet. The full investigation
  is in [troubleshooting.md](troubleshooting.md).

`HOTSPOT_IP` is set in `config.env`; module 03 plumbs it into NM as
`ipv4.addresses=$HOTSPOT_IP/24`. Defaults assume 198.51.100.1.

## Packet flow

When Tesla loads `https://your.domain` over the Pi's hotspot:

1. **DNS** — Two independent mechanisms answer the same way:
   - Tesla's DHCP-supplied resolver is the Pi (`198.51.100.1`).
     NetworkManager's shared-mode dnsmasq has an
     `address=/your.domain/198.51.100.1` override and replies locally.
   - Tesla's Chromium also fires a DoH query to its public resolver
     (Cloudflare). The DNS-only A record we publish on Cloudflare points
     at the same IP, so the DoH path returns the same answer.
   Without the public record, DoH wins and gets NXDOMAIN — see
   troubleshooting.md.
2. **TCP 80 → 301 → 443** — A tiny Python redirector listens on :80 and
   answers `301 Location: https://...`. Tesla's browser will try HTTP
   first when no HSTS cache exists; without :80 listener it sees
   `ERR_CONNECTION_REFUSED`.
3. **TCP 443 → 8443** — On the Pi, a nftables `prerouting` rule with
   `fib daddr type local` redirects packets that target *this host* on
   port 443 to 8443 where KasmVNC's Xvnc is listening. The `fib`
   predicate is critical: without it, *forwarded* 443 traffic (a hotspot
   client browsing https://youtube.com) is also caught here and serves
   KasmVNC's cert for every HTTPS site → CN mismatch errors.
4. **TLS** — KasmVNC presents the Let's Encrypt cert for `your.domain`.
   Tesla browser validates it the same as any internet site.
5. **WebSocket** — KasmVNC web client opens `wss://...:443`, the redirect
   lands it on 8443, the framebuffer streams as JPEG/WebP.

## Internet path

When Tesla makes any other request:

1. **DHCP** — Pi's hotspot dnsmasq gives Tesla an IP in the
   `HOTSPOT_IP/24` range (default `198.51.100.0/24`, `.10–.254`) and
   the Pi's IP as gateway + DNS.
2. **Forward** — Pi forwards via the *active default route*. With the
   metrics we set, that's `eth1` (iPhone) when present, `eth0` (home
   ethernet) otherwise.
3. **NAT** — NetworkManager's shared mode runs `nft` masquerade on the
   upstream interface, hiding hotspot clients behind the Pi's IP.
4. **TTL rewrite** — Our nftables rule sets every packet's TTL=65 on egress
   from `eth1`. iPhone forwards with `--TTL` → carrier sees TTL=64, which
   matches native iPhone traffic.
5. **Cellular** — Carrier doesn't see anything that looks like tethering and
   counts the bytes against the iPhone's normal data bucket.

## Bluetooth audio

```
[Pi PipeWire] --A2DP source--> [Tesla / BT speaker]
       ^
       |
[bt-agent (NoInputNoOutput)] handles pairing prompts in the background
[BT class 0x240404]          tells peers we're a stereo Headphones device
```

PipeWire's `bluez5` plugin advertises us as A2DP source automatically once a
device pairs. The BT class controls how peers decide whether we're a valid
audio source — Tesla is restrictive: it pairs phone-class devices for HFP
only and refuses A2DP, but reliably opens A2DP for the
**Audio/Video → Headphones** class (`0x240404`). See troubleshooting.md for
the longer story.

## HDMI capture (module 12)

```
[HDMI source]              [USB capture stick]            [Pi]
 console/Apple TV/    →    MS2109 / MS2130 UVC    →   /dev/video0 (V4L2)
 phone/laptop/etc.         (e.g. Apera GA06)         + PA source MACROSILICON_*
                                                            │
                                                            ▼
                                              [hdmi-capture.py wrapper]
                                              ├─ pactl load-module
                                              │     module-loopback
                                              │     source=<capture>
                                              ├─ mpv --fs --hwdec=auto
                                              │     --profile=low-latency
                                              │     av://v4l2:/dev/video0
                                              └─ Tk overlay × close button
                                                            │
                                                            ▼
                                       PipeWire default sink (BT → Tesla,
                                       or whichever sink the user picked)
                                                            │
                                                            ▼
                                              X session (Xvnc :1) →
                                              KasmVNC → Tesla browser
```

The capture chip is plain UVC: the kernel exposes a `/dev/videoN` and an
ALSA/PipeWire source automatically — module 12 only installs `mpv`,
`v4l-utils`, `ffmpeg`, `pulseaudio-utils` and a launcher. The launcher
auto-detects the source by name (`MACROSILICON`, `USB_Video`,
`HDMI_Capture`) so any rebrand of the same chipset works.

## CarPlay / Android Auto (module 13)

```
[iPhone / Android phone]
      ↕ Wi-Fi + BT (wireless pairing handled by the dongle itself)
[Carlinkit CPC200-CCPA]      USB 1314:1521 — "Magic Communication Auto Box"
      ↕ USB (Carlinkit protocol: H.264 + touch + USB-audio class)
[Pi]
 ├─ udev: 99-carlinkit.rules → TAG+=uaccess (no root needed)
 ├─ carplay-server.service   → python http.server on :5005
 │      serving the prebuilt React app from ~/carplay/web-dist
 ├─ carplay-launch.py        →  chromium --app=http://localhost:5005/
 │      --use-angle=swiftshader (KasmVNC Xvnc has no GPU → SwiftShader WebGL)
 │      --use-fake-ui-for-media-stream (auto-allow Siri mic)
 │      --autoplay-policy=no-user-gesture-required
 │      + Tk overlay × close button
 └─ pactl load-module module-loopback source=<Auto_Box / CCPA>
        → routes dongle's USB-audio to default sink (BT → Tesla)
```

The dongle handles the actual CarPlay / Android Auto wireless handshake
with the phone. The Pi only speaks WebUSB to the dongle — there is no
long-running Node daemon; Chromium itself drives the protocol via
`node-CarPlay`'s React example app, which decodes H.264 via WebCodecs.
On a Xvnc display (`:1`) WebGL has no GPU so we force ANGLE's SwiftShader
backend; the `tesla-display switch hwaccel` backend (`:0`) gives real V3D
acceleration if the kiosk needs it.

## Boot sequence

```
power on
 │
 ├── systemd
 │    ├── NetworkManager
 │    │    ├── pi-hotspot     (autoconnect=yes → wlan0 AP)
 │    │    ├── eth0 connection (route metric 700)
 │    │    └── eth1 connection if iPhone present (route metric 100)
 │    ├── nftables.service
 │    │    └── /etc/nftables.d/{ttl-fix,port-redirect}.conf
 │    ├── bluetooth.service   (Class=0x240404 in /etc/bluetooth/main.conf)
 │    └── usbmuxd.socket      (socket-activated)
 │
 └── linger user=pi (loginctl enable-linger)
       └── systemd --user
            ├── kasmvnc.service     (Xvnc :1 + LXDE-pi rpd-x session)
            ├── bt-agent.service    (pairing agent)
            └── pipewire / pipewire-pulse / wireplumber
```

Once the iPhone is plugged in (or eth0 is unplugged), `eth1` wins the
default route and traffic flows through cellular automatically.
