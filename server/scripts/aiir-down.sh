#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
PID_FILE="${AIIR_RUNTIME_PID_FILE:-${ROOT}/ai/state/runtime.pid}"
HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
PORT="${AI_RUNTIME_PORT:-7788}"
TIMEOUT_SEC="${AIIR_DOWN_TIMEOUT_SEC:-8}"
FORCE="0"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-down.sh [--host <host>] [--port <port>] [--pid-file <path>] [--force]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --pid-file) PID_FILE="${2:-}"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

pid=""
if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
fi

stopped="0"

if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 "$TIMEOUT_SEC"); do
    if ! kill -0 "$pid" 2>/dev/null; then
      stopped="1"
      break
    fi
    sleep 1
  done
  if [[ "$stopped" != "1" && "$FORCE" == "1" ]]; then
    kill -9 "$pid" 2>/dev/null || true
    if ! kill -0 "$pid" 2>/dev/null; then
      stopped="1"
    fi
  fi
fi

if [[ -f "$PID_FILE" ]]; then
  if [[ -z "$pid" ]]; then
    rm -f "$PID_FILE"
  elif ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PID_FILE"
  fi
fi

if curl -fsS "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
  echo "aiir-down-warn: runtime still reachable at ${HOST}:${PORT}" >&2
  if [[ "$FORCE" == "1" ]]; then
    exit 1
  fi
fi

cat <<EOF2
aiir-down-ok
host=${HOST}
port=${PORT}
pid_file=${PID_FILE}
stopped=${stopped}
EOF2
