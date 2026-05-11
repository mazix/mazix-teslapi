#!/bin/bash
# 03: create the Wi-Fi access point that Tesla connects to.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "03 — Wi-Fi hotspot ($HOTSPOT_SSID @ $HOTSPOT_IP)"

CON_NAME="pi-hotspot"

# Force the gateway IP. Without ipv4.addresses set, NM's `shared` mode falls
# back to 10.42.0.1/24, which is RFC 1918 and is rejected by Chromium's
# Private Network Access check on Tesla browsers (public-domain → private-IP
# resolution is blocked). HOTSPOT_IP defaults to TEST-NET-2 to dodge that.
HOTSPOT_CIDR="${HOTSPOT_IP}/24"

if nmcli -t -f NAME connection show | grep -qx "$CON_NAME"; then
  log "Connection $CON_NAME exists; updating settings"
  sudo nmcli connection modify "$CON_NAME" \
    802-11-wireless.ssid "$HOTSPOT_SSID" \
    802-11-wireless.mode ap \
    802-11-wireless.band "$HOTSPOT_BAND" \
    ipv4.method shared \
    ipv4.addresses "$HOTSPOT_CIDR" \
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
    ipv4.addresses "$HOTSPOT_CIDR" \
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
