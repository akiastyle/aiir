#!/usr/bin/env bash
set -euo pipefail

HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
PORT="${AI_RUNTIME_PORT:-7789}"
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
AI_WAL_PATH="$TMPDIR/ai.wal" \
AI_SNAPSHOT_PATH="$TMPDIR/snapshot.json" \
AI_MAX_REQ_BYTES="131072" \
AI_MAX_BODY_BYTES="8192" \
AI_IO_TIMEOUT_MS="1000" \
"$RUNTIME_BIN" serve >"$TMPDIR/runtime.log" 2>&1 &
PID=$!

for _ in $(seq 1 40); do
  if curl -fsS "http://${HOST}:${PORT}/health" >"$TMPDIR/health.json" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

curl -fsS "http://${HOST}:${PORT}/health" >"$TMPDIR/health.json"
curl -fsS "http://${HOST}:${PORT}/ai/meta" >"$TMPDIR/meta.json"

DB_HTTP="$(curl -sS -o "$TMPDIR/db.json" -w "%{http_code}" -X POST "http://${HOST}:${PORT}/ai/db/exec" \
  -H "Content-Type: application/json" \
  -d '{"opId":1,"args":[]}')"
if [[ "$DB_HTTP" != "400" ]]; then
  echo "smoke-failed: db/exec expected 400, got ${DB_HTTP}" >&2
  cat "$TMPDIR/db.json" >&2 || true
  exit 1
fi

echo "smoke-ok"
cat "$TMPDIR/health.json"
echo
cat "$TMPDIR/meta.json"
