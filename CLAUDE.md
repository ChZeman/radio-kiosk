# radio-kiosk -- kiosk device (project notes)

_General infra/credentials live in the workspace root CLAUDE.md._

## Radio Kiosk — BUILT (2026-06-14)

**Repo:** https://github.com/ChZeman/radio-kiosk
**Purpose:** Deployable radio station kiosk display for stores/shops. Shows station branding, live now-playing info, QR code, and sponsor screens during commercial breaks.
**Target:** Raspberry Pi 3B+/4/5 (Raspberry Pi OS Bookworm Desktop); also works Debian/Ubuntu x86.

### Architecture:
- Python 3 backend service (`src/service.py`) on port 8080 — stdlib only, no pip deps
- Chromium in kiosk mode pointing to `http://localhost:8080`
- Vanilla JS/CSS/HTML frontend (no framework)
- QR code via Google Chart API (inline in HTML, no JS lib)
- systemd for all services
- Git-based auto-update with health check + rollback
- cloudflared + x11vnc for remote access

### File layout (installed at /opt/radio-kiosk):
```
install.sh                            ← one-line curl installer
config/config.example.json           ← full config reference
src/
  service.py                         ← Python HTTP server + nowplaying poller
  kiosk/
    index.html                       ← kiosk UI
    static/style.css                 ← dark/light theme, rotations
    static/app.js                    ← frontend controller
scripts/
  update.sh                          ← git pull + health check + rollback
  rollback.sh                        ← manual rollback to .prev_sha
  health-check.sh                    ← curl localhost:8080/api/status
  kiosk-launcher.sh                  ← Chromium kiosk mode launcher
systemd/
  radio-kiosk.service                ← Python backend
  radio-kiosk-update.service         ← oneshot updater
  radio-kiosk-update.timer           ← scheduled timer
  radio-kiosk-display.service        ← Chromium (KIOSK_USER placeholder)
```

### One-line install:
```bash
curl -fsSL https://raw.githubusercontent.com/ChZeman/radio-kiosk/main/install.sh | sudo bash -s -- \
  --config-url https://yourstation.com/kiosk/config.json \
  --cf-token YOUR_CF_TUNNEL_TOKEN
```
Options: `--config-url`, `--cf-token`, `--vnc-password` (default: kiosk1234), `--channel` (default: main), `--no-reboot`

### Config keys (config/config.json on device):
- `station.name/logo_url/website_url/qr_target/tagline/accent_color`
- `nowplaying.enabled/url/format(json|text)/poll_interval_seconds/field_*` (dot-notation paths)
- Commercial detection: boolean field OR type-field equality OR regex on title/artist
- `display.rotation(0/90/180/270)/theme(dark|light)/show_clock/show_qr_code`
- `cloudflare.enabled/tunnel_token/vnc_enabled/vnc_password`
- `update.auto_update_enabled/update_interval_hours/git_branch`

### API endpoints (service.py):
- `GET /api/status` → current now-playing state + display config
- `GET /api/config` → sanitized config (cloudflare token stripped)
- `GET /` and `/static/*` → kiosk UI files

### State files on device:
- `.install_args` — CHANNEL, CONFIG_URL, VNC_PW, KIOSK_USER
- `.remote_config_url` — URL for hourly config refresh
- `.prev_sha` — previous commit SHA for rollback

### Known pending items:
- Not yet tested on actual Raspberry Pi hardware
- No `/api/reload-config` endpoint (config only reloads hourly or on restart)
- No web-based admin UI for config editing

---

