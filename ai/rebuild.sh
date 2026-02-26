#!/usr/bin/env bash
set -euo pipefail

GIT_ROOT="${AI_GIT_ROOT:-/var/www/html/git}"
CORE_DIR="${AI_CORE_DIR:-/var/www/aiir/ai/core}"

exec /var/www/aiir/ai/exchange/rebuild-all.run.sh "$GIT_ROOT" "$CORE_DIR"
