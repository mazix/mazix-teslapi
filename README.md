# maziX TeslaPI

Turn a Raspberry Pi 5 into a self-contained connectivity + media station for a
Tesla (or anything with a browser): the car connects to the Pi's Wi-Fi, the Pi
connects to the internet via iPhone USB tether, and the carrier's hotspot
detection is bypassed so it counts against your unlimited cellular data instead
of your hotspot quota. The Pi also serves a touch-friendly, browser-based
remote desktop that the car can open by name (no port number, valid TLS).

> Repository: <https://github.com/mazix/mazix-teslapi>
> (formerly published as `tesla-pi-station`; GitHub keeps the old URL
> redirecting for now).

## What you get

- Pi as **Wi-Fi access point** (NetworkManager `shared` mode) on a
  RFC 5737 TEST-NET range, chosen to bypass Tesla Chromium's Private Network
  Access check (see [docs/troubleshooting.md](docs/troubleshooting.md)).
- **iPhone Personal Hotspot over USB** as upstream — TTL rewritten to 65 so
  your carrier sees TTL=64 (looks native to the iPhone).
- **KasmVNC** browser remote desktop (LXDE-pi), reachable as
  `https://your.domain` (port 443→8443 redirect, 80→443 redirector for
  browsers that try HTTP first).
- **Let's Encrypt** cert via Cloudflare DNS-01. A public DNS-only A record
  on your Cloudflare zone points the hostname at the Pi's hotspot IP — this
  is required so DoH-using clients (Tesla, macOS Private Relay, Chrome
  Secure DNS) get the same answer the Pi's local dnsmasq would have given.
- **Bluetooth audio source** (PipeWire/BlueZ) advertised as a Headphones-
  class device (`0x240404`). Tesla treats the Pi as a media source and
  opens A2DP automatically on connect. Phone-class advertisement looks
  intuitive but Tesla then refuses A2DP — see
  [docs/troubleshooting.md](docs/troubleshooting.md).
- A small **Tk GUI** on the Pi desktop to pair Bluetooth devices without
  opening a terminal.
- Headless boot — `loginctl enable-linger` + systemd user services, everything
  comes up automatically.

## Architecture

```
                                     ┌────────────────────────┐
              ┌─────────┐  USB       │  Raspberry Pi 5        │
              │ iPhone  ├───────────►│  (Trixie)              │
              │ Hotspot │  eth1      │                        │
              └─────────┘  ipheth    │  ┌──────────────────┐  │  Wi-Fi   ┌────────┐
                                     │  │ NM hotspot       │◄─┼──────────┤ Tesla  │
                                     │  │ wlan0=198.51.100 │  │          │ Browser│
                                     │  │ .1 (TEST-NET-2)  │  │          └────────┘
                                     │  │ shared (NAT/DHCP │  │
                                     │  │ + dnsmasq)       │  │
                                     │  └────────┬─────────┘  │
                                     │           │            │
                                     │  ┌────────▼─────────┐  │
                                     │  │ nftables         │  │
                                     │  │ - 443 → 8443     │  │
                                     │  │ - TTL=65 on eth1 │  │
                                     │  └────────┬─────────┘  │
                                     │           │            │
                                     │  ┌────────▼─────────┐  │
                                     │  │ KasmVNC :8443    │  │
                                     │  │ + LE cert (CF)   │  │
                                     │  │ + LXDE-pi (rpd-x)│  │
                                     │  └──────────────────┘  │
                                     │                        │
                                     │  ┌──────────────────┐  │  A2DP
                                     │  │ PipeWire/BlueZ   ├──┼─────────► Tesla
                                     │  │ Class=0x240404   │  │
                                     │  │ + bt-agent + GUI │  │
                                     │  └──────────────────┘  │
                                     └────────────────────────┘
```

## Requirements

- **Raspberry Pi 5** with **Raspberry Pi OS Trixie** (X11 session — the
  installer flips the system off Wayland for you).
- A **domain you own** with DNS managed at **Cloudflare**.
- A **public DNS-only A record** for the hostname pointing at the Pi's
  hotspot IP (default `198.51.100.1`). See [docs/prerequisites.md].
- A **Cloudflare API token** scoped to *Edit zone DNS* on that zone.
- An iPhone with **unlimited cellular data** (this is for routing through
  cellular without tripping hotspot quotas — not for piracy).
- A USB cable iPhone → Pi.
- Email for Let's Encrypt registration.

## Quick start

```bash
git clone https://github.com/mazix/mazix-teslapi.git
cd mazix-teslapi
cp config.example.env config.env
$EDITOR config.env             # set domain, SSID, password, CF token, email

./install.sh                   # runs all modules in order
```

The installer will prompt for sudo once. After it finishes, plug the iPhone
into USB with Personal Hotspot enabled; the Pi will pick it up automatically.

Open `https://your.domain` from any device joined to your Pi's hotspot.

To run a single step:

```bash
./install.sh 06-kasmvnc 07-letsencrypt
```

## Modules

| # | Script | What it does |
|---|--------|--------------|
| 01 | `01-prereqs.sh` | apt install everything (NM, BlueZ, PipeWire, dnsmasq, nftables, …) |
| 02 | `02-iphone-tether.sh` | Loads `ipheth`, makes it persistent |
| 03 | `03-wifi-hotspot.sh` | NetworkManager AP `pi-hotspot` (shared NAT+DHCP) |
| 04 | `04-routing-bypass.sh` | Route metrics + TTL/HopLimit=65 on the tether interface |
| 05 | `05-port-redirect.sh` | nftables 443 → 8443 |
| 06 | `06-kasmvnc.sh` | Installs KasmVNC, xstartup (LXDE-pi `rpd-x`), user systemd service |
| 07 | `07-letsencrypt.sh` | acme.sh + Cloudflare DNS-01 issues your cert |
| 08 | `08-dns-hijack.sh` | NM hotspot dnsmasq resolves your domain to the Pi |
| 09 | `09-bluetooth-audio.sh` | BT class = Headphones (so Tesla opens A2DP), persistent pairing agent, BlueZ + PipeWire |
| 10 | `10-bt-gui.sh` | `btaudio.py` Tk GUI + desktop launcher |
| 11 | `11-hwaccel-display.sh` | *Optional* second backend (`x11vnc + noVNC` on `:0`, V3D-accelerated) + `tesla-display` switcher CLI + Tk GUI (`Display Backend` desktop icon) |
| 12 | `12-hdmi-capture.sh` | One-tap fullscreen viewer for a USB HDMI capture stick (e.g. MS2109 + Xiaomi TV Stick / Apple TV / console). Auto-routes dongle audio via PipeWire loopback to the default sink. |
| 13 | `13-carplay.sh` | CarPlay / Android Auto kiosk via Carlinkit CCPA. Clones + builds `node-CarPlay`'s React `carplay-web-app`, serves it on `localhost:5005`, Chromium kiosk talks WebUSB to the dongle. Video + touch work today; audio is an open issue (see CHANGELOG). |

Each module is idempotent — re-run as many times as you like.

Module 11 is opt-in. After install both stacks are present but only
KasmVNC serves `:443`; switch with `tesla-display switch hwaccel`
(or the GUI) when you want V3D acceleration on `:0`. See
[`docs/troubleshooting.md`](docs/troubleshooting.md) for when each
backend wins.

## After install

- Tesla / phone / laptop: connect to the Wi-Fi `HOTSPOT_SSID`.
- Browser: visit `https://<DOMAIN>` (or with `:443` explicit if you like).
- Audio: open the **BT Audio Manager** icon on the Pi desktop, scan,
  pair Tesla / a Bluetooth speaker, then "Set as Audio Out".
- Display backend: KasmVNC is default; switch to hwaccel with
  `tesla-display switch hwaccel` (or the **Display Backend** icon on
  the desktop). `tesla-display status` shows the current state.

## Customization

Everything is driven by `config.env`. The most common knobs:

- `DOMAIN` — pick anything on a Cloudflare-managed zone you own.
- `HOTSPOT_SSID` / `HOTSPOT_PASSWORD` — the Wi-Fi the car joins.
- `KASMVNC_RES_W` / `KASMVNC_RES_H` — virtual desktop resolution.
- `BT_DEVICE_CLASS` — `0x240404` (Audio/Video Headphones) is what makes
  Tesla open A2DP on first connect. If your
  car is fussy, [tweak the class bits](docs/troubleshooting.md).

## Uninstall

```bash
./uninstall.sh
```

## Docs

- [`docs/architecture.md`](docs/architecture.md) — packet/data flow.
- [`docs/prerequisites.md`](docs/prerequisites.md) — checklist before install.
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — every footgun we hit,
  including the Tesla PNA and A2DP write-ups.
- [`docs/customization.md`](docs/customization.md) — alternate domains, SSIDs,
  multiple hotspots, etc.
- [`CHANGELOG.md`](CHANGELOG.md) — what landed when, with commit references.

## Roadmap

See [`ROADMAP.md`](ROADMAP.md) for what's coming next:

- **HDMI capture** — PlayStation, Apple TV, Android TV, laptops, anything
  with HDMI out, displayed inside Tesla's browser.
- **CarPlay & Android Auto** via USB wireless dongle + a small web app on
  the Pi (no HDMI loop, native protocol).
- OBD-II overlay, backup cam, multi-zone audio, companion mobile app, and
  more.

⚠️ Some of these features can be used while the car is in motion. **That's
your call — not the project's.** See the safety notes in
[`ROADMAP.md`](ROADMAP.md#-safety--responsibility); the maintainers
disclaim liability for how, where and when you use it.

## License

MIT. See [LICENSE](LICENSE).

## A note on the carrier-bypass

Carriers detect tethering primarily via TTL/HopLimit deviation. Setting Pi's
egress TTL to 65 makes packets indistinguishable from native iPhone traffic
*after* the iPhone's own decrement. This is **not** circumventing payment —
it is intended for unlimited / non-throttled plans where the only friction is
the carrier counting the data against the wrong bucket. Read your contract;
your terms may differ.
