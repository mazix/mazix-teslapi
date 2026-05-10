#!/bin/bash
# 09: Bluetooth audio source — phone class for Tesla, persistent agent.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "09 — Bluetooth audio source"

# Set device class so Tesla treats Pi as a phone
log "Setting BT class to $BT_DEVICE_CLASS in /etc/bluetooth/main.conf"
sudo sed -i "s|^#\?Class\s*=.*|Class = $BT_DEVICE_CLASS|" /etc/bluetooth/main.conf
grep -E "^Class" /etc/bluetooth/main.conf

sudo systemctl enable --now bluetooth
sudo systemctl restart bluetooth
sleep 2

# Friendly alias
log "Setting BT alias to '$BT_DEVICE_ALIAS'"
bluetoothctl system-alias "$BT_DEVICE_ALIAS" || true
sleep 1
bluetoothctl show | grep -iE "Class|Alias|Name" | head -3

# Persistent pairing agent
log "Installing user systemd service for bt-agent..."
mkdir -p "$HOME/.config/systemd/user"
cp "$PROJECT_ROOT/templates/bt-agent.service" "$HOME/.config/systemd/user/bt-agent.service"
systemctl --user daemon-reload
systemctl --user enable --now bt-agent.service

# Make sure PipeWire-pulse is up (for audio routing)
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true

ok "Bluetooth audio ready. Pair from a sink (speaker/Tesla) and route default sink."
