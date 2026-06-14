#!/usr/bin/env bash
# Radio Kiosk — Auto-update with health check and rollback
set -euo pipefail

INSTALL_DIR="/opt/radio-kiosk"
LOG="/var/log/radio-kiosk-update.log"
HEALTH_URL="http://localhost:8080/api/status"
MAX_WAIT=60   # seconds to wait for health check

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
log "───────────────────────────────────────────"
log "Update check started"

cd "$INSTALL_DIR"

# Load installer args (channel, config URL, etc.)
[[ -f .install_args ]] && source .install_args
CHANNEL="${CHANNEL:-main}"

PREV_SHA=$(git rev-parse HEAD)
log "Current:  $PREV_SHA ($(git log -1 --format='%s'))"

git fetch origin "$CHANNEL" 2>&1 | tee -a "$LOG" | grep -v "^$" || true
NEW_SHA=$(git rev-parse "origin/$CHANNEL")

if [[ "$PREV_SHA" == "$NEW_SHA" ]]; then
  log "Already up to date."
  exit 0
fi

log "New commit: $NEW_SHA — updating..."
echo "$PREV_SHA" > "$INSTALL_DIR/.prev_sha"
git reset --hard "origin/$CHANNEL" 2>&1 | tee -a "$LOG"
log "Code updated: $(git log -1 --format='%s')"

# Re-deploy systemd files if they changed
for svc in radio-kiosk radio-kiosk-update radio-kiosk-display; do
  SRC="$INSTALL_DIR/systemd/${svc}.service"
  DST="/etc/systemd/system/${svc}.service"
  if [[ -f "$SRC" ]]; then
    # Preserve KIOSK_USER patch in display service
    KIOSK_USER="${KIOSK_USER:-pi}"
    sed "s/KIOSK_USER/$KIOSK_USER/g" "$SRC" > "$DST"
  fi
done
if [[ -f "$INSTALL_DIR/systemd/radio-kiosk-update.timer" ]]; then
  cp "$INSTALL_DIR/systemd/radio-kiosk-update.timer" /etc/systemd/system/
fi
systemctl daemon-reload

# Restart service
log "Restarting radio-kiosk..."
systemctl restart radio-kiosk

# Health check
log "Waiting for health check (max ${MAX_WAIT}s)..."
WAITED=0
OK=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
  sleep 5; WAITED=$((WAITED+5))
  if curl -sf --max-time 4 "$HEALTH_URL" > /dev/null 2>&1; then
    OK=1; break
  fi
  log "  (${WAITED}s) waiting..."
done

if [[ $OK -eq 1 ]]; then
  log "Health check passed after ${WAITED}s."
  log "Update successful: $(git rev-parse --short HEAD)"

  # Refresh remote config if configured
  if [[ -f "$INSTALL_DIR/.remote_config_url" ]]; then
    URL=$(cat "$INSTALL_DIR/.remote_config_url")
    if [[ -n "$URL" ]]; then
      curl -fsSL --max-time 15 "$URL" -o "$INSTALL_DIR/config/config.json" 2>/dev/null \
        && log "Remote config refreshed" || log "Remote config fetch failed (non-fatal)"
    fi
  fi
  exit 0
fi

# ── Rollback ──────────────────────────────────────────────────────────────
log "Health check FAILED — rolling back to $PREV_SHA..."
git reset --hard "$PREV_SHA"
systemctl restart radio-kiosk
sleep 8

if curl -sf --max-time 4 "$HEALTH_URL" > /dev/null 2>&1; then
  log "Rollback successful — running previous version."
else
  log "ERROR: Rollback health check also failed. Manual intervention needed."
  exit 2
fi
exit 1
