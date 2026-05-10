#!/bin/bash
# 01: install all required packages.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "01 — Prerequisites"

PKGS=(
  # Network
  network-manager dnsmasq-base nftables
  # iPhone tether
  usbmuxd libimobiledevice-1.0-6
  # Bluetooth
  bluez bluez-tools
  pipewire pipewire-pulse pipewire-audio-client-libraries
  libspa-0.2-bluetooth wireplumber
  # X / desktop
  dbus-x11 x11-xserver-utils
  # Misc
  curl wget ca-certificates openssl gettext-base
  # Tk for the BT GUI
  python3-tk python3-evdev
)

log "Updating apt..."
sudo apt-get update -qq

log "Installing ${#PKGS[@]} packages (skipping already-installed)..."
sudo apt-get install -y --no-install-recommends "${PKGS[@]}"

# Pi user must be in groups for BT and netdev
sudo usermod -aG bluetooth,netdev "$PI_USER" || true

ok "Prerequisites installed."
