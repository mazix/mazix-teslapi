#!/bin/bash
# 05: install :443 → :8443 redirect.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "05 — Port redirect 443 → 8443"

sudo mkdir -p /etc/nftables.d
sudo cp "$PROJECT_ROOT/templates/port-redirect.nft" /etc/nftables.d/port-redirect.conf
sudo nft -f /etc/nftables.d/port-redirect.conf

ok "Port redirect installed. https://${DOMAIN} → KasmVNC :8443"
