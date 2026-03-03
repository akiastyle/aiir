#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
START_SCRIPT="${ROOT}/server/scripts/start-runtime.sh"
PROVISION_SCRIPT="${ROOT}/server/scripts/provision-project-domain.sh"
PID_FILE="${AIIR_RUNTIME_PID_FILE:-${ROOT}/ai/state/runtime.pid}"
OUT_LOG="${AIIR_RUNTIME_OUT_LOG:-${ROOT}/ai/log/runtime.out.log}"
ERR_LOG="${AIIR_RUNTIME_ERR_LOG:-${ROOT}/ai/log/runtime.err.log}"

PROJECT_NAME=""
PROJECT_DOMAIN=""
PROJECT_TYPE="webapp"
APPLY_WEB="0"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-up.sh [--project <name>] [--domain <domain>] [--type <project-type>] [--apply-web]

notes:
  - zero-conf bootstrap: starts runtime if not active
  - optional project provisioning with AI-managed defaults
  - if --apply-web is set, generated web conf may be applied to nginx/apache when supported
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
    --apply-web)
      APPLY_WEB="1"
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

map_type() {
  local t="$1"
  case "$t" in
    website|landing_page|cms_content_site|blog_magazine)
      echo "content 30" ;;
    ecommerce|marketplace)
      echo "commerce 180" ;;
    webapp|dashboard_admin)
      echo "app 90" ;;
    backend|api_service)
      echo "service 90" ;;
    frontend)
      echo "edge 30" ;;
    mobileapp|pwa_app)
      echo "mobile 60" ;;
    saas_multitenant)
      echo "saas 180" ;;
    booking_platform|lms_elearning)
      echo "app 120" ;;
    community_forum)
      echo "community 90" ;;
    automation_agentic)
      echo "agent 60" ;;
    *)
      echo "app 90" ;;
  esac
}

: "${AI_RUNTIME_HOST:=127.0.0.1}"
: "${AI_RUNTIME_PORT:=7788}"

mkdir -p "${ROOT}/ai/log" "${ROOT}/ai/state" "${ROOT}/server/generated" "${ROOT}/server/env/projects"

if ! curl -fsS "http://${AI_RUNTIME_HOST}:${AI_RUNTIME_PORT}/health" >/dev/null 2>&1; then
  nohup "$START_SCRIPT" >"$OUT_LOG" 2>"$ERR_LOG" &
  pid="$!"
  echo "$pid" > "$PID_FILE"

  ready=0
  for _ in $(seq 1 80); do
    if curl -fsS "http://${AI_RUNTIME_HOST}:${AI_RUNTIME_PORT}/health" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.2
  done
  if [[ "$ready" != "1" ]]; then
    echo "aiir-up-failed: runtime not ready" >&2
    exit 1
  fi
fi

if [[ -n "$PROJECT_NAME" ]]; then
  read -r db_profile retention_days < <(map_type "$PROJECT_TYPE")
  AIIR_DB_DEFAULT_PROFILE="$db_profile" \
  AIIR_DB_RETENTION_DAYS="$retention_days" \
  AIIR_PROVISION_APPLY="$APPLY_WEB" \
  "$PROVISION_SCRIPT" "$PROJECT_NAME" "$PROJECT_DOMAIN"
fi

cat <<EOF2
aiir-up-ok
runtime=http://${AI_RUNTIME_HOST}:${AI_RUNTIME_PORT}
pid_file=${PID_FILE}
chat_cli=/var/www/aiir/server/scripts/aiir-chat.sh
EOF2
