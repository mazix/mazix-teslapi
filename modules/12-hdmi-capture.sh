#!/bin/bash
# 12: USB HDMI capture viewer (e.g. MacroSilicon MS2109 + a Xiaomi/Apple TV /
# console). One-click fullscreen via mpv + PipeWire audio loopback.
. "$(dirname "$0")/../lib/common.sh"
# Module is infrastructure-only; no config.env values needed.
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
require_sudo

step "12 — USB HDMI capture viewer"

log "Installing packages: mpv, v4l-utils, ffmpeg, pulseaudio-utils"
sudo apt install -y mpv v4l-utils ffmpeg pulseaudio-utils

INSTALL_DIR="$HOME/hdmi-capture"
mkdir -p "$INSTALL_DIR" "$HOME/Desktop"

log "Deploying capture script (Python wrapper with floating close button) + icon + launcher"
cp "$PROJECT_ROOT/templates/hdmi-capture.py" "$INSTALL_DIR/hdmi-capture.py"
cp "$PROJECT_ROOT/templates/hdmi-capture.svg" "$INSTALL_DIR/hdmi-capture.svg"
chmod +x "$INSTALL_DIR/hdmi-capture.py"
# Keep the old bash wrapper around for headless / debugging fallback.
cp "$PROJECT_ROOT/templates/hdmi-capture.sh" "$INSTALL_DIR/hdmi-capture.sh" 2>/dev/null || true
chmod +x "$INSTALL_DIR/hdmi-capture.sh" 2>/dev/null || true
INSTALL_DIR="$INSTALL_DIR" envsubst < "$PROJECT_ROOT/templates/hdmi-capture.desktop.tmpl" \
    > "$HOME/Desktop/hdmi-capture.desktop"
chmod +x "$HOME/Desktop/hdmi-capture.desktop"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
    gio set "$HOME/Desktop/hdmi-capture.desktop" "metadata::trusted" true 2>/dev/null || true

if [[ -e /dev/video0 ]]; then
    log "Detected video device(s):"
    for v in /dev/video0 /dev/video1; do
        [[ -e "$v" ]] || continue
        info=$(v4l2-ctl -d "$v" --info 2>/dev/null | grep -E 'Card|Bus' | head -2)
        echo "  $v"; echo "$info" | sed 's/^/    /'
    done
fi

ok "HDMI Capture installed."
echo
echo "Double-click 'HDMI Capture' on the desktop, or run:"
echo "  $INSTALL_DIR/hdmi-capture.sh"
echo
echo "Override knobs (env vars):"
echo "  HDMI_DEV=/dev/video1  $INSTALL_DIR/hdmi-capture.sh"
echo "  HDMI_FPS=30 HDMI_W=1280 HDMI_H=720  $INSTALL_DIR/hdmi-capture.sh"
echo "  HDMI_AUDIO_SRC=<source-name>  $INSTALL_DIR/hdmi-capture.sh"
