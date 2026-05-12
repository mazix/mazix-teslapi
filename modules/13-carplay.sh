#!/bin/bash
# 13: CarPlay / Android Auto kiosk for a Carlinkit CCPA-class dongle.
#
# Approach: ship the carplay-web-app React build as a static site behind a
# tiny Python http.server, and let Chromium in --app=kiosk mode talk to the
# USB dongle directly via WebUSB. No long-running Node bridge, no native
# bindings at runtime — the heavy lifting (Carlinkit protocol parsing, H.264
# decode via WebCodecs, audio playback) all happens inside the browser.
. "$(dirname "$0")/../lib/common.sh"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
require_sudo

step "13 — CarPlay / Android Auto kiosk (Carlinkit CCPA)"

log "Installing packages: npm, libudev-dev, chromium"
sudo apt install -y npm libudev-dev chromium

INSTALL_DIR="$HOME/carplay"
mkdir -p "$INSTALL_DIR" "$HOME/Desktop"

log "Cloning node-CarPlay (rhysmorgan134) if not present"
if [[ ! -d "$INSTALL_DIR/node-CarPlay" ]]; then
    git clone --depth 1 https://github.com/rhysmorgan134/node-CarPlay.git \
        "$INSTALL_DIR/node-CarPlay"
fi

log "Building node-carplay root + carplay-web-app (slow on Pi: ~5-10 min)"
(cd "$INSTALL_DIR/node-CarPlay" && npm install --no-audit --no-fund)
(cd "$INSTALL_DIR/node-CarPlay/examples/carplay-web-app" && \
    npm install --no-audit --no-fund && npm run build)

log "Staging the built SPA at $INSTALL_DIR/web-dist"
rm -rf "$INSTALL_DIR/web-dist"
cp -a "$INSTALL_DIR/node-CarPlay/examples/carplay-web-app/build" \
    "$INSTALL_DIR/web-dist"

log "Deploying udev rule for the dongle (1314:1521)"
sudo install -m 0644 "$PROJECT_ROOT/templates/99-carlinkit.rules" \
    /etc/udev/rules.d/99-carlinkit.rules
sudo udevadm control --reload-rules
sudo udevadm trigger

log "Deploying static-server systemd unit"
sudo install -m 0644 "$PROJECT_ROOT/templates/carplay-server.service" \
    /etc/systemd/system/carplay-server.service
sudo systemctl daemon-reload
sudo systemctl enable --now carplay-server.service

log "Deploying kiosk launcher + icon + desktop shortcut"
cp "$PROJECT_ROOT/templates/carplay-launch.py" "$INSTALL_DIR/carplay-launch.py"
cp "$PROJECT_ROOT/templates/carplay.svg" "$INSTALL_DIR/carplay.svg"
chmod +x "$INSTALL_DIR/carplay-launch.py"
INSTALL_DIR="$INSTALL_DIR" envsubst < "$PROJECT_ROOT/templates/carplay.desktop.tmpl" \
    > "$HOME/Desktop/carplay.desktop"
chmod +x "$HOME/Desktop/carplay.desktop"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
    gio set "$HOME/Desktop/carplay.desktop" "metadata::trusted" true 2>/dev/null || true

ok "CarPlay/AA kiosk installed."
echo
echo "Plug the CCPA dongle, then double-click 'CarPlay / Android Auto' on"
echo "the desktop. First launch will prompt to authorize the USB device."
echo "Test server manually with:"
echo "  curl -sI http://localhost:5005/ | head -1"
