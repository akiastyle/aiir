#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
MODE="safe"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-clean.sh [--safe|--deep]

modes:
  --safe  remove runtime/generated temporary artifacts (default)
  --deep  safe + clear benchmark workdirs under /var/www/aiir/test
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --safe)
      MODE="safe"
      shift ;;
    --deep)
      MODE="deep"
      shift ;;
    -h|--help)
      usage
      exit 0 ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 1 ;;
  esac
done

prune_dir_files() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -type f -delete 2>/dev/null || true
  find "$dir" -type d -empty -delete 2>/dev/null || true
}

# Runtime/project generated artifacts (never touch tracked code).
prune_dir_files "${ROOT}/ai/state/projects"
prune_dir_files "${ROOT}/server/env/projects"
prune_dir_files "${ROOT}/server/generated"

# Shared ops lock can be stale after interrupted operations.
rm -f "${ROOT}/ai/state/.ops.lock" 2>/dev/null || true

if [[ "$MODE" == "deep" ]]; then
  prune_dir_files "${ROOT}/test/work"
  prune_dir_files "${ROOT}/test/full-work"
  prune_dir_files "${ROOT}/test/parity-work"
  prune_dir_files "${ROOT}/test/parity-retry"
fi

cat <<EOF2
{"ok":1,"action":"clean","mode":"${MODE}"}
EOF2
