#!/bin/bash
# Best-effort uninstall for tesla-pi-station.
# Reverts the changes made by install.sh. Won't delete acme.sh data.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$SCRIPT_DIR"

if [[ -f "$SCRIPT_DIR/config.env" ]]; then
  set -a; . "$SCRIPT_DIR/config.env"; set +a
fi

. "$SCRIPT_DIR/lib/common.sh"

read -r -p "This will stop services and remove configs. Continue? [y/N] " a
[[ "$a" =~ ^[Yy]$ ]] || exit 0

require_sudo

step "Stopping user services"
systemctl --user disable --now kasmvnc.service bt-agent.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/kasmvnc.service" \
      "$HOME/.config/systemd/user/bt-agent.service"
systemctl --user daemon-reload

step "Removing nftables drop-ins"
sudo rm -f /etc/nftables.d/ttl-fix.conf /etc/nftables.d/port-redirect.conf
sudo nft list ruleset > /tmp/nft.bak || true
sudo systemctl restart nftables 2>/dev/null || true

step "Removing dnsmasq override"
[[ -n "${DOMAIN:-}" ]] && \
  sudo rm -f "/etc/NetworkManager/dnsmasq-shared.d/${DOMAIN}.conf"

step "Removing hotspot connection"
sudo nmcli connection down pi-hotspot 2>/dev/null || true
sudo nmcli connection delete pi-hotspot 2>/dev/null || true

step "Removing GUI app"
rm -rf "$HOME/bt-audio"
rm -f "$HOME/Desktop/btaudio.desktop"

step "Resetting BT class to default (computer)"
sudo sed -i 's|^Class\s*=.*|#Class = 0x000100|' /etc/bluetooth/main.conf || true
sudo systemctl restart bluetooth || true

step "Removing ipheth autoload"
sudo rm -f /etc/modules-load.d/ipheth.conf

cat <<MSG

Uninstall done. Things kept (delete manually if you want):
  ~/.vnc/                   (KasmVNC user state, certs)
  ~/.acme.sh/               (acme.sh + Let's Encrypt account/certs)
  KasmVNC package          (sudo apt remove kasmvncserver)
  apt packages from 01-prereqs (didn't auto-remove to avoid breaking)
MSG
