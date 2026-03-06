#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
PORT="${AI_RUNTIME_PORT:-7788}"
START_SCRIPT="${ROOT}/server/scripts/start-runtime.sh"
UP_SCRIPT="${ROOT}/server/scripts/aiir-up.sh"
DOWN_SCRIPT="${ROOT}/server/scripts/aiir-down.sh"
CHAT_SCRIPT="${ROOT}/server/scripts/aiir-chat.sh"
CHECK_SCRIPT="${ROOT}/server/scripts/check-runtime.sh"
AUDIT_SCRIPT="${ROOT}/server/scripts/aiir-self-audit.sh"
CORE_DIR="${AI_CORE_DIR:-${ROOT}/ai/core}"
STRICT="0"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-doctor.sh [--host <host>] [--port <port>] [--strict]

notes:
  - returns 0 by default even if runtime is down (diagnostic mode)
  - with --strict returns non-zero when checks fail
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --strict) STRICT="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

failures=0
warns=0

check_file() {
  local p="$1"
  local label="$2"
  if [[ -f "$p" ]]; then
    echo "ok ${label}=${p}"
  else
    echo "fail ${label}=${p}"
    failures=$((failures+1))
  fi
}

check_exec() {
  local p="$1"
  local label="$2"
  if [[ -x "$p" ]]; then
    echo "ok ${label}=${p}"
  else
    echo "fail ${label}=${p}"
    failures=$((failures+1))
  fi
}

check_dir() {
  local p="$1"
  local label="$2"
  if [[ -d "$p" ]]; then
    echo "ok ${label}=${p}"
  else
    echo "fail ${label}=${p}"
    failures=$((failures+1))
  fi
}

echo "aiir-doctor"
echo "target=http://${HOST}:${PORT}"
check_exec "$START_SCRIPT" "start_script"
check_exec "$UP_SCRIPT" "up_script"
check_exec "$DOWN_SCRIPT" "down_script"
check_exec "$CHAT_SCRIPT" "chat_script"
check_exec "$CHECK_SCRIPT" "check_script"
check_exec "$AUDIT_SCRIPT" "audit_script"
check_dir "$CORE_DIR" "core_dir"
check_file "${ROOT}/server/env/ai-runtime.env" "runtime_env"
check_file "${ROOT}/server/env/ai-gateway.env" "gateway_env"

if curl --connect-timeout 1 --max-time 2 -fsS "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
  echo "ok runtime=up"
  if "$CHECK_SCRIPT" "$HOST" "$PORT" >/tmp/aiir-doctor-runtime.$$ 2>/tmp/aiir-doctor-runtime.err.$$; then
    echo "ok runtime_endpoints=healthy"
  else
    echo "fail runtime_endpoints=check-runtime-failed"
    failures=$((failures+1))
  fi
  rm -f /tmp/aiir-doctor-runtime.$$ /tmp/aiir-doctor-runtime.err.$$ || true
else
  echo "warn runtime=down"
  warns=$((warns+1))
fi

if "$AUDIT_SCRIPT" >/tmp/aiir-doctor-audit.$$ 2>/tmp/aiir-doctor-audit.err.$$; then
  echo "ok ai_first_audit=pass"
else
  echo "fail ai_first_audit=failed"
  failures=$((failures+1))
fi
rm -f /tmp/aiir-doctor-audit.$$ /tmp/aiir-doctor-audit.err.$$ || true

if [[ "$failures" -eq 0 ]]; then
  echo "doctor_status=ok"
else
  echo "doctor_status=fail"
fi
echo "failures=${failures}"
echo "warnings=${warns}"

if [[ "$STRICT" == "1" && ( "$failures" -gt 0 || "$warns" -gt 0 ) ]]; then
  exit 1
fi
