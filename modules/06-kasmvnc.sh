#!/bin/bash
# 06: install KasmVNC + LXDE-pi xstartup + systemd user service.
. "$(dirname "$0")/../lib/common.sh"
load_config
require_sudo

step "06 — KasmVNC"

# Pi OS Trixie: switch to X11 (KasmVNC needs X11)
log "Ensuring X11 session (raspi-config nonint do_wayland 1 = X11)..."
sudo raspi-config nonint do_wayland 1 || warn "raspi-config Wayland switch failed (already X11?)"

# Install KasmVNC if not present
if ! command -v kasmvncserver >/dev/null; then
  log "Downloading KasmVNC..."
  ARCH="$(dpkg --print-architecture)"
  VER="1.4.0"
  DEB="kasmvncserver_trixie_${VER}_${ARCH}.deb"
  TMP=$(mktemp -d)
  ( cd "$TMP" && wget -q "https://github.com/kasmtech/KasmVNC/releases/download/v${VER}/${DEB}" )
  sudo apt-get install -y "$TMP/$DEB"
  rm -rf "$TMP"
fi

# Conflicting RealVNC (Pi OS pre-install) must go
if dpkg -l realvnc-vnc-server 2>/dev/null | grep -q '^ii'; then
  log "Removing RealVNC (conflicts with KasmVNC's Xvnc binary)..."
  sudo apt-get remove --purge -y realvnc-vnc-server realvnc-vnc-viewer || true
fi

# User dirs and password
mkdir -p "$HOME/.vnc"
if [[ ! -f "$HOME/.kasmpasswd" ]]; then
  log "Creating KasmVNC user (set a password):"
  kasmvncpasswd -u "$PI_USER" -wo
fi

# Initial self-signed cert (replaced by Let's Encrypt in module 07)
if [[ ! -f "$HOME/.vnc/cert.pem" ]]; then
  log "Generating placeholder self-signed cert..."
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$HOME/.vnc/key.pem" -out "$HOME/.vnc/cert.pem" \
    -days 30 -subj "/CN=$DOMAIN" 2>/dev/null
  chmod 600 "$HOME/.vnc/key.pem"
fi

# yaml from template
log "Writing kasmvnc.yaml..."
HOME="$HOME" envsubst < "$PROJECT_ROOT/templates/kasmvnc.yaml.tmpl" > "$HOME/.vnc/kasmvnc.yaml"
chmod 600 "$HOME/.vnc/kasmvnc.yaml"

# xstartup
cp "$PROJECT_ROOT/templates/xstartup" "$HOME/.vnc/xstartup"
chmod +x "$HOME/.vnc/xstartup"

# systemd user service
mkdir -p "$HOME/.config/systemd/user"
cp "$PROJECT_ROOT/templates/kasmvnc.service" "$HOME/.config/systemd/user/kasmvnc.service"

# Enable linger so user services come up at boot, even headless
sudo loginctl enable-linger "$PI_USER"

systemctl --user daemon-reload
systemctl --user enable --now kasmvnc.service

sleep 4
if systemctl --user is-active --quiet kasmvnc.service; then
  ok "KasmVNC running on :8443 (will be reachable as https://$DOMAIN after module 07 + 08)."
else
  err "KasmVNC service failed. See: tail -30 /tmp/kasmvnc-systemd.log"
  exit 1
fi
