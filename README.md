# radio-kiosk

A self-contained, auto-updating kiosk display system for radio stations. Deploy it in stores, shops, or anywhere you want a presence — it shows your station branding, live "now playing" information, a QR code, and sponsor screens during commercial breaks.

## Features

- **Now Playing** — polls any URL for current song info (JSON or plain text)
- **Sponsor screens** — displays full-screen sponsor content during commercial breaks
- **QR code** — always-visible link to your station website
- **Auto-update** — pulls from GitHub on a schedule; rolls back automatically if something breaks
- **Remote access** — optional Cloudflare tunnel for SSH and VNC
- **Centralized config** — host your `config.json` anywhere online; all kiosks pick it up

## Hardware

Any Raspberry Pi (3B+/4/5) running **Raspberry Pi OS Bookworm Desktop** (64-bit recommended). Also works on any Debian/Ubuntu x86 mini PC.

## One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/ChZeman/radio-kiosk/main/install.sh | sudo bash -s -- \
  --config-url https://yourstation.com/kiosk/config.json \
  --cf-token YOUR_CLOUDFLARE_TUNNEL_TOKEN
```

All options:

| Flag | Description |
|------|-------------|
| `--config-url URL` | Remote config file URL (fetched every hour) |
| `--cf-token TOKEN` | Cloudflare tunnel token (enables SSH + VNC remote access) |
| `--vnc-password PW` | VNC password (default: `kiosk1234`) |
| `--channel BRANCH` | Git branch to track (default: `main`) |
| `--no-reboot` | Skip the reboot at the end |

## Configuration

After install the config lives at `/opt/radio-kiosk/config/config.json`. See `config/config.example.json` for all options.

### Minimum config

```json
{
  "station": {
    "name": "WLCB 97.7 FM",
    "website_url": "https://wlcb.org",
    "qr_target": "https://wlcb.org"
  }
}
```

### With now-playing (JSON feed)

```json
{
  "station": {
    "name": "WLCB 97.7 FM",
    "logo_url": "https://wlcb.org/logo.png",
    "website_url": "https://wlcb.org",
    "qr_target": "https://wlcb.org",
    "tagline": "Community Radio for the Lakes"
  },
  "nowplaying": {
    "enabled": true,
    "url": "https://wlcb.org/nowplaying.json",
    "format": "json",
    "field_artist": "artist",
    "field_title": "title",
    "field_is_commercial": "is_commercial",
    "field_sponsor_image_url": "sponsor_image",
    "commercial_screen_url": "https://wlcb.org/sponsor-screen.html"
  }
}
```

## Now-Playing Formats

### JSON (default)

Field paths support dot notation for nested objects (`now_playing.artist`, etc.).

```json
{ "artist": "U2", "title": "Beautiful Day", "is_commercial": false }
```

### Text

Two lines: artist on line 1, title on line 2. Put `BREAK` on line 1 to trigger commercial mode.

### Commercial detection

The kiosk enters commercial mode when **any** of these match:
- `field_is_commercial` is `true`
- `field_type` value equals `commercial_type_value`
- Title or artist matches `commercial_title_regex` (default: `BREAK|COMMERCIAL|SPOT|PSA`)

## Remote Access

When a Cloudflare tunnel token is provided the installer configures `cloudflared` + `x11vnc`. Set up your Cloudflare tunnel to route:
- `ssh://` → port 22 (SSH)  
- `vnc://` → port 5900 (VNC)

## Updates

**Automatic:** A systemd timer runs `scripts/update.sh` every 6 hours (configurable via `update.update_interval_hours`). It pulls the latest commit, restarts the service, runs a health check, and auto-rolls back if the check fails.

**Manual:**
```bash
sudo /opt/radio-kiosk/scripts/update.sh
```

**Force rollback:**
```bash
sudo /opt/radio-kiosk/scripts/rollback.sh
```

## Troubleshooting

```bash
# Service status and logs
sudo systemctl status radio-kiosk
sudo journalctl -u radio-kiosk -f

# Display logs
sudo journalctl -u radio-kiosk-display -f

# Test the API
curl http://localhost:8080/api/status
curl http://localhost:8080/api/config

# Restart everything
sudo systemctl restart radio-kiosk
sudo systemctl restart radio-kiosk-display
```
