#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/sakikazu/dev/rails/akiya-observer"
ASDF_DIR="${ASDF_DIR:-$HOME/.asdf}"

cd "${APP_DIR}"

if [ -f "${ASDF_DIR}/asdf.sh" ]; then
  # Load asdf so the Ruby version from .ruby-version is used in cron.
  # shellcheck disable=SC1090
  . "${ASDF_DIR}/asdf.sh"
fi

echo "[cron] start: $(date '+%Y-%m-%d %H:%M:%S %Z')"
bundle exec rails crawl:taketa_iju
echo "[cron] end: $(date '+%Y-%m-%d %H:%M:%S %Z')"
