#!/usr/bin/env bash
# Radio Kiosk — Manual rollback to previous commit
set -euo pipefail
INSTALL_DIR="/opt/radio-kiosk"
PREV_FILE="$INSTALL_DIR/.prev_sha"

[[ $EUID -ne 0 ]] && { echo "Run as root." >&2; exit 1; }

if [[ ! -f "$PREV_FILE" ]]; then
  echo "ERROR: No previous commit recorded at $PREV_FILE."
  echo "Check git log: git -C $INSTALL_DIR log --oneline -10"
  exit 1
fi

PREV_SHA=$(cat "$PREV_FILE")
CURR_SHA=$(git -C "$INSTALL_DIR" rev-parse HEAD)
echo "Current:  $CURR_SHA"
echo "Rollback: $PREV_SHA"
read -r -p "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

echo "$CURR_SHA" > "$PREV_FILE"   # swap so you can rollback the rollback
git -C "$INSTALL_DIR" reset --hard "$PREV_SHA"
systemctl restart radio-kiosk
sleep 5
echo "Done. Now at: $(git -C $INSTALL_DIR rev-parse --short HEAD)"
