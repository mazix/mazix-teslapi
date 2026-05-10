# Roadmap

A living list of ideas to grow `tesla-pi-station` from "Pi as Tesla browser"
into a full mobile entertainment + diagnostics hub.

## ✅ Shipped (v0.1)

- Pi as Wi-Fi access point
- iPhone USB tether as upstream
- Carrier hotspot detection bypass (TTL/HopLimit=65)
- KasmVNC remote desktop with Let's Encrypt cert (Cloudflare DNS-01)
- Domain DNS hijack on hotspot — port-less `https://your.domain`
- Bluetooth audio source advertised as a phone (Tesla-compatible)
- Tk GUI for Bluetooth pairing
- Headless boot via systemd user services + linger
- Modular, idempotent installer

## 🎮 HDMI capture — bring any HDMI device into the car

Plug *anything* with HDMI out into a cheap USB HDMI capture card on the Pi,
and watch it inside the same Tesla browser tab. Targets we want first-class
support for:

- 🕹️ **PlayStation / Xbox / Nintendo Switch** — gaming on the road while the
  car is parked / charging.
- 📺 **Apple TV** — full tvOS app catalog (Netflix, Apple TV+, AirPlay
  receiver) without depending on the Tesla's own apps.
- 🤖 **Android TV / Google TV / Chromecast** — sideload anything, cast from
  a phone, Smart TV browsers.
- 💻 **Laptops, mini-PCs, smartphones** with USB-C → HDMI dongles.

The Pi captures the HDMI stream over v4l2, renders it fullscreen on the X
session, and KasmVNC streams the result out to the car. Audio rides along
on either the BT speaker route or back to the car directly.

**Plan:**

- New module `11-hdmi-capture.sh`:
  - Detect MS2109/MS2130 capture sticks automatically (the cheap UVC ones).
  - Install `mpv`, `v4l-utils`, `ffmpeg`.
  - Provide a launcher that runs
    `mpv av://v4l2:/dev/video0 --fs --profile=low-latency`.
- Tk GUI `hdmi-input.py`:
  - List video devices with their supported modes.
  - Pick resolution / framerate.
  - "Play" button → fullscreen mpv.
  - "Audio" routing — mirror device audio to BT speaker / Tesla.
- Per-source presets (1080p60 / 1080p30 / MJPEG depending on bandwidth).
- Optional: side-by-side or PiP layout for game + chat / map.
- Optional: pair BT controllers (DualSense, Xbox Wireless, Switch Pro)
  directly with the Pi for input passthrough where the source allows it.

## 📱 CarPlay & Android Auto — native web app, no HDMI

Wireless CarPlay/Android Auto dongles (Carlinkit U2W, AAWireless, Ottocast,
etc.) pair with the phone over Wi-Fi/BT and present themselves to a *USB
host* speaking the CarPlay or Android Auto protocol. Instead of going through
HDMI capture, we plug the dongle straight into the Pi via USB and write a
small server that:

1. Speaks the dongle's USB protocol (H.264 video + touch + audio).
2. Decodes the H.264 stream.
3. Exposes the video and touch surface to a web app (WebSocket + canvas).
4. Routes audio through PipeWire to the BT speaker / Tesla.

The Tesla browser opens our web app at, say, `https://carplay.your.domain`
and gets a real CarPlay (or Android Auto) interface — Apple Maps, Spotify,
WhatsApp, Google Maps, Waze — with touch input working through Tesla's
touchscreen.

**Plan:**

- New module `12-carplay-server.sh`:
  - Install Node + a small server based on existing open-source projects
    (e.g. `node-carplay`, `carplay-receiver`-style protocol implementations).
  - systemd user service for the server.
  - nftables drop-in to expose it on its own subdomain / port.
- Web app `apps/carplay/`:
  - Renders the H.264 stream in a `<video>` element via MSE / WebCodecs.
  - Captures pointer / touch events and forwards to the dongle.
  - Audio: WebRTC track or routed locally on the Pi.
- Per-dongle profiles (different USB IDs and quirks).
- Auto-launch from a "CarPlay" / "Android Auto" tile on the Pi desktop.
- Bluetooth controller / mic passthrough for Siri / Google Assistant.

## 🚗 Future ideas

| Idea | Why | Sketch |
|------|-----|--------|
| **OBD-II live overlay** | See real-time car telemetry on the Pi screen | USB ELM327 + Python parser, overlay panel in LXDE |
| **Backup / dashcam** | USB webcam → fullscreen viewer with motion detect | UVC cam + a simple recorder |
| **Multi-zone audio** | Same source to BT speaker *and* car AUX | PipeWire combined-sink |
| **Companion mobile app** | One-tap launch of YouTube/Disney/etc. + audio routing | Phone web app served by Pi, talks to Pi via local API |
| **Auto-update** | `tesla-pi-station-update` keeps modules current | systemd timer pulling this repo, runs `install.sh` for changed modules |
| **Wildcard cert** | One cert covers `pi.`, `media.`, `obd.` etc. | Tweak `07-letsencrypt.sh` to issue `*.${DOMAIN}` |
| **5 GHz hotspot** | Faster, less crowded | Either an external USB Wi-Fi card with AP mode, or Pi 5 firmware updates |
| **Fail-over upstream** | When iPhone disconnects, fall back to a 4G USB modem | NM connection priorities + dnsmasq restart on link change |
| **Captive portal** | Auto-open KasmVNC when Tesla joins the SSID | `iptables`/`nft` redirect HTTP to Pi + tiny redirect server |
| **Voice control** | "Hey Pi, switch to PlayStation" | whisper.cpp on Pi 5, mqtt-style action bus |

---

## ⚠️ Safety & responsibility

This project ships features that *technically* work while the car is moving.
That is your call, not the project's. **Driver attention belongs on the
road.** Watching video, gaming, or browsing while you are operating a
vehicle is dangerous and is illegal in most jurisdictions — Tesla itself
disables many of its own infotainment features above 0 km/h for exactly
this reason.

By using `tesla-pi-station` you accept that:

- You alone are responsible for **when, where and how** you use it.
- The maintainers and contributors **disclaim all liability** for accidents,
  fines, injuries, voided warranties, carrier disputes, or any other
  consequences of using this project.
- Carrier "unlimited" plans often have fair-use clauses; the TTL bypass is
  intended for users whose plans don't *technically* exclude tethering. Read
  your contract.
- Local laws on screen use while driving, on Bluetooth tethering, and on
  data routing may apply.

Treat the in-motion features as **passenger-only**. Don't watch the
PlayStation while merging onto the highway.

## How to suggest

Open an issue with the `idea` label, or a draft PR with the module skeleton.
Each module should be:

- Idempotent (re-run-safe).
- Self-contained (no cross-module file editing).
- Templated (read from `config.env`).
- Documented in `README.md` + a section here when shipped.
