#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/sakikazu/dev/rails/akiya-observer"

cd "${APP_DIR}"

echo "[cron] start: $(date '+%Y-%m-%d %H:%M:%S %Z')"
bin/rails crawl:ok_smile
echo "[cron] end: $(date '+%Y-%m-%d %H:%M:%S %Z')"
