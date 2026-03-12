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
check_file "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md"
check_file "${ROOT}/docs/OAIIR_WEB_OPCODE_REGISTRY_V0.csv"
check_file "${ROOT}/docs/OAIIR_WEB_HTML_CATALOG_V0.csv"
check_file "${ROOT}/docs/OAIIR_WEB_CSS_CATALOG_V0.csv"
check_file "${ROOT}/docs/OAIIR_WEB_JS_CATALOG_V0.csv"
check_file "${ROOT}/server/scripts/aiir-chat.sh"
check_file "${ROOT}/server/scripts/aiir-deploy.sh"
check_file "${ROOT}/server/scripts/provision-project-domain.sh"
check_file "${ROOT}/server/scripts/aiir-bench.sh"
check_file "${ROOT}/server/scripts/aiir-clean.sh"
check_file "${ROOT}/server/scripts/aiir-enable-automation.sh"
check_file "${ROOT}/server/scripts/aiir-ingest-project.sh"
check_file "${ROOT}/server/scripts/aiir-oaiir-exec.sh"
check_file "${ROOT}/server/scripts/aiir-oaiir-exec.js"
check_file "${ROOT}/server/scripts/aiir-contract-test.sh"
check_file "${ROOT}/server/scripts/aiir-verify.sh"
check_file "${ROOT}/server/scripts/smoke-ai-ops.sh"
check_file "${ROOT}/test/REPO_REGRESSION_PACK.txt"
check_file "${ROOT}/test/run-regression-pack.sh"
check_file "${ROOT}/server/systemd/aiir-smoke.service"
check_file "${ROOT}/server/systemd/aiir-self-audit.timer"
check_file "${ROOT}/server/systemd/aiir-contract-pack.timer"
check_file "${ROOT}/server/cron/aiir-maintenance"

check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "reason natively in AIIR" "aiir_native_core"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "Human-facing artifacts \(including JSON\) are adapters" "json_adapter_only"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "mTLS" "no_mtls_baseline"
check_pattern "${ROOT}/docs/AIIR_AI_FIRST_PRINCIPLES.md" "JWT" "capability_over_jwt"
check_pattern "${ROOT}/docs/AI2AI_MIGRATION_POLICY_V1.md" "Primary mode is AIIR-native" "migration_primary_mode"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir audit" "runbook_has_audit"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir ingest" "runbook_prefers_ingest"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir deploy" "runbook_has_deploy"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "strict-web-apply" "runbook_has_deploy_strict"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir contract" "runbook_has_contract"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir verify" "runbook_has_verify"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "aiir oaiir" "runbook_has_oaiir_exec"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "regression-pack" "runbook_has_regression_pack"
check_pattern "${ROOT}/docs/AI_OPERATIONS_RUNBOOK.md" "OPEN_REPO_FULL_PROFILE.csv" "runbook_has_profile_output"
check_pattern "${ROOT}/server/scripts/aiir" "ingest[[:space:]]+source project" "cli_has_ingest"
check_pattern "${ROOT}/server/scripts/aiir" "deploy[[:space:]]+AI-first deploy" "cli_has_deploy"
check_pattern "${ROOT}/server/scripts/aiir" "contract[[:space:]]+run AIIR contract test pack" "cli_has_contract"
check_pattern "${ROOT}/server/scripts/aiir" "verify[[:space:]]+run consolidated verification pack" "cli_has_verify"
check_pattern "${ROOT}/server/scripts/aiir" "oaiir[[:space:]]+execute OAIIR web IR" "cli_has_oaiir_exec"
check_pattern "${ROOT}/server/scripts/aiir-convert-project.sh" "OAIIR_WEB_OPCODE_REGISTRY_V0.csv" "ingest_uses_oaiir_registry"
check_pattern "${ROOT}/server/scripts/aiir-convert-project.sh" "OAIIR_WEB_HTML_CATALOG_V0.csv" "ingest_uses_oaiir_html_catalog"
check_pattern "${ROOT}/server/scripts/aiir-convert-project.sh" "OAIIR_WEB_CSS_CATALOG_V0.csv" "ingest_uses_oaiir_css_catalog"
check_pattern "${ROOT}/server/scripts/aiir-convert-project.sh" "OAIIR_WEB_JS_CATALOG_V0.csv" "ingest_uses_oaiir_js_catalog"
check_pattern "${ROOT}/server/scripts/provision-project-domain.sh" "AIIR_DB_ALLOW_DIRECT_CREDENTIALS=0" "no_direct_db_credentials"
check_pattern "${ROOT}/server/scripts/provision-project-domain.sh" "AIIR_HUMAN_DB_MODE=indirect" "human_indirect_db_mode"
check_pattern "${ROOT}/server/scripts/provision-project-domain.sh" "a2enmod proxy proxy_http" "apache_proxy_autoload"
check_pattern "${ROOT}/server/scripts/aiir-chat.sh" "confirmation_required" "destructive_confirmation_gate"
check_pattern "${ROOT}/server/scripts/aiir-chat.sh" "ferma runtime conferma" "chat_confirm_intent"
check_pattern "${ROOT}/server/scripts/smoke-ai-ops.sh" "aiir-smoke-audit-up.json" "smoke_runs_audit"
check_pattern "${ROOT}/server/scripts/smoke-gateway.sh" "bad-contract.json" "gateway_negative_contract"
check_pattern "${ROOT}/server/scripts/smoke-gateway.sh" "bad-token.json" "gateway_negative_token"
check_pattern "${ROOT}/server/scripts/smoke-gateway.sh" "bad-intent.json" "gateway_negative_intent"
check_pattern "${ROOT}/test/benchmark-open-repos-full.sh" "aiir\" ingest" "benchmark_prefers_ingest"
check_pattern "${ROOT}/test/benchmark-open-repos-full.sh" "OPEN_REPO_FULL_PROFILE.csv" "benchmark_has_profile_csv"
check_pattern "${ROOT}/server/systemd/aiir-smoke.service" "smoke-ai-ops.sh" "systemd_smoke_ai_ops"
check_pattern "${ROOT}/server/systemd/aiir-self-audit.timer" "OnCalendar=hourly" "systemd_hourly_audit"
check_pattern "${ROOT}/server/systemd/aiir-contract-pack.timer" "OnCalendar=" "systemd_contract_pack_timer"
check_pattern "${ROOT}/server/cron/aiir-maintenance" "self-audit hourly" "cron_hourly_audit"
check_pattern "${ROOT}/server/cron/aiir-maintenance" "contract test pack daily" "cron_contract_pack_daily"

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
