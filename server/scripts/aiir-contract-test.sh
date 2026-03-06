#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
AUDIT="${ROOT}/server/scripts/aiir-self-audit.sh"
GW_SMOKE="${ROOT}/server/scripts/smoke-gateway.sh"
OPS_SMOKE="${ROOT}/server/scripts/smoke-ai-ops.sh"
DEPLOY="${ROOT}/server/scripts/aiir-deploy.sh"

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

# Always run AI-first compliance audit.
"$AUDIT" >"${TMPDIR}/audit.out"

if [[ "$RUN_DEPLOY_DRY" == "1" ]]; then
  "$DEPLOY" --dry-run --project contract-pack --type webapp --domain contract.local >"${TMPDIR}/deploy-dry.out"
fi

if [[ "$RUN_GATEWAY" == "1" ]]; then
  "$GW_SMOKE" >"${TMPDIR}/gateway.out"
fi

if [[ "$RUN_AI_OPS" == "1" ]]; then
  "$OPS_SMOKE" >"${TMPDIR}/aiops.out"
fi

cat <<EOF2
{"ok":1,"action":"contract_test_pack","audit":1,"gateway":${RUN_GATEWAY},"ai_ops":${RUN_AI_OPS},"deploy_dry":${RUN_DEPLOY_DRY}}
EOF2
