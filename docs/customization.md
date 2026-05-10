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
| `0x5A020C` | Smartphone with audio + telephony + networking (default) |
| `0x40020C` | Phone with audio + telephony |
| `0x200408` | Phone, mobile minor |
| `0x600204` | Phone, smartphone, audio + info |

Re-run module 09.

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
