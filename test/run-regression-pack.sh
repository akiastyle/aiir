#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"

# Default: strict quality gates over fixed regression pack.
exec "${ROOT}/server/scripts/aiir" bench --profile full --regression-pack --gate-strict "$@"
