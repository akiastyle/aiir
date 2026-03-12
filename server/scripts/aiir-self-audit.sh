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

check_absent_pattern() {
  local p="$1"
  local pattern="$2"
  local label="$3"
  checks_total=$((checks_total+1))
  if rg -q "$pattern" "$p"; then
    echo "fail:pattern_present:${label}"
  else
    checks_ok=$((checks_ok+1))
    echo "ok:pattern_absent:${label}"
  fi
}

# AI-first docs and runtime core
check_file "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md"
check_file "${ROOT}/docs/AIIR_CODEC_POLICY_V1.md"
check_file "${ROOT}/docs/AI2AI_MIGRATION_POLICY_V1.md"
check_file "${ROOT}/docs/AIIR_GATEWAY_V1.md"
check_file "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md"
check_file "${ROOT}/docs/OAIIR_WEB_OPCODE_REGISTRY_V0.csv"
check_file "${ROOT}/docs/OAIIR_WEB_HTML_CATALOG_V0.csv"
check_file "${ROOT}/docs/OAIIR_WEB_CSS_CATALOG_V0.csv"
check_file "${ROOT}/docs/OAIIR_WEB_JS_CATALOG_V0.csv"

# Core scripts only
check_file "${ROOT}/server/scripts/aiir"
check_file "${ROOT}/server/scripts/aiir-up.sh"
check_file "${ROOT}/server/scripts/aiir-down.sh"
check_file "${ROOT}/server/scripts/aiir-chat.sh"
check_file "${ROOT}/server/scripts/aiir-doctor.sh"
check_file "${ROOT}/server/scripts/aiir-verify.sh"
check_file "${ROOT}/server/scripts/aiir-clean.sh"
check_file "${ROOT}/server/scripts/aiir-ingest-project.sh"
check_file "${ROOT}/server/scripts/aiir-oaiir-exec.sh"
check_file "${ROOT}/server/scripts/aiir-oaiir-exec.js"
check_file "${ROOT}/server/scripts/aiir-parity-check.sh"
check_file "${ROOT}/server/scripts/aiir-bench.sh"
check_file "${ROOT}/server/scripts/aiir-tune-self.sh"
check_file "${ROOT}/server/scripts/start-runtime.sh"
check_file "${ROOT}/server/scripts/check-runtime.sh"
check_file "${ROOT}/server/scripts/provision-project-domain.sh"
check_file "${ROOT}/server/scripts/project-type-map.sh"
check_file "${ROOT}/server/env/ai-first-tuning.env"
check_file "${ROOT}/server/env/ai-codec.env"
check_file "${ROOT}/test/benchmark-open-repos-full.sh"
check_file "${ROOT}/test/REPO_REGRESSION_PACK.txt"

# Policy/behavioral assertions
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "reason natively in AIIR" "aiir_native_core"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "Human-facing artifacts \(including JSON\) are adapters" "json_adapter_only"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "mTLS" "no_mtls_baseline"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "JWT" "capability_over_jwt"
check_pattern "${ROOT}/docs/AIIR_CODEC_POLICY_V1.md" "binary-first" "codec_binary_first"
check_pattern "${ROOT}/docs/AIIR_CODEC_POLICY_V1.md" "base64" "codec_base64_text_fallback"
check_pattern "${ROOT}/docs/AIIR_CODEC_POLICY_V1.md" "base32" "codec_base32_emergency_only"
check_pattern "${ROOT}/docs/AI2AI_MIGRATION_POLICY_V1.md" "Primary mode is AIIR-native" "migration_primary_mode"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir audit" "runbook_has_audit"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir ingest" "runbook_prefers_ingest"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir verify" "runbook_has_verify"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir oaiir" "runbook_has_oaiir_exec"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "regression-pack" "runbook_has_regression_pack"
check_pattern "${ROOT}/server/scripts/aiir" "^  ingest\\)" "cli_has_ingest"
check_pattern "${ROOT}/server/scripts/aiir" "^  verify\\)" "cli_has_verify"
check_pattern "${ROOT}/server/scripts/aiir" "^  oaiir\\)" "cli_has_oaiir_exec"
check_pattern "${ROOT}/server/scripts/aiir" "^  tune\\)" "cli_has_tune"
check_pattern "${ROOT}/server/scripts/aiir-bench.sh" "AIIR_BENCH_LOCK_FILE" "bench_has_lock"
check_pattern "${ROOT}/server/scripts/aiir-ingest-project.sh" "OAIIR_WEB_OPCODE_REGISTRY_V0.csv" "ingest_uses_oaiir_registry"
check_pattern "${ROOT}/server/scripts/aiir-ingest-project.sh" "OAIIR_WEB_HTML_CATALOG_V0.csv" "ingest_uses_oaiir_html_catalog"
check_pattern "${ROOT}/server/scripts/aiir-ingest-project.sh" "OAIIR_WEB_CSS_CATALOG_V0.csv" "ingest_uses_oaiir_css_catalog"
check_pattern "${ROOT}/server/scripts/aiir-ingest-project.sh" "OAIIR_WEB_JS_CATALOG_V0.csv" "ingest_uses_oaiir_js_catalog"
check_pattern "${ROOT}/server/scripts/start-runtime.sh" "AIIR_CODEC_OPERATIONAL" "runtime_has_codec_policy"
check_pattern "${ROOT}/server/scripts/start-runtime.sh" "AIIR_CODEC_HUMAN_EMERGENCY:=base32" "runtime_declares_base32_emergency_only"
check_pattern "${ROOT}/ai/exchange/build-package.run.sh" "AIIR_CODEC_OPERATIONAL" "build_has_codec_policy"
check_pattern "${ROOT}/ai/exchange/unpack-package.run.sh" "AIIR_CODEC_OPERATIONAL" "unpack_has_codec_policy"
check_pattern "${ROOT}/server/scripts/provision-project-domain.sh" "AIIR_DB_ALLOW_DIRECT_CREDENTIALS=0" "no_direct_db_credentials"
check_pattern "${ROOT}/server/scripts/provision-project-domain.sh" "AIIR_HUMAN_DB_MODE=indirect" "human_indirect_db_mode"
check_pattern "${ROOT}/server/scripts/aiir-chat.sh" "confirmation_required" "destructive_confirmation_gate"
check_pattern "${ROOT}/server/scripts/aiir-chat.sh" "ferma runtime conferma" "chat_confirm_intent"
check_absent_pattern "${ROOT}/server/scripts/aiir-chat.sh" "base32" "no_base32_in_chat"
check_absent_pattern "${ROOT}/server/scripts/aiir-up.sh" "base32" "no_base32_in_up"
check_absent_pattern "${ROOT}/server/scripts/aiir-ingest-project.sh" "base32" "no_base32_in_ingest"
check_absent_pattern "${ROOT}/ai/runtime-server-native/ai_runtime_native.c" "base32" "no_base32_in_runtime_native"

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
