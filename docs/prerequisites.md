# Prerequisites

## Hardware

- **Raspberry Pi 5** (8 GB recommended for fluid browsing). Pi 4 will work
  but encoding fullscreen video over KasmVNC is tighter.
- A USB-A or USB-C cable from iPhone to a Pi USB 2.0 or 3.0 port.
- Optional: a small HDMI display + keyboard for first boot. After that
  everything is reachable over the network.

## Software

- **Raspberry Pi OS Trixie**, fresh install or up to date.
- The installer will switch the desktop session to **X11** (Wayland is the
  default but KasmVNC needs X11). It runs `raspi-config nonint do_wayland 1`
  for you. A reboot is recommended after install.

## Network

- **A domain you own** with DNS hosted at Cloudflare. Free tier is fine.
  - **Add a public A record** for the hostname you'll use, pointing at the
    Pi's hotspot IP — e.g. `pi.your.domain  A  10.42.0.1`, DNS-only (proxy
    off). The Pi's hotspot dnsmasq also hijacks this name locally, but
    modern browsers (Tesla's Chromium, macOS with iCloud Private Relay,
    Chrome/Firefox secure DNS) issue DNS-over-HTTPS queries to public
    resolvers and bypass the local hijack. Publishing the private IP on
    public DNS makes both paths return the same answer. The private IP is
    only reachable from clients joined to the hotspot, so this leaks
    nothing useful externally.
- **Cloudflare API token**, scoped:
  - Permissions: *Zone → DNS → Edit*
  - Zone Resources: *Include → Specific zone → your-zone.com*
  - Create at: My Profile → API Tokens → Create Token → Edit zone DNS template.
  - Copy the token once; you'll paste it into `config.env`.

## iPhone

- iOS with **Personal Hotspot** capable plan.
- "Allow Others to Join" enabled.
- USB cable plugged in. On first connect, tap **Trust** when prompted.
- An **unlimited cellular data plan** if you intend to actually use this for
  Tesla browsing/streaming. Tethering bypass tricks data routing, not
  billing — your contract terms still apply.

## Skills assumed

- Comfortable with `sudo`, `systemctl`, and editing a `.env` file.
- Cloudflare dashboard navigation (~3 minutes for the API token).
