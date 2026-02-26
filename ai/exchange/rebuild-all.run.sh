#!/usr/bin/env bash
set -euo pipefail

GIT_ROOT="${1:-${AI_GIT_ROOT:-/var/www/html/git}}"
CORE_DIR="${2:-${AI_CORE_DIR:-/var/www/aiir/ai/core}}"

cd /var/www/aiir/ai/toolchain-native
make
./aiir-toolchain rebuild-all "$GIT_ROOT" "$CORE_DIR"
