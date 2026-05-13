# Customization

Everything is in `config.env`. Re-run `./install.sh` (or just the affected
module) after editing.

## Use your own domain

Set `DOMAIN` to anything on a Cloudflare-managed zone you own:

```bash
DOMAIN="pi.example.com"        # or tesla.example.org, or just example.org
```

Re-run modules 07 + 08:

```bash
./install.sh 07-letsencrypt 08-dns-hijack
```

The cert is valid for whatever name you set; the dnsmasq hijack updates to
match. No public A record is required.

### Wildcard cert

To cover multiple subdomains, switch to a wildcard. In
`modules/07-letsencrypt.sh`, change the `--issue` line to:

```sh
"$ACME" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --server letsencrypt
```

(Cloudflare DNS-01 supports wildcards out of the box.)

## Different SSID / password

```bash
HOTSPOT_SSID="MyCarHotspot"
HOTSPOT_PASSWORD="something-better"
```

Re-run module 03:

```bash
./install.sh 03-wifi-hotspot
```

## Different upstream than iPhone

Anything that surfaces as a Linux network interface works. To use, e.g., a
USB-C ethernet adapter:

- Plug it in; NM should auto-create a connection.
- Set its `route-metric` lower than `eth0`'s in `04-routing-bypass.sh` (or
  manually with `nmcli`).
- The TTL rewrite rule references `$TETHER_IFACE`. Edit the variable in the
  generated `/etc/nftables.d/ttl-fix.conf` to match the new interface name.

## Different Bluetooth class for stubborn cars

Set `BT_DEVICE_CLASS`:

| Value | Meaning |
|-------|---------|
| `0x240404` | Audio/Video → Headphones (**default**, what Tesla pairs as A2DP) |
| `0x240414` | Audio/Video → Loudspeaker |
| `0x240418` | Audio/Video → Headset+Speaker |
| `0x5A020C` | Phone, smartphone with audio + telephony + networking (historical — Tesla pairs HFP only) |

Re-run module 09. See [`docs/troubleshooting.md`](troubleshooting.md) for
why Headphones beats Phone on Tesla.

## HDMI capture overrides (module 12)

`hdmi-capture.py` reads env vars at launch — set them in the desktop
launcher's `Exec=` line, or run from a terminal:

| Var | Default | Notes |
|-----|---------|-------|
| `HDMI_DEV` | `/dev/video0` | First UVC device. Use `/dev/video1` if you have a second cam. |
| `HDMI_FPS` | `60` | Drop to `30` for bandwidth-constrained KasmVNC. |
| `HDMI_W` / `HDMI_H` | `1920` / `1080` | Match the source; 1280×720 saves a lot of CPU. |
| `HDMI_AUDIO_SRC` | auto | PulseAudio source name; override if your stick isn't named `MACROSILICON_*`. |

## CarPlay overrides (module 13)

| Var | Default | Notes |
|-----|---------|-------|
| `CARPLAY_URL` | `http://localhost:5005/` | The carplay-web-app build served by `carplay-server.service`. |
| `CARPLAY_AUDIO_SRC` | auto | PulseAudio source name for the dongle (matches `Auto_Box` / `Magic_Communication` / `Carlinkit` / `CCPA`). |

## KasmVNC resolution / framerate

Tune for your client device. Tesla's center display works well at 1280×720,
24 fps. For a phone screen, 1024×600 or even 800×480 is more responsive.

```bash
KASMVNC_RES_W=1024
KASMVNC_RES_H=600
KASMVNC_FPS=20
```

Re-run module 06.

## Skip modules

The installer accepts module names:

```bash
./install.sh 03-wifi-hotspot 06-kasmvnc
```

You can also run them by hand:

```bash
bash modules/03-wifi-hotspot.sh
```

## Persistent across SD card swaps

Most state lives in `/etc/` and `/home/$USER/`. To replicate this Pi to
another:

1. `git clone` this repo + bring `config.env`.
2. `./install.sh`.
3. Restore your KasmVNC password, BT pairings, and Cloudflare token.
