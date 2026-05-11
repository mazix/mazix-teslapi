#!/bin/bash
# 05: install :443 → :8443 redirect, plus an HTTP/80 -> HTTPS 301 redirector
# for browsers (e.g. Tesla's Chromium) that try http:// before https://.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "05 — Port redirect 443 → 8443"

sudo mkdir -p /etc/nftables.d
sudo cp "$PROJECT_ROOT/templates/port-redirect.nft" /etc/nftables.d/port-redirect.conf
sudo nft -f /etc/nftables.d/port-redirect.conf

step "05 — HTTP/80 → HTTPS 301 redirector"

sudo install -m 0755 "$PROJECT_ROOT/templates/http-redirect.py" /usr/local/sbin/http-redirect.py
sudo install -m 0644 "$PROJECT_ROOT/templates/http-redirect.service" /etc/systemd/system/http-redirect.service
sudo systemctl daemon-reload
sudo systemctl enable --now http-redirect.service

ok "Port redirect installed. https://${DOMAIN} → KasmVNC :8443  (http:// also redirected)"
