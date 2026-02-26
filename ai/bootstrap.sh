#!/usr/bin/env bash
set -euo pipefail

GIT_ROOT="${1:-${AI_GIT_ROOT:-/var/www/html/git}}"
CORE_DIR="${2:-${AI_CORE_DIR:-/var/www/aiir/ai/core}}"
MODE="${3:-prepare}"

cd /var/www/aiir/ai/toolchain-native
make
/var/www/aiir/ai/exchange/bootstrap-node.run.sh
if [[ "$MODE" == "serve" ]]; then
  exec ./aiird bootstrap "$GIT_ROOT" "$CORE_DIR" serve
fi
exec ./aiird bootstrap "$GIT_ROOT" "$CORE_DIR"
