# Prerequisites

## Hardware

- **Raspberry Pi 5** (8 GB recommended for fluid browsing). Pi 4 will work
  but encoding fullscreen video over KasmVNC is tighter.
- A USB-A or USB-C cable from iPhone to a Pi USB 2.0 or 3.0 port.
- Optional: a small HDMI display + keyboard for first boot. After that
  everything is reachable over the network.

### Optional hardware for media modules

These are needed only if you enable the matching module — the core
hotspot + KasmVNC stack does not require them.

- **USB HDMI capture stick** (module 12, `12-hdmi-capture.sh`) — any
  cheap **UVC** capture dongle based on the **MacroSilicon MS2109** or
  **MS2130** chipset. Many brands rebrand the same hardware; one
  example we've tested with is the
  [Apera GA06 USB-C 1080p60](https://www.trendyol.com/apera/ga06-type-c-3-1-to-hdmi-1080p-60hz-4k-30hz-video-capture-goruntu-yakalama-karti-p-934269466).
  The stick presents one `/dev/videoN` (V4L2) plus a USB-audio source
  named `MACROSILICON_USB_Video` / similar — module 12 picks both up
  automatically. 1080p30 is the safe ceiling on a Pi 5 over KasmVNC;
  1080p60 works on the hwaccel backend.
- **Carlinkit CCPA wireless CarPlay / Android Auto dongle** (module
  13, `13-carplay.sh`) — the
  [Carlinkit CPC200-CCPA](https://www.hepsiburada.com/carlinkit-ccpa-kablosuz-apple-carplay-android-auto-android-multimedya-ekrani-donusturucu-cpc200-ccpa-pm-HBC000059X6G5)
  (USB ID `1314:1521`, advertised as **Magic Communication Auto Box**).
  Older `1314:1520` variants share the same udev rule. The dongle does
  the wireless pairing with the phone; the Pi only sees a USB device
  speaking Carlinkit's protocol over WebUSB.

## Software

- **Raspberry Pi OS Trixie**, fresh install or up to date.
- The installer will switch the desktop session to **X11** (Wayland is the
  default but KasmVNC needs X11). It runs `raspi-config nonint do_wayland 1`
  for you. A reboot is recommended after install.

## Network

- **A domain you own** with DNS hosted at Cloudflare. Free tier is fine.
  - **Add a public DNS-only A record** for the hostname you'll use,
    pointing at the Pi's hotspot IP. With the default config that is
    `pi.your.domain  A  198.51.100.1`, proxy off (gray cloud).
  - Two reasons we need this record on public DNS:
    1. Modern browsers (Tesla's Chromium, macOS with iCloud Private
       Relay, Chrome/Firefox Secure DNS) issue DNS-over-HTTPS queries to
       public resolvers and **bypass the Pi's local dnsmasq hijack**.
       Publishing the same answer on public DNS makes both paths
       consistent.
    2. The hotspot IP itself is a **TEST-NET / RFC 5737** address
       (`198.51.100.0/24`), not RFC 1918. We use TEST-NET so Chromium's
       Private Network Access (PNA) check treats the response as a
       public address and lets the connection proceed; an RFC 1918
       answer would be rejected silently on Tesla's browser. See
       `docs/troubleshooting.md` for the full story.
  - TEST-NET is not routable on the internet, so this record leaks
    nothing useful externally — only clients on the Pi's hotspot can
    reach the IP.
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
