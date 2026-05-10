#!/bin/bash
# 10: install the BT Audio Manager GUI + desktop launcher.
. "$(dirname "$0")/../lib/common.sh"
load_config

step "10 — BT Audio Manager (GUI)"

INSTALL_DIR="$HOME/bt-audio"
mkdir -p "$INSTALL_DIR" "$HOME/Desktop" "$HOME/.config/libfm"

# Copy script
cp "$PROJECT_ROOT/templates/btaudio.py" "$INSTALL_DIR/btaudio.py"
chmod +x "$INSTALL_DIR/btaudio.py"

# Render and install .desktop
INSTALL_DIR="$INSTALL_DIR" envsubst < "$PROJECT_ROOT/templates/btaudio.desktop.tmpl" \
  > "$HOME/Desktop/btaudio.desktop"
chmod +x "$HOME/Desktop/btaudio.desktop"

# pcmanfm: don't ask "execute / run in terminal" prompt
if [[ ! -f "$HOME/.config/libfm/libfm.conf" ]]; then
  cp /etc/xdg/libfm/libfm.conf "$HOME/.config/libfm/libfm.conf" 2>/dev/null || true
fi
if [[ -f "$HOME/.config/libfm/libfm.conf" ]] && \
   ! grep -q '^quick_exec=' "$HOME/.config/libfm/libfm.conf"; then
  sed -i 's|^\[config\]|[config]\nquick_exec=1|' "$HOME/.config/libfm/libfm.conf"
fi

# Mark trusted (quick_exec covers it, but belt-and-braces)
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
  gio set "$HOME/Desktop/btaudio.desktop" "metadata::trusted" true 2>/dev/null || true

ok "BT Audio Manager installed at $INSTALL_DIR; icon on desktop."
