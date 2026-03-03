#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-}"
PROJECT_TYPE="${2:-}"
DOMAIN="${3:-}"

if [[ -z "${PROJECT_NAME}" || -z "${PROJECT_TYPE}" ]]; then
  cat >&2 <<'EOF'
usage:
  /var/www/aiir/human/create-project-by-type.sh <project-name> <project-type> [domain]
EOF
  exit 1
fi

DB_PROFILE=""
RETENTION_DAYS=""
REGION="${AIIR_DB_REGION:-local}"

case "${PROJECT_TYPE}" in
  website|landing_page|cms_content_site|blog_magazine)
    DB_PROFILE="content"; RETENTION_DAYS="30" ;;
  ecommerce|marketplace)
    DB_PROFILE="commerce"; RETENTION_DAYS="180" ;;
  webapp|dashboard_admin)
    DB_PROFILE="app"; RETENTION_DAYS="90" ;;
  backend|api_service)
    DB_PROFILE="service"; RETENTION_DAYS="90" ;;
  frontend)
    DB_PROFILE="edge"; RETENTION_DAYS="30" ;;
  mobileapp|pwa_app)
    DB_PROFILE="mobile"; RETENTION_DAYS="60" ;;
  saas_multitenant)
    DB_PROFILE="saas"; RETENTION_DAYS="180" ;;
  booking_platform|lms_elearning)
    DB_PROFILE="app"; RETENTION_DAYS="120" ;;
  community_forum)
    DB_PROFILE="community"; RETENTION_DAYS="90" ;;
  automation_agentic)
    DB_PROFILE="agent"; RETENTION_DAYS="60" ;;
  *)
    echo "unknown project_type: ${PROJECT_TYPE}" >&2
    echo "see /var/www/aiir/human/PROJECT_TYPES_V1.md" >&2
    exit 1 ;;
esac

echo "human-project-type-selected"
echo "project_name=${PROJECT_NAME}"
echo "project_type=${PROJECT_TYPE}"
echo "domain=${DOMAIN}"
echo "db_profile=${DB_PROFILE}"
echo "retention_days=${RETENTION_DAYS}"
echo "region=${REGION}"

AIIR_DB_DEFAULT_PROFILE="${DB_PROFILE}" \
AIIR_DB_RETENTION_DAYS="${RETENTION_DAYS}" \
AIIR_DB_REGION="${REGION}" \
/var/www/aiir/server/scripts/provision-project-domain.sh "${PROJECT_NAME}" "${DOMAIN}"
