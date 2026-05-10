#!/bin/bash
# 07: get a Let's Encrypt cert for $DOMAIN via Cloudflare DNS-01.
. "$(dirname "$0")/../lib/common.sh"
load_config

step "07 — Let's Encrypt cert (Cloudflare DNS-01)"

if [[ -z "${CF_TOKEN:-}" ]]; then
  err "CF_TOKEN is empty in config.env."
  err "Create a scoped token at Cloudflare → My Profile → API Tokens."
  exit 1
fi

# Install acme.sh if missing
if [[ ! -f "$HOME/.acme.sh/acme.sh" ]]; then
  log "Installing acme.sh..."
  curl -fsSL https://get.acme.sh | sh -s "email=$LE_EMAIL"
fi

ACME="$HOME/.acme.sh/acme.sh"

# Issue
log "Issuing cert for $DOMAIN..."
CF_Token="$CF_TOKEN" CF_Account_ID="$CF_ACCOUNT_ID" \
  "$ACME" --issue --dns dns_cf -d "$DOMAIN" --server letsencrypt --force || true

# Install into KasmVNC paths and reload
log "Installing cert → ~/.vnc/{cert,key}.pem"
"$ACME" --install-cert -d "$DOMAIN" --ecc \
  --key-file       "$HOME/.vnc/key.pem"  \
  --fullchain-file "$HOME/.vnc/cert.pem" \
  --reloadcmd     "systemctl --user restart kasmvnc.service"

ok "Cert issued and KasmVNC restarted with valid TLS."
