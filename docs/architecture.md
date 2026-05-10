# Architecture

## Packet flow

When Tesla loads `https://your.domain` over the Pi's hotspot:

1. **DNS** — Tesla's resolver (via DHCP) is the Pi (`10.42.0.1`).
   NetworkManager's shared-mode dnsmasq has an `address=/your.domain/10.42.0.1`
   override, so the answer is the Pi's hotspot IP. No public DNS query happens.
2. **TCP 443 → 8443** — On the Pi, a nftables `prerouting` rule redirects
   port 443 to 8443 where KasmVNC's Xvnc is listening. KasmVNC stays
   unprivileged.
3. **TLS** — KasmVNC presents the Let's Encrypt cert for `your.domain`.
   Tesla browser validates it the same as any internet site (cert validation
   is by name, not by IP), so there's no warning.
4. **WebSocket** — KasmVNC web client opens the WebSocket on `wss://...:443`,
   the redirect lands it on 8443, the framebuffer streams as JPEG/WebP.

## Internet path

When Tesla makes any other request:

1. **DHCP** — Pi's hotspot dnsmasq gives Tesla an IP in `10.42.0.0/24` and
   `10.42.0.1` as gateway + DNS.
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
[BT class 0x5A020C]          tells peers we're a phone, not a computer
```

PipeWire's `bluez5` plugin advertises us as A2DP source automatically once a
device pairs. The BT class controls how peers decide whether we're a valid
audio source — Tesla is restrictive and only accepts "phone" class.

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
 │    ├── bluetooth.service   (Class=0x5A020C in /etc/bluetooth/main.conf)
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
