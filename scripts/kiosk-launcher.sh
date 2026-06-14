#!/usr/bin/env bash
# Radio Kiosk — Chromium kiosk launcher
# Started from LXDE autostart (or systemd display service) as the desktop user.

# Disable screensaver and power management
xset s off    2>/dev/null || true
xset s noblank 2>/dev/null || true
xset -dpms    2>/dev/null || true

# Hide mouse cursor after 0.5 s of idle
unclutter -idle 0.5 -root &

# Apply display rotation from config (OS-level, more reliable than CSS)
ROTATION=$(python3 -c "
import json
try:
  c = json.load(open('/opt/radio-kiosk/config/config.json'))
  print(c.get('display',{}).get('rotation', 0))
except Exception:
  print(0)
" 2>/dev/null || echo 0)

if [[ "$ROTATION" != "0" ]]; then
  OUTPUT=$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')
  case "$ROTATION" in
    90)  xrandr --output "$OUTPUT" --rotate right    2>/dev/null || true ;;
    180) xrandr --output "$OUTPUT" --rotate inverted 2>/dev/null || true ;;
    270) xrandr --output "$OUTPUT" --rotate left     2>/dev/null || true ;;
  esac
fi

# Wait for the backend service to become ready (up to 90 s)
WAITED=0
until curl -sf --max-time 2 http://localhost:8080/api/status > /dev/null 2>&1; do
  sleep 3; WAITED=$((WAITED+3))
  [[ $WAITED -ge 90 ]] && { echo "Service not ready after 90s, launching anyway." >&2; break; }
done

CHROMIUM=$(command -v chromium-browser 2>/dev/null \
        || command -v chromium       2>/dev/null \
        || echo "chromium")

exec "$CHROMIUM" \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --no-first-run \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --disable-translate \
  --disable-features=TranslateUI,OverscrollHistoryNavigation \
  --disable-pinch \
  --overscroll-history-navigation=0 \
  --check-for-update-interval=31536000 \
  --start-maximized \
  --disable-background-networking \
  http://localhost:8080
