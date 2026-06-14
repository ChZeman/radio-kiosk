#!/usr/bin/env python3
"""
Radio Kiosk - Backend Service
Serves the kiosk UI and polls the configured now-playing URL.
No external dependencies required (Python 3 standard library only).
"""

import json
import os
import threading
import time
import urllib.request
import urllib.error
import re
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

CONFIG_PATH = Path('/opt/radio-kiosk/config/config.json')
KIOSK_DIR   = Path('/opt/radio-kiosk/src/kiosk')
PORT        = 8080

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
log = logging.getLogger('radio-kiosk')

DEFAULT_CONFIG = {
    "station": {
        "name": "Radio Station", "tagline": "", "logo_url": "",
        "website_url": "", "qr_target": "", "accent_color": "#3b82f6"
    },
    "nowplaying": {
        "enabled": False, "url": "", "format": "json",
        "poll_interval_seconds": 10, "request_headers": {},
        "field_artist": "artist", "field_title": "title",
        "field_is_commercial": "is_commercial",
        "field_type": "type", "commercial_type_value": "",
        "commercial_title_regex": "^(BREAK|COMMERCIAL|SPOT|PSA|PROMO)",
        "field_sponsor_image_url": "sponsor_image_url",
        "field_sponsor_name": "sponsor_name",
        "field_sponsor_screen_url": "sponsor_screen_url",
        "commercial_screen_url": ""
    },
    "display": {
        "rotation": 0, "theme": "dark",
        "show_clock": True, "show_qr_code": True,
        "ui_poll_interval_seconds": 5
    },
    "cloudflare": {
        "enabled": False, "tunnel_token": "",
        "vnc_enabled": False, "vnc_password": "kiosk1234"
    },
    "update": {
        "auto_update_enabled": True,
        "update_interval_hours": 6,
        "git_branch": "main"
    }
}

_lock  = threading.Lock()
_state = {
    "artist": "", "title": "", "is_commercial": False,
    "sponsor_image_url": "", "sponsor_name": "",
    "sponsor_screen_url": "", "last_updated": 0, "error": None
}
_config = {}


# ── Config ─────────────────────────────────────────────────────────────────

def _deep_merge(base, override):
    result = dict(base)
    for k, v in override.items():
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = _deep_merge(result[k], v)
        else:
            result[k] = v
    return result

def load_config():
    global _config
    _config = _deep_merge(DEFAULT_CONFIG, {})
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                user = json.load(f)
            _config = _deep_merge(DEFAULT_CONFIG, user)
            log.info("Config loaded from %s", CONFIG_PATH)
        except Exception as e:
            log.error("Config load error: %s", e)

def _fetch_remote_config():
    """Hourly thread: pull remote config URL and write it locally."""
    while True:
        time.sleep(3600)
        url_file = Path('/opt/radio-kiosk/.remote_config_url')
        if not url_file.exists():
            continue
        url = url_file.read_text().strip()
        if not url:
            continue
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                data = r.read().decode('utf-8')
            json.loads(data)          # validate JSON before writing
            CONFIG_PATH.write_text(data)
            load_config()
            log.info("Remote config refreshed")
        except Exception as e:
            log.warning("Remote config fetch failed: %s", e)


# ── Now-playing poller ─────────────────────────────────────────────────────

def _get_nested(data, path):
    """Resolve a dot-notation path in a nested dict."""
    if not path:
        return None
    current = data
    for part in path.split('.'):
        if isinstance(current, dict):
            current = current.get(part)
        else:
            return None
    return current

def _poll_nowplaying():
    while True:
        np = _config.get('nowplaying', {})
        if not np.get('enabled') or not np.get('url'):
            time.sleep(10)
            continue
        interval = np.get('poll_interval_seconds', 10)
        try:
            req = urllib.request.Request(np['url'], headers=np.get('request_headers', {}))
            with urllib.request.urlopen(req, timeout=10) as resp:
                raw = resp.read().decode('utf-8', errors='replace')

            fmt = np.get('format', 'json')

            if fmt == 'json':
                data   = json.loads(raw)
                artist = str(_get_nested(data, np.get('field_artist', 'artist')) or '')
                title  = str(_get_nested(data, np.get('field_title',  'title'))  or '')

                is_com = False
                # Method 1: boolean field
                v = _get_nested(data, np.get('field_is_commercial', 'is_commercial'))
                if v is not None:
                    is_com = bool(v)
                # Method 2: type field equality
                com_val = np.get('commercial_type_value', '')
                if com_val and str(_get_nested(data, np.get('field_type', 'type'))) == com_val:
                    is_com = True
                # Method 3: regex on title/artist
                pat = np.get('commercial_title_regex', '')
                if pat and re.search(pat, f"{title} {artist}", re.IGNORECASE):
                    is_com = True

                sponsor_img    = str(_get_nested(data, np.get('field_sponsor_image_url', 'sponsor_image_url')) or '')
                sponsor_name   = str(_get_nested(data, np.get('field_sponsor_name',      'sponsor_name'))      or '')
                sponsor_screen = str(_get_nested(data, np.get('field_sponsor_screen_url','sponsor_screen_url')) or '')
                if is_com and not sponsor_screen:
                    sponsor_screen = np.get('commercial_screen_url', '')

            else:  # text format: line1=artist, line2=title
                lines  = [l.strip() for l in raw.strip().splitlines() if l.strip()]
                artist = lines[0] if lines       else ''
                title  = lines[1] if len(lines) > 1 else ''
                pat    = np.get('commercial_title_regex', '')
                is_com = bool(pat and re.search(pat, artist, re.IGNORECASE))
                sponsor_img = sponsor_name = ''
                sponsor_screen = np.get('commercial_screen_url', '') if is_com else ''

            with _lock:
                _state.update(
                    artist=artist, title=title, is_commercial=is_com,
                    sponsor_image_url=sponsor_img, sponsor_name=sponsor_name,
                    sponsor_screen_url=sponsor_screen,
                    last_updated=time.time(), error=None
                )

        except Exception as e:
            log.warning("Now-playing poll error: %s", e)
            with _lock:
                _state['error'] = str(e)

        time.sleep(interval)


# ── HTTP handler ────────────────────────────────────────────────────────────

MIME = {
    '.html': 'text/html; charset=utf-8',
    '.css':  'text/css',
    '.js':   'application/javascript',
    '.png':  'image/png',
    '.jpg':  'image/jpeg',
    '.svg':  'image/svg+xml',
    '.ico':  'image/x-icon',
    '.json': 'application/json',
}

class KioskHandler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass   # silence default access log

    def _send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(body)

    def _serve_file(self, fpath):
        try:
            with open(fpath, 'rb') as f:
                data = f.read()
            mime = MIME.get(Path(fpath).suffix, 'application/octet-stream')
            self.send_response(200)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not found')

    def do_GET(self):
        path = self.path.split('?')[0]

        if path == '/api/status':
            with _lock:
                data = dict(_state)
            data['display']            = _config.get('display', {})
            data['nowplaying_enabled'] = _config.get('nowplaying', {}).get('enabled', False)
            self._send_json(data)

        elif path == '/api/config':
            safe = {k: v for k, v in _config.items() if k != 'cloudflare'}
            cf   = _config.get('cloudflare', {})
            safe['cloudflare'] = {
                'enabled':     cf.get('enabled',     False),
                'vnc_enabled': cf.get('vnc_enabled', False)
            }
            self._send_json(safe)

        elif path in ('/', '/index.html'):
            self._serve_file(KIOSK_DIR / 'index.html')

        elif path.startswith('/static/'):
            self._serve_file(KIOSK_DIR / path.lstrip('/'))

        else:
            self.send_response(404)
            self.end_headers()


# ── Entry point ─────────────────────────────────────────────────────────────

def main():
    load_config()
    for target in (_poll_nowplaying, _fetch_remote_config):
        threading.Thread(target=target, daemon=True).start()

    server = HTTPServer(('0.0.0.0', PORT), KioskHandler)
    log.info("Radio Kiosk service listening on :%d", PORT)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == '__main__':
    main()
