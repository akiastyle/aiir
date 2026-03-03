#!/usr/bin/env bash
set -euo pipefail

PROJECT_REF="${1:-global}"
DAYS="${2:-30}"
SCOPE="${3:-browser_connect}"

if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [[ "$DAYS" -lt 1 || "$DAYS" -gt 365 ]]; then
  echo "days must be an integer between 1 and 365" >&2
  exit 1
fi

ROOT="/var/www/aiir"
STATE_DIR="${AIIR_STATE_DIR:-${ROOT}/ai/state}"
OUT_FILE="${AIIR_BROWSER_CODES_FILE:-${STATE_DIR}/browser-access-codes.ndjson}"

mkdir -p "${STATE_DIR}"
touch "${OUT_FILE}"

if command -v openssl >/dev/null 2>&1; then
  RAW="$(openssl rand -hex 20)"
else
  RAW="$(date +%s)-$$-$RANDOM-$RANDOM"
fi

CODE="brw_${RAW}"
CODE_SHA="$(printf '%s' "${CODE}" | sha256sum | awk '{print $1}')"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXPIRES_AT="$(date -u -d "+${DAYS} days" +%Y-%m-%dT%H:%M:%SZ)"

if command -v flock >/dev/null 2>&1; then
  exec 9>>"${OUT_FILE}"
  flock -x 9
  printf '{"created_at":"%s","expires_at":"%s","project_ref":"%s","scope":"%s","code_sha256":"%s","status":"active"}\n' \
    "${CREATED_AT}" "${EXPIRES_AT}" "${PROJECT_REF}" "${SCOPE}" "${CODE_SHA}" >> "${OUT_FILE}"
  flock -u 9
  exec 9>&-
else
  printf '{"created_at":"%s","expires_at":"%s","project_ref":"%s","scope":"%s","code_sha256":"%s","status":"active"}\n' \
    "${CREATED_AT}" "${EXPIRES_AT}" "${PROJECT_REF}" "${SCOPE}" "${CODE_SHA}" >> "${OUT_FILE}"
fi

cat <<EOF
browser-access-code-generated
project_ref=${PROJECT_REF}
scope=${SCOPE}
expires_at=${EXPIRES_AT}
code=${CODE}
EOF
