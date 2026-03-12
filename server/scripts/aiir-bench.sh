#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
TEST_DIR="${ROOT}/test"
PROFILE="full"
TUNING_ENV_FILE="${ROOT}/server/env/ai-first-tuning.env"
LOCK_FILE="${AIIR_BENCH_LOCK_FILE:-${ROOT}/ai/state/.bench.lock}"
GATE_ZERO_NEW=0
GATE_OVERALL_MIN=""
GATE_NOTE_OK=0
GATE_NO_CHUNK=0
REPOS=()
USE_REGRESSION_PACK=0

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-bench.sh [--profile quick|full] [--regression-pack] [--gate-zero-new] [--gate-overall-min N] [--gate-note-ok] [--gate-no-chunk] [--gate-strict] [repo-url ...]

profiles:
  quick  -> MB benchmark only (OPEN_REPO_TEST_*)
  full   -> MB + parity benchmark (OPEN_REPO_FULL_*)

gates (full profile):
  --gate-zero-new      fail if any repo in current run has oaiir_new_total > 0
  --gate-overall-min N fail if any repo in current run has overall_parity < N
  --gate-note-ok       fail if note is not ok or analysis_chunked_large
  --gate-no-chunk      fail if any repo in current run used chunk_mode != none
  --gate-strict        equivalent to --gate-zero-new --gate-overall-min 100 --gate-note-ok
  --regression-pack    run fixed repository pack from /var/www/aiir/test/REPO_REGRESSION_PACK.txt
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
    --gate-zero-new)
      GATE_ZERO_NEW=1
      shift ;;
    --gate-overall-min)
      GATE_OVERALL_MIN="${2:-}"
      shift 2 ;;
    --gate-note-ok)
      GATE_NOTE_OK=1
      shift ;;
    --gate-no-chunk)
      GATE_NO_CHUNK=1
      shift ;;
    --gate-strict)
      GATE_ZERO_NEW=1
      GATE_OVERALL_MIN="100"
      GATE_NOTE_OK=1
      shift ;;
    --regression-pack)
      USE_REGRESSION_PACK=1
      shift ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        REPOS+=("$1")
        shift
      done
      break ;;
    *)
      REPOS+=("$1")
      shift ;;
  esac
done

if [[ -f "$TUNING_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$TUNING_ENV_FILE"
fi

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
  : "${AIIR_INGEST_TIMEOUT_SEC:=${AIIR_CONVERT_TIMEOUT_SEC:-1200}}"
fi

if [[ -n "$GATE_OVERALL_MIN" ]]; then
  if ! awk -v n="$GATE_OVERALL_MIN" 'BEGIN{exit !(n ~ /^[0-9]+([.][0-9]+)?$/)}'; then
    echo "invalid --gate-overall-min: ${GATE_OVERALL_MIN}" >&2
    exit 1
  fi
fi

if [[ "$PROFILE" == "quick" && ( "$GATE_ZERO_NEW" == "1" || -n "$GATE_OVERALL_MIN" || "$GATE_NOTE_OK" == "1" || "$GATE_NO_CHUNK" == "1" ) ]]; then
  echo "gate options are supported only with --profile full" >&2
  exit 1
fi

if [[ "$USE_REGRESSION_PACK" == "1" ]]; then
  PACK_FILE="${TEST_DIR}/REPO_REGRESSION_PACK.txt"
  if [[ ! -f "$PACK_FILE" ]]; then
    echo "missing regression pack file: ${PACK_FILE}" >&2
    exit 1
  fi
  while IFS= read -r line; do
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    REPOS+=("$line")
  done < "$PACK_FILE"
fi

run_runner() {
  if [[ "${#REPOS[@]}" -gt 0 ]]; then
    "$runner" "${REPOS[@]}"
  else
    "$runner"
  fi
}

if command -v flock >/dev/null 2>&1; then
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  flock -x 9
  run_runner
  flock -u 9
  exec 9>&-
else
  run_runner
fi

if [[ "$PROFILE" != "full" ]]; then
  exit 0
fi

if [[ "$GATE_ZERO_NEW" != "1" && -z "$GATE_OVERALL_MIN" && "$GATE_NOTE_OK" != "1" && "$GATE_NO_CHUNK" != "1" ]]; then
  exit 0
fi

LOG_FILE="${TEST_DIR}/OPEN_REPO_FULL_LOG.csv"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "missing log file: $LOG_FILE" >&2
  exit 1
fi

run_ts="$(awk -F, 'NR>1 && $1>max {max=$1} END{print max}' "$LOG_FILE")"
if [[ -z "$run_ts" ]]; then
  echo "unable to resolve latest run timestamp from $LOG_FILE" >&2
  exit 1
fi

gate_fail=0
if [[ "$GATE_ZERO_NEW" == "1" ]]; then
  oaiir_new_rows="$(awk -F, -v ts="$run_ts" 'NR>1 && $1==ts && ($18+0)>0 {c++} END{print c+0}' "$LOG_FILE")"
  if [[ "$oaiir_new_rows" != "0" ]]; then
    echo "gate failed (--gate-zero-new): run_ts=${run_ts} rows_with_oaiir_new=${oaiir_new_rows}" >&2
    gate_fail=1
  fi
fi

if [[ -n "$GATE_OVERALL_MIN" ]]; then
  parity_rows="$(awk -F, -v ts="$run_ts" -v min="$GATE_OVERALL_MIN" 'NR>1 && $1==ts && ($25+0)<min {c++} END{print c+0}' "$LOG_FILE")"
  if [[ "$parity_rows" != "0" ]]; then
    echo "gate failed (--gate-overall-min ${GATE_OVERALL_MIN}): run_ts=${run_ts} rows_below_min=${parity_rows}" >&2
    gate_fail=1
  fi
fi

if [[ "$GATE_NOTE_OK" == "1" ]]; then
  note_rows="$(awk -F, -v ts="$run_ts" 'NR>1 && $1==ts && ($29!="ok" && $29!="analysis_chunked_large") {c++} END{print c+0}' "$LOG_FILE")"
  if [[ "$note_rows" != "0" ]]; then
    echo "gate failed (--gate-note-ok): run_ts=${run_ts} rows_with_bad_note=${note_rows}" >&2
    gate_fail=1
  fi
fi

if [[ "$GATE_NO_CHUNK" == "1" ]]; then
  chunk_rows="$(awk -F, -v ts="$run_ts" 'NR>1 && $1==ts && $26!="none" {c++} END{print c+0}' "$LOG_FILE")"
  if [[ "$chunk_rows" != "0" ]]; then
    echo "gate failed (--gate-no-chunk): run_ts=${run_ts} rows_with_chunk_mode=${chunk_rows}" >&2
    gate_fail=1
  fi
fi

if [[ "$gate_fail" == "1" ]]; then
  exit 2
fi

echo "gates passed: run_ts=${run_ts}" >&2
