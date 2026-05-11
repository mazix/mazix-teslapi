#!/bin/bash
# 11: install the hardware-accelerated display backend (x11vnc + websockify
# + noVNC on :0 X server) alongside KasmVNC, and the tesla-display switcher
# to pick which one serves :443. KasmVNC stays installed and switchable
# back at any moment.
. "$(dirname "$0")/../lib/common.sh"
# This module installs infrastructure only — no per-site values from
# config.env are needed. Skip the strict load_config so the module can
# also be re-run on systems that haven't created config.env yet.
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
require_sudo

step "11 — Hardware-accelerated display backend (x11vnc + noVNC)"

log "Installing packages: x11vnc, novnc, websockify, mesa-utils"
sudo apt install -y x11vnc novnc websockify mesa-utils

log "Deploying x11vnc system service (bound to :0)"
sudo install -m 0644 "$PROJECT_ROOT/templates/x11vnc.service" \
    /etc/systemd/system/x11vnc.service

log "Deploying websockify+noVNC TLS system service (port 8444)"
sudo install -m 0644 "$PROJECT_ROOT/templates/websockify-tls.service" \
    /etc/systemd/system/websockify-tls.service

log "Deploying tesla-display switcher CLI"
sudo install -m 0755 "$PROJECT_ROOT/templates/tesla-display" \
    /usr/local/bin/tesla-display
sudo install -m 0755 "$PROJECT_ROOT/templates/tesla-display-boot" \
    /usr/local/sbin/tesla-display-boot
sudo install -m 0644 "$PROJECT_ROOT/templates/tesla-display-boot.service" \
    /etc/systemd/system/tesla-display-boot.service

sudo systemctl daemon-reload
systemctl --user daemon-reload

log "Enabling boot-default applier"
sudo systemctl enable tesla-display-boot.service

log "Initial default = kasmvnc (preserve current behaviour)"
sudo mkdir -p /etc/tesla-display
if [[ ! -f /etc/tesla-display/active ]]; then
    echo "kasmvnc" | sudo tee /etc/tesla-display/active >/dev/null
fi

log "Installing GUI switcher + desktop launcher"
GUI_DIR="$HOME/tesla-display-gui"
mkdir -p "$GUI_DIR" "$HOME/Desktop"
cp "$PROJECT_ROOT/templates/tesla-display-gui.py" "$GUI_DIR/tesla-display-gui.py"
chmod +x "$GUI_DIR/tesla-display-gui.py"
INSTALL_DIR="$GUI_DIR" envsubst < "$PROJECT_ROOT/templates/tesla-display-gui.desktop.tmpl" \
    > "$HOME/Desktop/tesla-display-gui.desktop"
chmod +x "$HOME/Desktop/tesla-display-gui.desktop"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
    gio set "$HOME/Desktop/tesla-display-gui.desktop" "metadata::trusted" true 2>/dev/null || true

log "Granting pi NOPASSWD sudo for tesla-display only (GUI needs it)"
sudo tee /etc/sudoers.d/tesla-display >/dev/null <<'EOF'
# Allow the tesla-display GUI to switch backends without prompting.
# Scope is locked to this single command; no other sudo privileges.
pi ALL=(ALL) NOPASSWD: /usr/local/bin/tesla-display
EOF
sudo chmod 0440 /etc/sudoers.d/tesla-display
sudo visudo -c -f /etc/sudoers.d/tesla-display

log "Disabling HDMI screen blanking persistently"
sudo tee /etc/xdg/autostart/tesla-display-no-dpms.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Disable HDMI screen blanking (tesla-display)
Comment=Without this, :0 X server lets the monitor go DPMS-off and
        x11vnc shows a black framebuffer.
Exec=sh -c 'xset s off -dpms 2>/dev/null'
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

ok "Hardware-accelerated backend installed."
echo
echo "Switch to it with:           tesla-display switch hwaccel"
echo "Switch back to KasmVNC with: tesla-display switch kasmvnc"
echo "Inspect current state:       tesla-display status"
echo "Change the boot default:     tesla-display set-default <name>"
