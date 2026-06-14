#!/usr/bin/env bash
# Radio Kiosk — One-line installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ChZeman/radio-kiosk/main/install.sh | sudo bash -s -- [options]
#
# Options:
#   --config-url URL      URL to remote config.json (fetched hourly)
#   --cf-token TOKEN      Cloudflare tunnel token (enables SSH + VNC)
#   --vnc-password PW     VNC password (default: kiosk1234)
#   --channel BRANCH      Git branch to track (default: main)
#   --no-reboot           Skip the reboot at the end

set -euo pipefail

REPO_URL="https://github.com/ChZeman/radio-kiosk.git"
INSTALL_DIR="/opt/radio-kiosk"

# ── Parse args ─────────────────────────────────────────────────────────────
CONFIG_URL=""
CF_TOKEN=""
VNC_PW="kiosk1234"
CHANNEL="main"
NO_REBOOT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-url)   CONFIG_URL="$2"; shift 2 ;;
    --cf-token)     CF_TOKEN="$2";   shift 2 ;;
    --vnc-password) VNC_PW="$2";     shift 2 ;;
    --channel)      CHANNEL="$2";    shift 2 ;;
    --no-reboot)    NO_REBOOT=1;     shift   ;;
    *) echo "Unknown option: $1" >&2; shift ;;
  esac
done

[[ $EUID -ne 0 ]] && { echo "ERROR: Run as root (sudo)." >&2; exit 1; }

echo "════════════════════════════════════════════════"
echo "  Radio Kiosk Installer"
echo "════════════════════════════════════════════════"

# ── Detect desktop user ────────────────────────────────────────────────────
KIOSK_USER=$(logname 2>/dev/null || getent passwd 1000 | cut -d: -f1 || echo "pi")
KIOSK_HOME=$(getent passwd "$KIOSK_USER" | cut -d: -f6 || echo "/home/$KIOSK_USER")
echo "→ Desktop user: $KIOSK_USER (home: $KIOSK_HOME)"

# ── Packages ───────────────────────────────────────────────────────────────
echo "→ Installing system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git python3 curl unclutter x11vnc openbox xdotool

# Chromium (name differs between distros)
for pkg in chromium-browser chromium; do
  if apt-cache show "$pkg" &>/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" && break
  fi
done

CHROMIUM_BIN=$(command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null || true)
[[ -z "$CHROMIUM_BIN" ]] && echo "WARNING: Chromium not found in PATH — install manually." >&2

# ── Clone / update repo ────────────────────────────────────────────────────
echo "→ Installing to $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git fetch origin
  git checkout "$CHANNEL"
  git pull origin "$CHANNEL"
else
  git clone --branch "$CHANNEL" --depth 10 "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi
git config pull.rebase false

# ── Config ─────────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR/config"

if [[ -n "$CONFIG_URL" ]]; then
  echo "$CONFIG_URL" > "$INSTALL_DIR/.remote_config_url"
  echo "→ Fetching config from $CONFIG_URL..."
  curl -fsSL --max-time 15 "$CONFIG_URL" -o "$INSTALL_DIR/config/config.json" 2>/dev/null \
    || echo "WARNING: Could not fetch remote config; using example." >&2
fi

if [[ ! -f "$INSTALL_DIR/config/config.json" ]]; then
  cp "$INSTALL_DIR/config/config.example.json" "$INSTALL_DIR/config/config.json"
  echo "→ Example config installed at $INSTALL_DIR/config/config.json"
  echo "  Edit it to set your station name, logo, and now-playing URL."
fi

# Save installer args for re-runs and the update script
cat > "$INSTALL_DIR/.install_args" << ARGS
CHANNEL="$CHANNEL"
CONFIG_URL="$CONFIG_URL"
VNC_PW="$VNC_PW"
KIOSK_USER="$KIOSK_USER"
ARGS

# ── Systemd services ───────────────────────────────────────────────────────
echo "→ Installing systemd services..."
chmod +x "$INSTALL_DIR/src/service.py" "$INSTALL_DIR/scripts/"*.sh

for svc in radio-kiosk radio-kiosk-update radio-kiosk-display; do
  [[ -f "$INSTALL_DIR/systemd/${svc}.service" ]] && \
    cp "$INSTALL_DIR/systemd/${svc}.service" /etc/systemd/system/
done
[[ -f "$INSTALL_DIR/systemd/radio-kiosk-update.timer" ]] && \
  cp "$INSTALL_DIR/systemd/radio-kiosk-update.timer" /etc/systemd/system/

# Patch KIOSK_USER placeholder into display service
sed -i "s/KIOSK_USER/$KIOSK_USER/g" /etc/systemd/system/radio-kiosk-display.service 2>/dev/null || true

# Patch update interval from config
UPDATE_HRS=$(python3 -c "
import json, sys
try:
  c = json.load(open('$INSTALL_DIR/config/config.json'))
  print(int(c.get('update',{}).get('update_interval_hours', 6)))
except Exception:
  print(6)
" 2>/dev/null || echo 6)
sed -i "s/UPDATE_HOURS/${UPDATE_HRS}/g" /etc/systemd/system/radio-kiosk-update.timer 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now radio-kiosk
systemctl enable radio-kiosk-update.timer
systemctl start  radio-kiosk-update.timer

# ── Autologin + LXDE autostart ────────────────────────────────────────────
echo "→ Configuring autologin..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/60-radio-kiosk.conf << LXDM
[Seat:*]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=LXDE-pi
LXDM

AUTOSTART_DIR="$KIOSK_HOME/.config/lxsession/LXDE-pi"
mkdir -p "$AUTOSTART_DIR"
LAUNCH_LINE="@bash /opt/radio-kiosk/scripts/kiosk-launcher.sh"
grep -qF "kiosk-launcher" "$AUTOSTART_DIR/autostart" 2>/dev/null \
  || echo "$LAUNCH_LINE" >> "$AUTOSTART_DIR/autostart"
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config" 2>/dev/null || true

# ── Cloudflare tunnel ──────────────────────────────────────────────────────
if [[ -n "$CF_TOKEN" ]]; then
  echo "→ Installing cloudflared..."
  if ! command -v cloudflared &>/dev/null; then
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    [[ "$ARCH" == "armv7l"  ]] && ARCH="arm"
    [[ "$ARCH" == "x86_64"  ]] && ARCH="amd64"
    CF_DEB="cloudflared-linux-${ARCH}.deb"
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/${CF_DEB}" \
      -o /tmp/cloudflared.deb
    dpkg -i /tmp/cloudflared.deb || apt-get install -f -y -qq
    rm -f /tmp/cloudflared.deb
  fi
  cloudflared service install "$CF_TOKEN" && systemctl enable --now cloudflared || \
    echo "WARNING: cloudflared service install failed — check token and retry." >&2
fi

# ── x11vnc ────────────────────────────────────────────────────────────────
CF_ENABLED=$(python3 -c "
import json
try:
  c = json.load(open('$INSTALL_DIR/config/config.json'))
  print('1' if c.get('cloudflare',{}).get('vnc_enabled', False) else '0')
except: print('0')
" 2>/dev/null || echo 0)

if [[ "$CF_ENABLED" == "1" || -n "$CF_TOKEN" ]]; then
  echo "→ Configuring x11vnc (VNC password: $VNC_PW)..."
  x11vnc -storepasswd "$VNC_PW" /etc/x11vnc.pass 2>/dev/null || true
  cat > /etc/systemd/system/x11vnc.service << 'VNCSVC'
[Unit]
Description=x11vnc VNC Server for Radio Kiosk
After=display-manager.service

[Service]
ExecStart=/usr/bin/x11vnc -display :0 -rfbauth /etc/x11vnc.pass -rfbport 5900 -forever -shared -noxdamage -repeat
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
VNCSVC
  systemctl daemon-reload
  systemctl enable --now x11vnc 2>/dev/null || true
fi

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo "  Installation complete!"
echo ""
echo "  Config:   $INSTALL_DIR/config/config.json"
echo "  Logs:     journalctl -u radio-kiosk -f"
echo "  Update:   sudo $INSTALL_DIR/scripts/update.sh"
echo "  Rollback: sudo $INSTALL_DIR/scripts/rollback.sh"
[[ -n "$CF_TOKEN" ]] && echo "  Remote:   Cloudflare tunnel active"
echo "════════════════════════════════════════════════"

if [[ $NO_REBOOT -eq 0 ]]; then
  echo "Rebooting in 5 s ... (Ctrl-C to cancel)"
  sleep 5
  reboot
fi
