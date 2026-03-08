#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="/var/www/aiir/server/scripts"
NODE_BIN="${NODE_BIN:-node}"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-oaiir-exec.sh <ingest-out-dir> [runtime-out-dir]
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
  usage
  [[ -n "${1:-}" ]] && exit 0 || exit 1
fi

exec "$NODE_BIN" "${SCRIPT_DIR}/aiir-oaiir-exec.js" "$@"
