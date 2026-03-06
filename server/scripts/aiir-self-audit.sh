#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
checks_total=0
checks_ok=0

check_file() {
  local p="$1"
  checks_total=$((checks_total+1))
  if [[ -f "$p" ]]; then
    checks_ok=$((checks_ok+1))
    echo "ok:file:${p}"
  else
    echo "fail:file:${p}"
  fi
}

check_pattern() {
  local p="$1"
  local pattern="$2"
  local label="$3"
  checks_total=$((checks_total+1))
  if rg -q "$pattern" "$p"; then
    checks_ok=$((checks_ok+1))
    echo "ok:pattern:${label}"
  else
    echo "fail:pattern:${label}"
  fi
}

check_file "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md"
check_file "${ROOT}/docs/AI2AI_MIGRATION_POLICY_V1.md"
check_file "${ROOT}/docs/AIIR_GATEWAY_V1.md"
check_file "${ROOT}/server/scripts/aiir-chat.sh"
check_file "${ROOT}/server/scripts/provision-project-domain.sh"
check_file "${ROOT}/server/scripts/aiir-bench.sh"
check_file "${ROOT}/server/scripts/aiir-clean.sh"

check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "reason natively in AIIR" "aiir_native_core"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "Human-facing artifacts \(including JSON\) are adapters" "json_adapter_only"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "mTLS" "no_mtls_baseline"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "JWT" "capability_over_jwt"
check_pattern "${ROOT}/server/scripts/provision-project-domain.sh" "AIIR_DB_ALLOW_DIRECT_CREDENTIALS=0" "no_direct_db_credentials"
check_pattern "${ROOT}/server/scripts/provision-project-domain.sh" "AIIR_HUMAN_DB_MODE=indirect" "human_indirect_db_mode"
check_pattern "${ROOT}/server/scripts/aiir-chat.sh" "confirmation_required" "destructive_confirmation_gate"
check_pattern "${ROOT}/server/scripts/aiir-chat.sh" "ferma runtime conferma" "chat_confirm_intent"

status="ok"
if [[ "$checks_ok" -ne "$checks_total" ]]; then
  status="fail"
fi

cat <<EOF2
{"ok":$([[ "$status" == "ok" ]] && echo 1 || echo 0),"action":"self_audit","status":"${status}","checks_ok":${checks_ok},"checks_total":${checks_total}}
EOF2

if [[ "$status" != "ok" ]]; then
  exit 1
fi
