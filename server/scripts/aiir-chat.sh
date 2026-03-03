#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
PROVISION_SCRIPT="${ROOT}/server/scripts/provision-project-domain.sh"

: "${AI_RUNTIME_HOST:=127.0.0.1}"
: "${AI_RUNTIME_PORT:=7788}"
: "${AIIR_PROJECTS_FILE:=/var/www/aiir/ai/state/projects.ndjson}"

if [[ $# -lt 1 ]]; then
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-chat.sh "<message>"

examples:
  aiir-chat.sh "stato"
  aiir-chat.sh "crea progetto crm-alpha tipo webapp dominio crm.local"
  aiir-chat.sh "create project shop-one type ecommerce domain shop.local"
USAGE
  exit 1
fi

msg="$*"
lower="$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')"

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

if [[ "$lower" =~ ^(stato|status|health)$ ]]; then
  curl -fsS "http://${AI_RUNTIME_HOST}:${AI_RUNTIME_PORT}/health"
  exit 0
fi

if [[ "$lower" =~ ^(ultimi[[:space:]]+progetti|last[[:space:]]+projects)$ ]]; then
  if [[ ! -f "$AIIR_PROJECTS_FILE" ]]; then
    echo '{"ok":1,"projects":[]}'
    exit 0
  fi
  tail -n 10 "$AIIR_PROJECTS_FILE"
  exit 0
fi

project=""
domain=""
type="webapp"

if [[ "$lower" =~ ^(crea[[:space:]]+progetto|create[[:space:]]+project)[[:space:]]+([a-z0-9][a-z0-9._-]{1,63}) ]]; then
  project="${BASH_REMATCH[2]}"
else
  echo '{"ok":0,"err":"intent","hint":"use: crea progetto <name> [tipo X] [dominio Y]"}'
  exit 1
fi

if [[ "$lower" =~ (dominio|domain)[[:space:]]*[:=]?[[:space:]]*([a-z0-9.-]+) ]]; then
  domain="${BASH_REMATCH[2]}"
fi
if [[ "$lower" =~ (tipo|type)[[:space:]]*[:=]?[[:space:]]*([a-z_]+) ]]; then
  type="${BASH_REMATCH[2]}"
fi

read -r db_profile retention_days < <(map_type "$type")

AIIR_DB_DEFAULT_PROFILE="$db_profile" \
AIIR_DB_RETENTION_DAYS="$retention_days" \
"$PROVISION_SCRIPT" "$project" "$domain"
