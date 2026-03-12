#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
AUDIT="${ROOT}/server/scripts/aiir-self-audit.sh"
DEPLOY="${ROOT}/server/scripts/aiir-deploy.sh"
CHECK="${ROOT}/server/scripts/check-runtime.sh"
HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
PORT="${AI_RUNTIME_PORT:-7788}"
RUN_GATEWAY="1"
RUN_AI_OPS="1"
RUN_DEPLOY_DRY="1"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-contract-test.sh [--no-gateway] [--no-ai-ops] [--no-deploy-dry]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-gateway)
      RUN_GATEWAY="0"
      shift ;;
    --no-ai-ops)
      RUN_AI_OPS="0"
      shift ;;
    --no-deploy-dry)
      RUN_DEPLOY_DRY="0"
      shift ;;
    -h|--help)
      usage
      exit 0 ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 1 ;;
  esac
done

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

"$AUDIT" >"${TMPDIR}/audit.out"

if [[ "$RUN_DEPLOY_DRY" == "1" ]]; then
  "$DEPLOY" --dry-run --project contract-pack --type webapp --domain contract.local >"${TMPDIR}/deploy-dry.out"
fi

gateway_ok=1
if [[ "$RUN_GATEWAY" == "1" ]]; then
  if curl --connect-timeout 1 --max-time 2 -fsS "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
    if ! "$CHECK" "$HOST" "$PORT" >"${TMPDIR}/gateway.out" 2>"${TMPDIR}/gateway.err"; then
      gateway_ok=0
    fi
  else
    echo "runtime_down_skip_gateway_check" >"${TMPDIR}/gateway.out"
  fi
fi

ai_ops_ok=1
if [[ "$RUN_AI_OPS" == "1" ]]; then
  if [[ ! -s "/var/www/aiir/docs/AI_OPERATIONS_RUNBOOK.md" ]]; then
    ai_ops_ok=0
  fi
fi

ok=1
if [[ "$gateway_ok" != "1" || "$ai_ops_ok" != "1" ]]; then
  ok=0
fi

cat <<EOF2
{"ok":${ok},"action":"contract_test_pack","audit":1,"gateway":${gateway_ok},"ai_ops":${ai_ops_ok},"deploy_dry":${RUN_DEPLOY_DRY}}
EOF2

if [[ "$ok" != "1" ]]; then
  exit 1
fi
