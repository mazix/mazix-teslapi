#!/bin/bash
# 08: dnsmasq override → resolve $DOMAIN to $HOTSPOT_IP for hotspot clients.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "08 — DNS hijack ($DOMAIN → $HOTSPOT_IP)"

sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
DOMAIN="$DOMAIN" HOTSPOT_IP="$HOTSPOT_IP" \
  envsubst < "$PROJECT_ROOT/templates/dnsmasq-domain.conf.tmpl" | \
  sudo tee "/etc/NetworkManager/dnsmasq-shared.d/${DOMAIN}.conf" > /dev/null

# Reload hotspot so dnsmasq picks the new override
log "Reloading hotspot to pick up DNS override..."
sudo nmcli connection down pi-hotspot >/dev/null 2>&1 || true
sleep 1
sudo nmcli connection up pi-hotspot >/dev/null

ok "Clients on '$HOTSPOT_SSID' will now resolve $DOMAIN → $HOTSPOT_IP."
