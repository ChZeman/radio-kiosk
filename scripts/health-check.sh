#!/usr/bin/env bash
# Radio Kiosk — Health check (exits 0 = healthy, 1 = not responding)
exec curl -sf --max-time 5 http://localhost:8080/api/status > /dev/null 2>&1
