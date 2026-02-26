#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${1:-/var/www/aiir/ai/state}"
BACKUP_ROOT="${2:-/var/backups/aiir-state}"
RETENTION="${3:-7}"

ts="$(date +%Y%m%d-%H%M%S)"
install -d -m 0750 -o root -g www-data "$BACKUP_ROOT"

archive="${BACKUP_ROOT}/state-${ts}.tar.gz"
tar -C "$STATE_DIR" -czf "$archive" .
chown root:www-data "$archive"
chmod 0640 "$archive"

ls -1t "$BACKUP_ROOT"/state-*.tar.gz 2>/dev/null | awk -v keep="$RETENTION" 'NR>keep {print}' | xargs -r rm -f

echo "backup-ok: $archive"
