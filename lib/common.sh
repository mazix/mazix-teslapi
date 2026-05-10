#!/bin/bash
# Common helpers used by all modules.

set -euo pipefail

# Color logging
_c_red=$'\033[31m'; _c_grn=$'\033[32m'; _c_ylw=$'\033[33m'
_c_blu=$'\033[34m'; _c_dim=$'\033[2m';  _c_off=$'\033[0m'

log()  { printf '%s[*]%s %s\n' "$_c_blu" "$_c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$_c_grn" "$_c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$_c_ylw" "$_c_off" "$*"; }
err()  { printf '%s[x]%s %s\n' "$_c_red" "$_c_off" "$*" >&2; }
step() { printf '\n%s== %s ==%s\n' "$_c_blu" "$*" "$_c_off"; }

# Source config.env from project root
load_config() {
  local root="${PROJECT_ROOT:-}"
  [[ -z "$root" ]] && root="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  if [[ -f "$root/config.env" ]]; then
    set -a; . "$root/config.env"; set +a
    export PROJECT_ROOT="$root"
  else
    err "config.env not found. Copy config.example.env → config.env and edit it."
    exit 1
  fi
}

# Require sudo without re-prompting between calls
require_sudo() {
  if ! sudo -v; then
    err "sudo authentication failed."
    exit 1
  fi
  # keep-alive
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# Render template with ${VAR} substitution → stdout
render() {
  local tmpl="$1"
  envsubst < "$tmpl"
}

# Detect iPhone tether interface (the most-recent USB-Ethernet that has an IPv4)
detect_tether_iface() {
  for iface in /sys/class/net/*/; do
    name=$(basename "$iface")
    [[ "$name" == "lo" || "$name" == "wlan0" || "$name" == "eth0" ]] && continue
    if [[ -d "$iface/device" ]]; then
      driver=$(readlink "$iface/device/driver" 2>/dev/null | xargs basename 2>/dev/null || true)
      if [[ "$driver" == "ipheth" || "$driver" == "cdc_ether" || "$driver" == "cdc_ncm" ]]; then
        echo "$name"
        return 0
      fi
    fi
  done
  return 1
}

# Idempotent NM connection ensure
nm_ensure_modify() {
  local conname="$1"; shift
  if nmcli -t -f NAME connection show | grep -qx "$conname"; then
    sudo nmcli connection modify "$conname" "$@"
  else
    return 1
  fi
}

confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}
