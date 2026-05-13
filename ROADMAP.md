# Roadmap

A living list of ideas to grow `maziX TeslaPI` from "Pi as Tesla browser"
into a full mobile entertainment + diagnostics hub.

## ✅ Shipped

**Core (v0.1)**

- Pi as Wi-Fi access point on RFC 5737 TEST-NET-2 (bypasses Tesla
  Chromium's Private Network Access check).
- iPhone USB tether as upstream.
- Carrier hotspot detection bypass (TTL/HopLimit=65).
- KasmVNC remote desktop with Let's Encrypt cert (Cloudflare DNS-01).
- Domain DNS hijack on hotspot — port-less `https://your.domain`,
  with a matching public DNS-only A record so DoH-using clients land
  on the same answer.
- Bluetooth A2DP source advertised as Audio/Video Headphones
  (class `0x240404`) — what Tesla actually opens A2DP for, not phone
  class.
- Tk GUI for Bluetooth pairing.
- Headless boot via systemd user services + linger.
- Modular, idempotent installer.

**Display (v0.2)**

- Optional second display backend: x11vnc + noVNC on `:0` with V3D
  acceleration (`tesla-display switch hwaccel`), KasmVNC stays default.
- `tesla-display` CLI + Tk switcher that survives stopping its own
  parent service (uses `systemd-run --user --scope` to escape the
  caller's cgroup).
- Unified **maziX TeslaPI Settings** Tk GUI — Bluetooth, Display, and
  About in one tabbed window (replaces the two older standalone
  launchers).

**Media (v0.3)**

- 🎮 **HDMI capture** ([`modules/12-hdmi-capture.sh`](modules/12-hdmi-capture.sh))
  — UVC capture stick (MS2109 / MS2130, tested with Apera GA06) →
  `mpv` fullscreen + PipeWire loopback to default sink (BT → Tesla
  by default). One-tap desktop launcher with a Tk close overlay so
  it survives a touchscreen-only session. Targets that have been
  exercised: Xiaomi TV Stick, Apple TV, generic HDMI sources via
  USB-C dongles. Console / Switch / PlayStation are the same code
  path.
- 📱 **CarPlay / Android Auto** ([`modules/13-carplay.sh`](modules/13-carplay.sh))
  — Carlinkit CPC200-CCPA (USB `1314:1521`) driven by Chromium kiosk
  + WebUSB via the React `carplay-web-app` from `node-CarPlay`. No
  long-running native daemon: the browser handles the Carlinkit
  protocol + H.264 decode via WebCodecs. Static SPA served by a tiny
  Python http.server at `localhost:5005`. Video and touch work today.
  **Audio is the open issue** (see `CHANGELOG.md`) — render path is
  fine, the loopback chain just never gets a non-silent source on a
  fresh launch; next step is DevTools console inspection.

## 🔜 Next up — CarPlay audio + kiosk launcher

The two things blocking a clean v1.0:

1. **Resolve CarPlay audio silence.** Open a fresh Chromium devtools
   session against the kiosk profile, watch for PcmPlayer / AudioContext
   warnings (gesture policy, sample rate mismatch, suspended worklet),
   correlate with the `pactl list short sources` state when the dongle
   is up. We already auto-load `module-loopback` from the dongle's
   USB-audio source to the default sink — but the dongle may be
   pushing audio over its data endpoint instead, in which case the
   fix is in the web app's PcmPlayer, not on the PipeWire side.
2. **Kiosk-style home launcher** (described below). Replaces the
   LXDE desktop as the primary entry point for the car-facing view.

## 🖥️ Kiosk-style home launcher

Today, opening anything on the Pi means seeing the LXDE-pi desktop —
which looks too much like "a PC inside a car". Goal: a **fullscreen
home grid** that auto-launches on boot, hides the desktop, and lives
in front of everything else. Big touch tiles ("HDMI", "CarPlay",
"Settings", "Web", "Music", "Map", …); tap a tile, the relevant
fullscreen sub-app opens; an always-on-top **Home** overlay button
brings the grid back. The maziX TeslaPI Settings window becomes one
of the tiles.

**Plan:**

- New module `15-home-kiosk.sh`.
- Fullscreen Tk or GTK app, lightdm autostart entry so it greets the
  user at boot (in front of LXDE).
- Tile registry — each tile is a `.desktop` file in a known dir
  (`~/.config/maziX-teslapi/tiles/*.desktop`) with `Name`, `Icon`,
  `Exec`. Module installers drop their own tile. New apps integrate
  without editing the launcher.
- Built-in tiles bind to existing launchers we already have: HDMI
  Capture (module 12), CarPlay/AA (module 13), maziX TeslaPI Settings
  (module 14).
- `Home` overlay button (same transparent X overlay pattern used by
  HDMI/CarPlay) maps to "close current app, return to grid".
- DPMS-off autostart from module 11 already keeps the screen alive.
- Optional secondary view: the same kiosk content served as a web app
  at `https://your.domain/launcher` so a remote client (the Tesla
  itself, a phone) can open it without going through KasmVNC.

This will probably replace the desktop icons as the primary entry
point; the LXDE desktop stays underneath as a fallback / debug surface.

## 🚗 Future ideas

| Idea | Why | Sketch |
|------|-----|--------|
| **OBD-II live overlay** | See real-time car telemetry on the Pi screen | USB ELM327 + Python parser, overlay panel in LXDE |
| **Backup / dashcam** | USB webcam → fullscreen viewer with motion detect | UVC cam + a simple recorder |
| **Multi-zone audio** | Same source to BT speaker *and* car AUX | PipeWire combined-sink |
| **Companion mobile app** | One-tap launch of YouTube/Disney/etc. + audio routing | Phone web app served by Pi, talks to Pi via local API |
| **Auto-update** | `mazix-teslapi-update` keeps modules current | systemd timer pulling this repo, runs `install.sh` for changed modules |
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

By using `maziX TeslaPI` you accept that:

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
