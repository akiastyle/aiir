#!/usr/bin/env bash
set -euo pipefail

HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
PORT="${AI_RUNTIME_PORT:-7790}"
CORE_DIR="${AI_CORE_DIR:-/var/www/aiir/ai/core}"
RUNTIME_BIN="/var/www/aiir/ai/toolchain-native/aiird"
CAP_SECRET="${AI_CAP_SECRET:-aiir-test-secret}"
OP_ID="${AI_CAP_TEST_OP_ID:-1}"

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
AI_POLICY_ALLOW_DB_EXEC="1" \
AI_POLICY_ALLOW_OPS="*" \
AI_CAP_REQUIRE="1" \
AI_CAP_SECRET="$CAP_SECRET" \
AI_CAP_MAX_FUTURE_SEC="120" \
AI_AUDIT_LOG_PATH="$TMPDIR/runtime_audit.log" \
AI_LOG_REQUESTS="1" \
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

EXP="$(( $(date +%s) + 30 ))"
NONCE="nonce-smoke-001"
SIG="$("$RUNTIME_BIN" cap-sign "$CAP_SECRET" "$OP_ID" "$EXP" "$NONCE")"

HTTP1="$(curl -sS -o "$TMPDIR/first.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/ai/db/exec" \
  -H "Content-Type: application/json" \
  -H "X-AIIR-Cap-Op: $OP_ID" \
  -H "X-AIIR-Cap-Exp: $EXP" \
  -H "X-AIIR-Cap-Nonce: $NONCE" \
  -H "X-AIIR-Cap-Sig: $SIG" \
  -d "{\"opId\":$OP_ID,\"args\":[]}")"
if [[ "$HTTP1" != "200" && "$HTTP1" != "400" ]]; then
  echo "cap-smoke-failed: first request expected 200/400, got ${HTTP1}" >&2
  cat "$TMPDIR/first.json" >&2 || true
  exit 1
fi
if rg -q '"err":"capability"' "$TMPDIR/first.json"; then
  echo "cap-smoke-failed: first request must pass capability checks" >&2
  cat "$TMPDIR/first.json" >&2 || true
  exit 1
fi

HTTP2="$(curl -sS -o "$TMPDIR/replay.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/ai/db/exec" \
  -H "Content-Type: application/json" \
  -H "X-AIIR-Cap-Op: $OP_ID" \
  -H "X-AIIR-Cap-Exp: $EXP" \
  -H "X-AIIR-Cap-Nonce: $NONCE" \
  -H "X-AIIR-Cap-Sig: $SIG" \
  -d "{\"opId\":$OP_ID,\"args\":[]}")"
if [[ "$HTTP2" != "400" ]]; then
  echo "cap-smoke-failed: replay expected 400, got ${HTTP2}" >&2
  cat "$TMPDIR/replay.json" >&2 || true
  exit 1
fi
if ! rg -q '"err":"capability"' "$TMPDIR/replay.json"; then
  echo "cap-smoke-failed: replay body mismatch" >&2
  cat "$TMPDIR/replay.json" >&2 || true
  exit 1
fi

EXP_OLD="$(( $(date +%s) - 10 ))"
NONCE_OLD="nonce-smoke-002"
SIG_OLD="$("$RUNTIME_BIN" cap-sign "$CAP_SECRET" "$OP_ID" "$EXP_OLD" "$NONCE_OLD")"
HTTP3="$(curl -sS -o "$TMPDIR/expired.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/ai/db/exec" \
  -H "Content-Type: application/json" \
  -H "X-AIIR-Cap-Op: $OP_ID" \
  -H "X-AIIR-Cap-Exp: $EXP_OLD" \
  -H "X-AIIR-Cap-Nonce: $NONCE_OLD" \
  -H "X-AIIR-Cap-Sig: $SIG_OLD" \
  -d "{\"opId\":$OP_ID,\"args\":[]}")"
if [[ "$HTTP3" != "400" ]]; then
  echo "cap-smoke-failed: expired expected 400, got ${HTTP3}" >&2
  cat "$TMPDIR/expired.json" >&2 || true
  exit 1
fi

echo "cap-smoke-ok"
cat "$TMPDIR/first.json"
echo
cat "$TMPDIR/replay.json"
echo
cat "$TMPDIR/expired.json"
