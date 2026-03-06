#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
TEST_DIR="${ROOT}/test"
PROFILE="full"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-bench.sh [--profile quick|full] [repo-url ...]

profiles:
  quick  -> MB benchmark only (OPEN_REPO_TEST_*)
  full   -> MB + parity benchmark (OPEN_REPO_FULL_*)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2 ;;
    -h|--help)
      usage
      exit 0 ;;
    --)
      shift
      break ;;
    *)
      break ;;
  esac
done

runner=""
case "$PROFILE" in
  quick)
    runner="${TEST_DIR}/benchmark-open-repos.sh" ;;
  full)
    runner="${TEST_DIR}/benchmark-open-repos-full.sh" ;;
  *)
    echo "invalid profile: $PROFILE" >&2
    usage
    exit 1 ;;
esac

if [[ ! -x "$runner" ]]; then
  echo "missing runner: $runner" >&2
  exit 1
fi

if [[ "$PROFILE" == "full" ]]; then
  : "${AIIR_FULL_ANALYSIS_MAX_MB:=350}"
fi

if [[ "$#" -gt 0 ]]; then
  exec "$runner" "$@"
fi
exec "$runner"
