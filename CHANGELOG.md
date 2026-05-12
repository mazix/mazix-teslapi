# Changelog

All notable changes to this project, newest first. Each entry references
the commit hash so you can `git show <hash>` for the actual diff. Items
marked **live-only** were applied to the running Pi but not committed to
the repo (yet) — they're either user-specific (Turkish keyboard layout)
or out-of-scope tweaks (mate-polkit duplicate suppression).

## 2026-05-12 — HDMI capture + CarPlay/AA kiosks land

### Added
- **HDMI capture viewer** (module 12). One-tap fullscreen of a USB HDMI
  capture stick (tested MS2109) via `mpv av://v4l2:/dev/video0`. Auto-
  detects the dongle's USB audio source by name and `pactl module-loopback`
  routes it to the active default sink — so a Xiaomi TV Stick plays to
  whatever the user has wired (BT-to-Tesla, BT speaker, local HDMI).
  Custom HDMI-plug SVG icon, semi-transparent Tk close-X overlay in the
  bottom-right that survives mpv's fullscreen window. ([8ffd5c4])
- **CarPlay / Android Auto kiosk** (module 13). Carlinkit CPC200-CCPA
  dongle. `node-CarPlay`'s `carplay-web-app` (React + Web Workers +
  WebUSB) runs as a Chromium kiosk on `localhost:5005`. No long-running
  Node bridge — the browser talks the Carlinkit protocol directly via
  WebUSB. Custom car-with-app-grid SVG icon, same close-X overlay.
  udev rule grants the logged-in user access to vendor 1314 product
  1521. Module clones the upstream repo, npm-installs + builds the React
  SPA, stages it at `~/carplay/web-dist`, wires up a systemd unit, and
  drops the desktop launcher. ([b880fd1])

### Known open issue
- CarPlay **audio is silent so far**. Video + touch + handshake work on
  both KasmVNC (SwiftShader software WebGL) and hwaccel (V3D hardware
  WebGL) backends. fps 60→30 doesn't change anything; render layer
  isn't the bottleneck. Hypothesis: AudioWorklet / `pcm-ringbuf-player`
  isn't reaching the default PulseAudio sink — direct `paplay` to the
  same sink works fine. Next step: DevTools console during fresh
  launch to see AudioContext state + `getUserMedia` outcome.

## 2026-05-12 — GUI + dual-stack polish

### Added
- **Tk GUI switcher** for the display backend: desktop icon `Display
  Backend` opens a small window with `Active now` / `Boot default`
  radio groups + Apply / Save / Refresh / Close buttons + a live
  status panel. ([9fbd838])
- **NOPASSWD sudoers rule** locked to `/usr/local/bin/tesla-display`
  so the GUI can switch backends without a password prompt and without
  granting the user general sudo. ([9fbd838])

### Fixed
- `tesla-display status` output was duplicating "unknown" lines because
  the `|| echo unknown` fallback ran *after* `systemctl is-active` had
  already printed `inactive` to stdout. Removed the fallback. ([9fbd838])
- `tesla-display` user-service calls were failing when the script ran
  via `sudo` (the GUI's path) because `systemctl --user` needs the
  user's DBus session. Added a `user_systemctl` helper that switches
  to `runuser -u pi env XDG_RUNTIME_DIR=/run/user/1000` when we're
  root, falls back to direct `systemctl --user` when we're already
  pi. ([9fbd838])
- `tesla-display-boot` (boot-time applier) was originally trying to
  call `systemctl --user` itself, which fails at boot because no user
  DBus session is up yet. Rewrote it to only touch system services
  and nft; linger keeps the KasmVNC user service alive independently.
  Bug surfaced after a reboot: the boot service exited 1, no nft rule
  got written, and `https://pi.tesladock.com` timed out until we put
  the rule back by hand. ([fd5eae9])

## 2026-05-11 — The Tesla wall: PNA, A2DP, and assorted bugs

The browser on Tesla refused to load `pi.tesladock.com` while every
other client on the hotspot worked. Three independent walls, fixed in
sequence. Full debugging notes in `docs/troubleshooting.md`.

### Added
- **Hardware-accelerated display backend** (optional, kept disabled by
  default). `x11vnc` binds to the real `:0` Xorg session (HDMI, V3D
  GPU) and serves its framebuffer through `websockify` + `noVNC` on
  port 8444 with the existing Let's Encrypt cert. A `tesla-display`
  CLI (kept in `/usr/local/bin/`) flips the nft 443 redirect between
  8443 (KasmVNC) and 8444 (hwaccel); the choice is persisted to
  `/etc/tesla-display/active` and reapplied at boot by a oneshot
  service.
  Decision after live A/B test: KasmVNC's WebP/video-region encoder
  beats classic RFB on the same Pi for video-heavy work, so default
  stays KasmVNC. Hwaccel is the right answer for GPU-bound work
  (IDE/CAD/WebGL) and the foundation for any future Sunshine + H.264
  experiment. ([fd5eae9])
- **HTTP `:80` → 301 redirector** (small Python service). Some
  browsers — including Tesla's Chromium when there's no HSTS entry —
  try `http://` before `https://`. With nothing on `:80` the kernel
  was sending TCP RST and the browser showed
  `ERR_CONNECTION_REFUSED`. ([6ac7336])
- **Documented Tesla's Private Network Access (PNA)** behaviour at
  length in `docs/troubleshooting.md` with a tcpdump signature so the
  next person hitting it can match the pattern in one step.
  ([96a5f3b])
- **Documented the public DNS A-record requirement** in
  `docs/prerequisites.md`. Modern browsers (Tesla's Chromium, macOS
  iCloud Private Relay, Chrome Secure DNS) issue DoH queries to public
  resolvers and ignore the Pi's local dnsmasq hijack, so the public
  answer has to match the local one. ([7db4bd0])

### Changed
- `HOTSPOT_IP` default `10.42.0.1` → **`198.51.100.1`** (RFC 5737
  TEST-NET-2). RFC 1918 is in Chromium's PNA "private" set; resolving
  a public hostname to it makes Tesla's browser silently abort with
  zero TCP SYNs. TEST-NET is not in the private set, not BGP-routable,
  and reserved for documentation — no collisions, no PNA trigger.
  ([4f22b3f])
- `BT_DEVICE_CLASS` default `0x5A020C` (phone) → **`0x240404`**
  (Audio/Video → Headphones). Tesla pairs phone-class devices for
  calls only (HFP/HSP) and never offers an A2DP profile, even after
  pairing. Headphones class makes Tesla treat the Pi as a Bluetooth
  speaker / media device from the first pair; A2DP opens on connect
  and audio runs stereo 48 kHz. ([d331605])
- README architecture diagram + "What you get" rewritten to mention
  TEST-NET-2 and the Headphones class, plus pointers to
  troubleshooting for the reasoning. ([4f22b3f], [d331605])

### Fixed
- **HTTPS leak on hotspot clients**: the nft `:443 → :8443` redirect
  was matching *forwarded* traffic too, so any HTTPS site a hotspot
  client visited got rerouted to KasmVNC, which served
  `pi.tesladock.com`'s cert for unrelated origins — every site showed
  `NET::ERR_CERT_COMMON_NAME_INVALID`. Scoped the redirect with
  `fib daddr type local` so only packets aimed at this host match.
  ([64d88be])
- `modules/03-wifi-hotspot.sh` was setting `ipv4.method=shared` on the
  NetworkManager connection but never `ipv4.addresses`, so
  `HOTSPOT_IP` in `config.env` was *advertised in log messages but
  silently ignored*. NM fell back to 10.42.0.1/24 every time. Module
  03 now plumbs `ipv4.addresses=$HOTSPOT_IP/24`. ([4f22b3f])
- `modules/09-bluetooth-audio.sh` used
  `sed -i s|^#?Class\s*=.*|Class = $BT_DEVICE_CLASS|`, which is a
  *no-op* when `/etc/bluetooth/main.conf` ships without a `Class =`
  line at all (Trixie's default). Now the module checks first and
  appends under `[General]` if missing. ([d331605])

## 2026-05-10 — Initial publication

### Added
- **`tesla-pi-station` v0**: full installer modules 01-10 covering Pi
  hotspot (NM `shared`), iPhone USB tether with TTL=65 carrier bypass,
  KasmVNC remote desktop with Let's Encrypt cert via Cloudflare
  DNS-01, dnsmasq hostname hijack, BlueZ + PipeWire BT audio source,
  and a small Tk pairing GUI. Idempotent modules, `config.env` driven,
  uninstall script included. ([1985545])
- **`ROADMAP.md`** with HDMI capture, USB-dongle CarPlay/Android Auto,
  OBD-II, dashcam, multi-zone audio, companion mobile app, captive
  portal, voice control. Includes a safety/responsibility section
  (in-motion features are passenger-only). ([5d516c9])

---

## Live-only adjustments (not yet in the repo)

These were applied to the running Pi during the 2026-05-11/12 session
and work, but the corresponding install module/template hasn't been
committed yet. If you reinstall from a clean checkout you'll need to
redo these by hand.

- **matchbox-keyboard panel launcher** (`~/.local/bin/matchbox-keyboard-toggle`
  with PID-file based open/close + `xdotool` bottom-dock, panel button
  injected directly into `~/.config/lxpanel-pi/panels/panel`).
- **Turkish QWERTY alphanumeric layout** (`/usr/share/matchbox-keyboard/
  keyboard-tr.xml`, custom XML wrapping `base-fragment-tr_TR.xml` plus
  a numeric row).
- **mate-polkit autostart override** (`~/.config/autostart/
  polkit-mate-authentication-agent-1.desktop` with `Hidden=true`) —
  suppresses the GDBus "agent already exists" popup on LXDE-pi.
- **Default Chromium cache wipe**: `~/.cache/chromium` was 760 MB with
  a stale index; clearing it removed cold-start lag for non-KasmVNC
  use of Chromium. No structural fix — just a maintenance note.

If any of these are worth repo'ing, a future module `10b-desktop-tweaks.sh`
could bundle them.

[b880fd1]: https://github.com/mazix/tesla-pi-station/commit/b880fd1
[8ffd5c4]: https://github.com/mazix/tesla-pi-station/commit/8ffd5c4
[9fbd838]: https://github.com/mazix/tesla-pi-station/commit/9fbd838
[fd5eae9]: https://github.com/mazix/tesla-pi-station/commit/fd5eae9
[d331605]: https://github.com/mazix/tesla-pi-station/commit/d331605
[96a5f3b]: https://github.com/mazix/tesla-pi-station/commit/96a5f3b
[4f22b3f]: https://github.com/mazix/tesla-pi-station/commit/4f22b3f
[7db4bd0]: https://github.com/mazix/tesla-pi-station/commit/7db4bd0
[6ac7336]: https://github.com/mazix/tesla-pi-station/commit/6ac7336
[64d88be]: https://github.com/mazix/tesla-pi-station/commit/64d88be
[5d516c9]: https://github.com/mazix/tesla-pi-station/commit/5d516c9
[1985545]: https://github.com/mazix/tesla-pi-station/commit/1985545
