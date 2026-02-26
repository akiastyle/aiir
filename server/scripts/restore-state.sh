#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-}"
STATE_DIR="${2:-/var/www/aiir/ai/state}"

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "usage: $0 /path/to/state-YYYYMMDD-HHMMSS.tar.gz [/var/www/aiir/ai/state]" >&2
  exit 1
fi

install -d -m 2770 -o root -g www-data "$STATE_DIR"
find "$STATE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
tar -C "$STATE_DIR" -xzf "$ARCHIVE"
chown -R root:www-data "$STATE_DIR"
find "$STATE_DIR" -type d -exec chmod 2770 {} +
find "$STATE_DIR" -type f -exec chmod 0660 {} +

echo "restore-ok: $ARCHIVE -> $STATE_DIR"
