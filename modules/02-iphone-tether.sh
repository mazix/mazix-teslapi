#!/bin/bash
# 02: enable iPhone Personal Hotspot tethering on USB.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "02 — iPhone USB tether"

# Load ipheth now and at boot
log "Loading ipheth kernel module..."
sudo modprobe ipheth || warn "modprobe ipheth failed (kernel may not have it)"
echo "ipheth" | sudo tee /etc/modules-load.d/ipheth.conf > /dev/null

# usbmuxd is socket-activated on Trixie (Type=static). Just make sure it's installed.
if systemctl list-unit-files usbmuxd.service >/dev/null 2>&1; then
  ok "usbmuxd present (socket-activated)."
else
  warn "usbmuxd service not found — try: sudo apt install usbmuxd"
fi

cat <<MSG

  iPhone tethering ready. To use:
    1. Connect iPhone with a USB cable.
    2. iPhone → Settings → Personal Hotspot → enable
       'Allow Others to Join'.
    3. On first connect, tap 'Trust' on the iPhone.
    4. Verify a new interface appears (typically eth1):
         ip -br addr

MSG
ok "Module done."
