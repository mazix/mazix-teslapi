#!/bin/bash
# 04: route metrics + nftables TTL rewrite for hotspot bypass.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "04 — Routing & TTL bypass"

# Detect tether interface (or fall back to hint)
if iface=$(detect_tether_iface); then
  log "Detected tether interface: $iface"
else
  iface="$TETHER_IFACE_HINT"
  warn "No tether interface auto-detected. Falling back to '$iface'."
  warn "Plug iPhone in with Personal Hotspot enabled, then re-run."
fi
export TETHER_IFACE="$iface"

# Bump tether to higher priority than ethernet (lower metric = higher pref)
ETH_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2=="eth0"{print $1}' | head -1)
TET_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v i="$iface" '$2==i{print $1}' | head -1)

if [[ -n "$ETH_CON" ]]; then
  log "Setting metric 700 on '$ETH_CON' (eth0)"
  sudo nmcli connection modify "$ETH_CON" ipv4.route-metric 700 || true
fi
if [[ -n "$TET_CON" ]]; then
  log "Setting metric 100 on '$TET_CON' ($iface)"
  sudo nmcli connection modify "$TET_CON" ipv4.route-metric 100 || true
  sudo nmcli connection modify "$TET_CON" ipv6.method ignore || true
  sudo nmcli connection up "$TET_CON" >/dev/null || true
fi

# nftables TTL rule
log "Installing /etc/nftables.d/ttl-fix.conf"
sudo mkdir -p /etc/nftables.d
TETHER_IFACE="$iface" envsubst < "$PROJECT_ROOT/templates/ttl-fix.nft" | \
  sudo tee /etc/nftables.d/ttl-fix.conf > /dev/null

# Make sure /etc/nftables.conf includes our drop-in dir
if ! sudo grep -q '/etc/nftables.d/' /etc/nftables.conf 2>/dev/null; then
  echo 'include "/etc/nftables.d/*.conf"' | sudo tee -a /etc/nftables.conf > /dev/null
fi

log "Reloading nftables..."
sudo systemctl enable --now nftables
sudo nft -f /etc/nftables.d/ttl-fix.conf

ok "TTL rewrite active on $iface (TTL=65)."
sudo nft list table inet ttlfix
