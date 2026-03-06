#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir/server/scripts"
DOCTOR="${ROOT}/aiir-doctor.sh"
AUDIT="${ROOT}/aiir-self-audit.sh"
CONTRACT="${ROOT}/aiir-contract-test.sh"

RUN_DOCTOR="1"
RUN_AUDIT="1"
RUN_CONTRACT="1"
STRICT_DOCTOR="0"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-verify.sh [--strict] [--skip-doctor] [--skip-audit] [--skip-contract]

notes:
  - runs a single AIIR verification pack
  - default flow: doctor + audit + contract
  - --strict enables doctor strict mode
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT_DOCTOR="1"
      shift ;;
    --skip-doctor)
      RUN_DOCTOR="0"
      shift ;;
    --skip-audit)
      RUN_AUDIT="0"
      shift ;;
    --skip-contract)
      RUN_CONTRACT="0"
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

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

doctor_ok=0
audit_ok=0
contract_ok=0
failed=0

run_step() {
  local name="$1"
  shift
  local out="${tmpdir}/${name}.out"
  local err="${tmpdir}/${name}.err"
  if "$@" >"$out" 2>"$err"; then
    echo "verify_step=${name} status=ok"
    return 0
  fi
  echo "verify_step=${name} status=fail"
  if [[ -s "$err" ]]; then
    sed -n '1,20p' "$err" >&2 || true
  fi
  failed=1
  return 1
}

if [[ "$RUN_DOCTOR" == "1" ]]; then
  if [[ "$STRICT_DOCTOR" == "1" ]]; then
    run_step doctor "$DOCTOR" --strict && doctor_ok=1 || true
  else
    run_step doctor "$DOCTOR" && doctor_ok=1 || true
  fi
fi

if [[ "$RUN_AUDIT" == "1" ]]; then
  run_step audit "$AUDIT" && audit_ok=1 || true
fi

if [[ "$RUN_CONTRACT" == "1" ]]; then
  run_step contract "$CONTRACT" && contract_ok=1 || true
fi

if [[ "$RUN_DOCTOR" == "0" ]]; then doctor_ok=1; fi
if [[ "$RUN_AUDIT" == "0" ]]; then audit_ok=1; fi
if [[ "$RUN_CONTRACT" == "0" ]]; then contract_ok=1; fi

ok=1
if [[ "$failed" -ne 0 ]]; then
  ok=0
fi

cat <<EOF2
{"ok":${ok},"action":"verify_pack","doctor":${doctor_ok},"audit":${audit_ok},"contract":${contract_ok},"strict_doctor":${STRICT_DOCTOR}}
EOF2

if [[ "$ok" -ne 1 ]]; then
  exit 1
fi
