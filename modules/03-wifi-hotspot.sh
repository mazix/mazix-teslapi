#!/bin/bash
# 03: create the Wi-Fi access point that Tesla connects to.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "03 — Wi-Fi hotspot ($HOTSPOT_SSID)"

CON_NAME="pi-hotspot"

if nmcli -t -f NAME connection show | grep -qx "$CON_NAME"; then
  log "Connection $CON_NAME exists; updating settings"
  sudo nmcli connection modify "$CON_NAME" \
    802-11-wireless.ssid "$HOTSPOT_SSID" \
    802-11-wireless.mode ap \
    802-11-wireless.band "$HOTSPOT_BAND" \
    ipv4.method shared \
    ipv6.method ignore \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.proto rsn \
    wifi-sec.pairwise ccmp \
    wifi-sec.group ccmp \
    wifi-sec.psk "$HOTSPOT_PASSWORD" \
    connection.autoconnect yes
else
  log "Creating connection $CON_NAME"
  sudo nmcli connection add type wifi ifname "$WIFI_IFACE" \
    con-name "$CON_NAME" autoconnect yes \
    ssid "$HOTSPOT_SSID" \
    -- \
    802-11-wireless.mode ap \
    802-11-wireless.band "$HOTSPOT_BAND" \
    ipv4.method shared \
    ipv6.method ignore \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.proto rsn \
    wifi-sec.pairwise ccmp \
    wifi-sec.group ccmp \
    wifi-sec.psk "$HOTSPOT_PASSWORD"
fi

log "Activating hotspot..."
sudo nmcli connection up "$CON_NAME"

sleep 2
ip -br addr show "$WIFI_IFACE"
ok "Hotspot '$HOTSPOT_SSID' is up at $HOTSPOT_IP."
