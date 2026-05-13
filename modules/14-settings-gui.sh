#!/bin/bash
# 14: maziX TeslaPI Settings — single tabbed GUI replacing the older two
# standalone launchers (Pi BT Audio + Display Backend). Bluetooth pairing
# and audio routing, display-backend switching, and an About tab in one
# window with a custom ttk dark theme.
. "$(dirname "$0")/../lib/common.sh"
# Infrastructure-only module; doesn't read config.env.
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
require_sudo

step "14 — maziX TeslaPI Settings (unified BT + Display GUI)"

INSTALL_DIR="$HOME/teslapi-settings"
mkdir -p "$INSTALL_DIR" "$HOME/Desktop"

log "Deploying GUI + icon"
cp "$PROJECT_ROOT/templates/teslapi-settings.py" "$INSTALL_DIR/teslapi-settings.py"
cp "$PROJECT_ROOT/templates/teslapi-settings.svg" "$INSTALL_DIR/teslapi-settings.svg"
chmod +x "$INSTALL_DIR/teslapi-settings.py"

log "Installing desktop launcher"
INSTALL_DIR="$INSTALL_DIR" envsubst \
    < "$PROJECT_ROOT/templates/teslapi-settings.desktop.tmpl" \
    > "$HOME/Desktop/teslapi-settings.desktop"
chmod +x "$HOME/Desktop/teslapi-settings.desktop"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
    gio set "$HOME/Desktop/teslapi-settings.desktop" "metadata::trusted" true 2>/dev/null || true

log "Removing legacy standalone GUIs (Pi BT Audio + Display Backend)"
rm -f "$HOME/Desktop/btaudio.desktop" \
      "$HOME/Desktop/tesla-display-gui.desktop"
rm -rf "$HOME/bt-audio" "$HOME/tesla-display-gui"

ok "maziX TeslaPI Settings installed at $INSTALL_DIR"
echo
echo "Desktop icon: $HOME/Desktop/teslapi-settings.desktop"
echo "CLI test:     python3 $INSTALL_DIR/teslapi-settings.py"
