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
