#!/usr/bin/env bash
set -euo pipefail

HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
PORT="${AI_RUNTIME_PORT:-7791}"
CORE_DIR="${AI_CORE_DIR:-/var/www/aiir/ai/core}"
RUNTIME_BIN="/var/www/aiir/ai/toolchain-native/aiird"

/var/www/aiir/server/scripts/build-native-runtime.sh >/dev/null

TMPDIR="$(mktemp -d)"
cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

AI_RUNTIME_HOST="$HOST" \
AI_RUNTIME_PORT="$PORT" \
AI_CORE_DIR="$CORE_DIR" \
AI_DB_EXEC_MODE="dry-run" \
AI_POLICY_ALLOW_DB_EXEC="0" \
AI_POLICY_ALLOW_OPS="" \
AIIR_GATEWAY_ENABLE="1" \
AIIR_HUMAN_DB_MODE="indirect" \
AIIR_DB_PROVIDER="default" \
AIIR_DB_DEFAULT_PROFILE="default" \
AIIR_DB_REGION="local" \
AIIR_DB_RETENTION_DAYS="30" \
AIIR_PROJECTS_FILE="$TMPDIR/projects.ndjson" \
AI_WAL_PATH="$TMPDIR/ai.wal" \
AI_SNAPSHOT_PATH="$TMPDIR/snapshot.json" \
"$RUNTIME_BIN" serve >"$TMPDIR/runtime.log" 2>&1 &
PID=$!

for _ in $(seq 1 40); do
  if curl -fsS "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

CREATE_HTTP="$(curl -sS -o "$TMPDIR/create.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/aiir/project/create" \
  -H "Content-Type: application/json" \
  -d '{"contract_version":"hal.v1","intent":"create_project","project_name":"smoke-proj","db_profile":"default","region":"local","retention_days":30,"idempotency_key":"smoke-001"}')"
if [[ "$CREATE_HTTP" != "202" ]]; then
  echo "gateway-smoke-failed: create expected 202, got ${CREATE_HTTP}" >&2
  cat "$TMPDIR/create.json" >&2 || true
  exit 1
fi

PROJECT_REF="$(sed -n 's/.*"project_ref":"\([^"]*\)".*/\1/p' "$TMPDIR/create.json" | head -n1)"
DB_REF="$(sed -n 's/.*"db_ref":"\([^"]*\)".*/\1/p' "$TMPDIR/create.json" | head -n1)"
[[ -n "$PROJECT_REF" && -n "$DB_REF" ]] || { echo "gateway-smoke-failed: missing refs"; cat "$TMPDIR/create.json"; exit 1; }

CREATE2_HTTP="$(curl -sS -o "$TMPDIR/create2.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/aiir/project/create" \
  -H "Content-Type: application/json" \
  -d '{"contract_version":"hal.v1","intent":"create_project","project_name":"smoke-proj","db_profile":"default","region":"local","retention_days":30,"idempotency_key":"smoke-001"}')"
if [[ "$CREATE2_HTTP" != "202" ]]; then
  echo "gateway-smoke-failed: idempotent create expected 202, got ${CREATE2_HTTP}" >&2
  cat "$TMPDIR/create2.json" >&2 || true
  exit 1
fi
PROJECT_REF2="$(sed -n 's/.*"project_ref":"\([^"]*\)".*/\1/p' "$TMPDIR/create2.json" | head -n1)"
DB_REF2="$(sed -n 's/.*"db_ref":"\([^"]*\)".*/\1/p' "$TMPDIR/create2.json" | head -n1)"
if [[ "$PROJECT_REF2" != "$PROJECT_REF" || "$DB_REF2" != "$DB_REF" ]]; then
  echo "gateway-smoke-failed: idempotent refs mismatch" >&2
  cat "$TMPDIR/create.json" >&2 || true
  cat "$TMPDIR/create2.json" >&2 || true
  exit 1
fi
if ! rg -q '"idempotent":1' "$TMPDIR/create2.json"; then
  echo "gateway-smoke-failed: idempotent flag missing" >&2
  cat "$TMPDIR/create2.json" >&2 || true
  exit 1
fi

EXEC_HTTP="$(curl -sS -o "$TMPDIR/exec.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/aiir/db/exec" \
  -H "Content-Type: application/json" \
  -d "{\"contract_version\":\"hal.v1\",\"intent\":\"save_data\",\"project_ref\":\"$PROJECT_REF\",\"db_ref\":\"$DB_REF\",\"op_id\":\"entity.upsert\",\"payload\":{\"collection\":\"x\"},\"req_id\":\"smoke-req-1\"}")"
if [[ "$EXEC_HTTP" != "200" ]]; then
  echo "gateway-smoke-failed: exec expected 200, got ${EXEC_HTTP}" >&2
  cat "$TMPDIR/exec.json" >&2 || true
  exit 1
fi
if ! rg -q '"status":"queued"' "$TMPDIR/exec.json"; then
  echo "gateway-smoke-failed: exec response mismatch" >&2
  cat "$TMPDIR/exec.json" >&2 || true
  exit 1
fi

# Negative validation checks (must reject invalid contracts/tokens/intents).
BAD_CONTRACT_HTTP="$(curl -sS -o "$TMPDIR/bad-contract.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/aiir/project/create" \
  -H "Content-Type: application/json" \
  -d '{"contract_version":"hal.v9","intent":"create_project","project_name":"bad-contract","db_profile":"default","region":"local","retention_days":30,"idempotency_key":"smoke-bad-001"}')"
if [[ "$BAD_CONTRACT_HTTP" -lt 400 ]]; then
  echo "gateway-smoke-failed: invalid contract_version unexpectedly accepted (${BAD_CONTRACT_HTTP})" >&2
  cat "$TMPDIR/bad-contract.json" >&2 || true
  exit 1
fi

BAD_TOKEN_HTTP="$(curl -sS -o "$TMPDIR/bad-token.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/aiir/project/create" \
  -H "Content-Type: application/json" \
  -d '{"contract_version":"hal.v1","intent":"create_project","project_name":"bad/name","db_profile":"default","region":"local","retention_days":30,"idempotency_key":"smoke-bad-002"}')"
if [[ "$BAD_TOKEN_HTTP" -lt 400 ]]; then
  echo "gateway-smoke-failed: invalid project_name token unexpectedly accepted (${BAD_TOKEN_HTTP})" >&2
  cat "$TMPDIR/bad-token.json" >&2 || true
  exit 1
fi

BAD_INTENT_HTTP="$(curl -sS -o "$TMPDIR/bad-intent.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/aiir/db/exec" \
  -H "Content-Type: application/json" \
  -d "{\"contract_version\":\"hal.v1\",\"intent\":\"unknown_intent\",\"project_ref\":\"$PROJECT_REF\",\"db_ref\":\"$DB_REF\",\"op_id\":\"entity.upsert\",\"payload\":{\"collection\":\"x\"},\"req_id\":\"smoke-bad-003\"}")"
if [[ "$BAD_INTENT_HTTP" -lt 400 ]]; then
  echo "gateway-smoke-failed: invalid intent unexpectedly accepted (${BAD_INTENT_HTTP})" >&2
  cat "$TMPDIR/bad-intent.json" >&2 || true
  exit 1
fi

echo "gateway-smoke-ok"
cat "$TMPDIR/create.json"
echo
cat "$TMPDIR/create2.json"
echo
cat "$TMPDIR/exec.json"
echo
cat "$TMPDIR/bad-contract.json"
echo
cat "$TMPDIR/bad-token.json"
echo
cat "$TMPDIR/bad-intent.json"
