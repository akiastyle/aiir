#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
UP_SCRIPT="${ROOT}/server/scripts/aiir-up.sh"
DOCTOR_SCRIPT="${ROOT}/server/scripts/aiir-doctor.sh"
AUDIT_SCRIPT="${ROOT}/server/scripts/aiir-self-audit.sh"

PROJECT_NAME=""
PROJECT_DOMAIN=""
PROJECT_TYPE="webapp"
APPLY_WEB="1"
RUN_DOCTOR="1"
RUN_AUDIT="1"
DRY_RUN="0"
FALLBACK_NO_APPLY="0"
STRICT_WEB_APPLY="0"
FALLBACK_REASON=""

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-deploy.sh --project <name> [--domain <domain>] [--type <project-type>] [--no-apply-web] [--strict-web-apply] [--no-doctor] [--no-audit] [--dry-run]

notes:
  - starts runtime if needed
  - provisions project/db/policy/env
  - applies webserver conf when possible (default on, can disable with --no-apply-web)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_NAME="${2:-}"
      shift 2 ;;
    --domain)
      PROJECT_DOMAIN="${2:-}"
      shift 2 ;;
    --type)
      PROJECT_TYPE="${2:-}"
      shift 2 ;;
    --no-apply-web)
      APPLY_WEB="0"
      shift ;;
    --strict-web-apply)
      STRICT_WEB_APPLY="1"
      shift ;;
    --no-doctor)
      RUN_DOCTOR="0"
      shift ;;
    --no-audit)
      RUN_AUDIT="0"
      shift ;;
    --dry-run)
      DRY_RUN="1"
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

if [[ -z "$PROJECT_NAME" ]]; then
  echo '{"ok":0,"err":"project_required"}'
  usage
  exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  cat <<EOF2
{"ok":1,"action":"deploy_project","dry_run":1,"project_name":"${PROJECT_NAME}","project_domain":"${PROJECT_DOMAIN}","project_type":"${PROJECT_TYPE}","apply_web":${APPLY_WEB},"apply_web_strict":${STRICT_WEB_APPLY},"run_doctor":${RUN_DOCTOR},"run_audit":${RUN_AUDIT}}
EOF2
  exit 0
fi

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

up_args=(--project "$PROJECT_NAME" --type "$PROJECT_TYPE")
if [[ -n "$PROJECT_DOMAIN" ]]; then
  up_args+=(--domain "$PROJECT_DOMAIN")
fi
run_up() {
  local apply="$1"
  local -a args=("${up_args[@]}")
  if [[ "$apply" == "1" ]]; then
    args+=(--apply-web)
  fi
  "$UP_SCRIPT" "${args[@]}"
}

if ! run_up "$APPLY_WEB" >"${TMPDIR}/up.txt" 2>"${TMPDIR}/up.err"; then
  if [[ "$APPLY_WEB" == "1" ]]; then
    if [[ "$STRICT_WEB_APPLY" == "1" ]]; then
      cat "${TMPDIR}/up.err" >&2 || true
      exit 1
    fi
    FALLBACK_NO_APPLY="1"
    APPLY_WEB="0"
    FALLBACK_REASON="$(tr '\n' ' ' < "${TMPDIR}/up.err" | sed 's/  */ /g' | sed 's/"/'\''/g' | cut -c1-240)"
    run_up "0" >"${TMPDIR}/up.txt" 2>"${TMPDIR}/up.err"
  else
    cat "${TMPDIR}/up.err" >&2 || true
    exit 1
  fi
fi

project_ref="$(sed -n 's/^project_ref=//p' "${TMPDIR}/up.txt" | head -n1)"
db_ref="$(sed -n 's/^db_ref=//p' "${TMPDIR}/up.txt" | head -n1)"
status="$(sed -n 's/^status=//p' "${TMPDIR}/up.txt" | head -n1)"
project_env="$(sed -n 's/^project_env=//p' "${TMPDIR}/up.txt" | head -n1)"
project_policy="$(sed -n 's/^project_policy=//p' "${TMPDIR}/up.txt" | head -n1)"
webserver="$(sed -n 's/^webserver=//p' "${TMPDIR}/up.txt" | head -n1)"
web_conf="$(sed -n 's/^web_conf=//p' "${TMPDIR}/up.txt" | head -n1)"
runtime="$(sed -n 's/^runtime=//p' "${TMPDIR}/up.txt" | head -n1)"

if [[ "$RUN_AUDIT" == "1" ]]; then
  "$AUDIT_SCRIPT" >"${TMPDIR}/audit.json"
fi
if [[ "$RUN_DOCTOR" == "1" ]]; then
  "$DOCTOR_SCRIPT" --strict >"${TMPDIR}/doctor.txt"
fi

cat <<EOF2
{"ok":1,"action":"deploy_project","project_name":"${PROJECT_NAME}","project_type":"${PROJECT_TYPE}","project_domain":"${PROJECT_DOMAIN}","project_ref":"${project_ref}","db_ref":"${db_ref}","status":"${status}","runtime":"${runtime}","project_env":"${project_env}","project_policy":"${project_policy}","webserver":"${webserver}","web_conf":"${web_conf}","apply_web":${APPLY_WEB},"apply_web_strict":${STRICT_WEB_APPLY},"apply_web_fallback":${FALLBACK_NO_APPLY},"fallback_reason":"${FALLBACK_REASON}","doctor":${RUN_DOCTOR},"audit":${RUN_AUDIT}}
EOF2
