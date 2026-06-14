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

## Bill of Materials

Two reference configurations. Mix and match — the Pi and accessories are the same either way; the display and audio choices differ.

> **Note:** The Raspberry Pi 5 has no 3.5mm audio jack. Audio output always requires either HDMI (to a TV's speakers) or a USB sound card / DAC HAT.

---

### Option A — Desktop / Counter Unit

Compact all-in-one. The Pi mounts to the back of the DSI display using the included standoffs; the display includes a desk stand.

| # | Item | Notes | Est. Price |
|---|------|-------|-----------|
| 1 | **Raspberry Pi 5 (2 GB)** | Pi 4 works too (~$45), but Pi 5 runs Chromium smoother for 24/7 use | ~$50 |
| 2 | **7" DSI Touchscreen** | [Hosyond B0D3QB7X4Z](https://www.amazon.com/dp/B0D3QB7X4Z) or similar — 800×480 IPS, 5-pt capacitive, driver-free, includes stand | ~$38 |
| 3 | **Pi 5 PSU (5 V / 5 A USB-C)** | Pi 5 needs 5 A; a Pi 4 supply is undersized | ~$12 |
| 4 | **32 GB microSD — Endurance rated** | Samsung Pro Endurance or SanDisk High Endurance — standard cards wear out fast under 24/7 writes | ~$12 |
| 5 | **Pi 5 Active Cooler** | Official Pi 5 Active Cooler or equivalent — Pi 5 runs hot; cooling is not optional | ~$10 |
| 6 | **USB Sound Card** | [Waveshare B0CXJ2RTWJ](https://www.amazon.com/dp/B0CXJ2RTWJ) — driver-free, 3.5 mm out; required since DSI carries no audio | ~$12 |
| 7 | **USB-powered desktop speakers** | Logitech S120 or similar — 3.5 mm in, USB power, compact | ~$22 |
| | **Total** | | **~$156** |

*No HDMI cable needed — the DSI ribbon cable is included with the display.*

---

### Option B — Wall-Mount / Large Display

Pi lives in its own case, drives any HDMI display.

| # | Item | Notes | Est. Price |
|---|------|-------|-----------|
| 1 | **Raspberry Pi 5 (2 GB)** | | ~$50 |
| 2 | **Micro-HDMI → HDMI cable (6 ft)** | Both Pi 4 and Pi 5 use micro-HDMI | ~$9 |
| 3 | **Pi 5 PSU (5 V / 5 A USB-C)** | | ~$12 |
| 4 | **32 GB microSD — Endurance rated** | | ~$12 |
| 5 | **Argon NEO 5 case** | Aluminum, passive or fan-assisted; mounts neatly behind a TV | ~$20 |
| 6 | **Display** | See options below | varies |
| | **Pi + accessories subtotal** | | **~$103** |

**Display options:**

| Display | Notes | Est. Price |
|---------|-------|-----------|
| 32" consumer TV (TCL, Hisense, etc.) | Cheapest; not rated 24/7 but usually fine | $180–220 |
| 43" consumer TV | Better visibility from across a room | $220–280 |
| 32" commercial signage display (e.g. Samsung BE32T) | Rated 24/7, no IR remote interference, commercial warranty | $380–450 |
| 43" commercial signage display (e.g. Samsung BE43T) | Same, bigger | $480–580 |

**Audio options (choose one):**

| Scenario | Add-on | Est. Price |
|----------|--------|-----------|
| TV's built-in speakers are sufficient | Nothing — HDMI carries audio natively | $0 |
| Store has its own sound system (PA / aux input) | [InnoMaker DAC HAT B07D13QWV9](https://www.amazon.com/dp/B07D13QWV9) + 3.5 mm → RCA cable — RCA out is proper line level (2.1 Vrms) | ~$28 |

---

### Configuration Totals

| Configuration | Est. Total |
|--------------|-----------|
| Desktop counter unit (with desktop speakers) | ~$156 |
| Wall-mount + 32" consumer TV (TV speakers) | ~$285–325 |
| Wall-mount + 43" consumer TV (TV speakers) | ~$325–385 |
| Wall-mount + 32" consumer TV + store PA output | ~$313–353 |
| Wall-mount + commercial display + store PA output | ~$513–583 |


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
