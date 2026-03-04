#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
CLI="${ROOT}/server/scripts/aiir"
PORT="${AI_RUNTIME_PORT:-7792}"
HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
PID_FILE="${AIIR_RUNTIME_PID_FILE:-/tmp/aiir-smoke.pid}"
OUT_LOG="${AIIR_RUNTIME_OUT_LOG:-/tmp/aiir-smoke.out.log}"
ERR_LOG="${AIIR_RUNTIME_ERR_LOG:-/tmp/aiir-smoke.err.log}"
PROJECT="smoke-aiops"
DOMAIN="smoke-aiops.local"

cleanup_project_artifacts() {
  local project="$1"
  local projects_file="${ROOT}/ai/state/projects.ndjson"
  if [[ -f "$projects_file" ]]; then
    rg '"project_name":"'"${project}"'"' "$projects_file" | sed -n 's/.*"project_ref":"\([^"]*\)".*/\1/p' | while read -r prj; do
      [[ -z "$prj" ]] && continue
      rm -f "${ROOT}/server/env/projects/${prj}.env" "${ROOT}/server/generated/apache/${prj}.conf" "${ROOT}/server/generated/nginx/${prj}.conf"
      rm -rf "${ROOT}/ai/state/projects/${prj}"
    done
    tmp="$(mktemp)"
    rg -v '"project_name":"'"${project}"'"' "$projects_file" > "$tmp" || true
    mv "$tmp" "$projects_file"
  fi
}

cleanup() {
  AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" AIIR_RUNTIME_PID_FILE="$PID_FILE" "$CLI" down --force >/dev/null 2>&1 || true
  cleanup_project_artifacts "$PROJECT"
  rm -f "$PID_FILE" "$OUT_LOG" "$ERR_LOG" /tmp/aiir-smoke-*.json /tmp/aiir-smoke-*.txt
}
trap cleanup EXIT

AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" AIIR_RUNTIME_PID_FILE="$PID_FILE" AIIR_RUNTIME_OUT_LOG="$OUT_LOG" AIIR_RUNTIME_ERR_LOG="$ERR_LOG" \
  "$CLI" up --project "$PROJECT" --type webapp --domain "$DOMAIN" > /tmp/aiir-smoke-up.txt

AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" chat "stato" > /tmp/aiir-smoke-health.json
AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" chat "lista progetti" > /tmp/aiir-smoke-list.json
AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" chat "stato progetto $PROJECT" > /tmp/aiir-smoke-status.json
AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" chat "ottimizza progetto $PROJECT" > /tmp/aiir-smoke-opt.json
AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" chat "ui progetto $PROJECT preset material" > /tmp/aiir-smoke-ui.json
AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" doctor --strict > /tmp/aiir-smoke-doctor-up.txt

if AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" chat "ferma runtime" >/tmp/aiir-smoke-stop-no.txt 2>&1; then
  echo "smoke-ai-ops-failed: stop without confirmation unexpectedly succeeded" >&2
  exit 1
fi
if ! rg -q 'confirmation_required' /tmp/aiir-smoke-stop-no.txt; then
  echo "smoke-ai-ops-failed: confirmation gate missing" >&2
  cat /tmp/aiir-smoke-stop-no.txt >&2
  exit 1
fi

AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" chat "ferma runtime conferma" > /tmp/aiir-smoke-stop-yes.txt

if curl -fsS "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
  echo "smoke-ai-ops-failed: runtime still up after confirmed stop" >&2
  exit 1
fi

if AI_RUNTIME_HOST="$HOST" AI_RUNTIME_PORT="$PORT" "$CLI" doctor --strict >/tmp/aiir-smoke-doctor-down.txt 2>&1; then
  echo "smoke-ai-ops-failed: doctor --strict should fail while runtime is down" >&2
  exit 1
fi

if ! rg -q '"ok":1' /tmp/aiir-smoke-health.json; then
  echo "smoke-ai-ops-failed: health output invalid" >&2
  exit 1
fi
if ! rg -q '"project_name":"'"$PROJECT"'"' /tmp/aiir-smoke-status.json; then
  echo "smoke-ai-ops-failed: status output invalid" >&2
  exit 1
fi
if ! rg -q '"action":"optimize_project"' /tmp/aiir-smoke-opt.json; then
  echo "smoke-ai-ops-failed: optimize output invalid" >&2
  exit 1
fi
if ! rg -q '"action":"ui_scaffold"' /tmp/aiir-smoke-ui.json; then
  echo "smoke-ai-ops-failed: ui scaffold output invalid" >&2
  exit 1
fi
ui_html="$(sed -n 's/.*"ui_html":"\([^"]*\)".*/\1/p' /tmp/aiir-smoke-ui.json | head -n1)"
if [[ -z "$ui_html" || ! -f "$ui_html" ]]; then
  echo "smoke-ai-ops-failed: ui scaffold file missing" >&2
  exit 1
fi

echo "smoke-ai-ops-ok"
cat /tmp/aiir-smoke-up.txt
cat /tmp/aiir-smoke-status.json
cat /tmp/aiir-smoke-opt.json
cat /tmp/aiir-smoke-ui.json
