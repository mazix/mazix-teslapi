#!/bin/bash
# Master installer for tesla-pi-station.
# Reads config.env, runs each numbered module in order.
# Modules are idempotent — safe to re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$SCRIPT_DIR"

if [[ ! -f "$SCRIPT_DIR/config.env" ]]; then
  echo "config.env missing. Run:"
  echo "  cp config.example.env config.env"
  echo "  \$EDITOR config.env"
  exit 1
fi

. "$SCRIPT_DIR/lib/common.sh"

MODULES=(
  "01-prereqs"
  "02-iphone-tether"
  "03-wifi-hotspot"
  "04-routing-bypass"
  "05-port-redirect"
  "06-kasmvnc"
  "07-letsencrypt"
  "08-dns-hijack"
  "09-bluetooth-audio"
  "10-bt-gui"
)

usage() {
  cat <<EOF
Usage: $0 [MODULE ...]

With no args, runs all modules in order. Otherwise runs only the named ones.

Available modules:
$(printf '  %s\n' "${MODULES[@]}")

Examples:
  $0                                # everything
  $0 06-kasmvnc 07-letsencrypt      # just these two
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi

selected=("${@:-${MODULES[@]}}")

echo
echo "  ┌─────────────────────────────────────┐"
echo "  │  tesla-pi-station — installer       │"
echo "  └─────────────────────────────────────┘"
echo

for m in "${selected[@]}"; do
  script="$SCRIPT_DIR/modules/${m}.sh"
  if [[ ! -f "$script" ]]; then
    err "Unknown module: $m"
    exit 1
  fi
  bash "$script"
done

echo
ok "All requested modules complete."
echo "Connect a client to '$HOTSPOT_SSID' and visit https://$DOMAIN"
