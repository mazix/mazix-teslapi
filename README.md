# tesla-pi-station

Turn a Raspberry Pi 5 into a self-contained connectivity + media station for a
Tesla (or anything with a browser): the car connects to the Pi's Wi-Fi, the Pi
connects to the internet via iPhone USB tether, and the carrier's hotspot
detection is bypassed so it counts against your unlimited cellular data instead
of your hotspot quota. The Pi also serves a touch-friendly, browser-based
remote desktop that the car can open by name (no port number, valid TLS).

## What you get

- Pi as **Wi-Fi access point** (NetworkManager `shared` mode).
- **iPhone Personal Hotspot over USB** as upstream — TTL rewritten to 65 so
  your carrier sees TTL=64 (looks native to the iPhone).
- **KasmVNC** browser remote desktop (LXDE-pi), reachable as
  `https://your.domain` (port 443→8443 redirect).
- **Let's Encrypt** cert via Cloudflare DNS-01. No public A record needed —
  the Pi's hotspot DNS hijacks `your.domain` to its local IP.
- **Bluetooth audio source** (PipeWire/BlueZ) advertised as a phone, so Tesla
  accepts it for media playback.
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
                                     │  │ wlan0=10.42.0.1  │  │          │ Browser│
                                     │  │ shared (NAT/DHCP │  │          └────────┘
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
                                     │  │ Class=0x5A020C   │  │
                                     │  │ + bt-agent + GUI │  │
                                     │  └──────────────────┘  │
                                     └────────────────────────┘
```

## Requirements

- **Raspberry Pi 5** with **Raspberry Pi OS Trixie** (X11 session — the
  installer flips the system off Wayland for you).
- A **domain you own** with DNS managed at **Cloudflare**.
- A **Cloudflare API token** scoped to *Edit zone DNS* on that zone.
- An iPhone with **unlimited cellular data** (this is for routing through
  cellular without tripping hotspot quotas — not for piracy).
- A USB cable iPhone → Pi.
- Email for Let's Encrypt registration.

## Quick start

```bash
git clone https://github.com/<you>/tesla-pi-station.git
cd tesla-pi-station
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
| 09 | `09-bluetooth-audio.sh` | BT class = phone, persistent pairing agent, BlueZ + PipeWire |
| 10 | `10-bt-gui.sh` | `btaudio.py` Tk GUI + desktop launcher |

Each module is idempotent — re-run as many times as you like.

## After install

- Tesla / phone / laptop: connect to the Wi-Fi `HOTSPOT_SSID`.
- Browser: visit `https://<DOMAIN>` (or with `:443` explicit if you like).
- Audio: open the **BT Audio Manager** icon on the Pi desktop, scan,
  pair Tesla / a Bluetooth speaker, then "Set as Audio Out".

## Customization

Everything is driven by `config.env`. The most common knobs:

- `DOMAIN` — pick anything on a Cloudflare-managed zone you own.
- `HOTSPOT_SSID` / `HOTSPOT_PASSWORD` — the Wi-Fi the car joins.
- `KASMVNC_RES_W` / `KASMVNC_RES_H` — virtual desktop resolution.
- `BT_DEVICE_CLASS` — `0x5A020C` (smartphone) is what Tesla accepts; if your
  car is fussy, [tweak the class bits](docs/troubleshooting.md).

## Uninstall

```bash
./uninstall.sh
```

## Docs

- [`docs/architecture.md`](docs/architecture.md) — packet/data flow.
- [`docs/prerequisites.md`](docs/prerequisites.md) — checklist before install.
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — every footgun we hit.
- [`docs/customization.md`](docs/customization.md) — alternate domains, SSIDs,
  multiple hotspots, etc.

## License

MIT. See [LICENSE](LICENSE).

## A note on the carrier-bypass

Carriers detect tethering primarily via TTL/HopLimit deviation. Setting Pi's
egress TTL to 65 makes packets indistinguishable from native iPhone traffic
*after* the iPhone's own decrement. This is **not** circumventing payment —
it is intended for unlimited / non-throttled plans where the only friction is
the carrier counting the data against the wrong bucket. Read your contract;
your terms may differ.
