#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-}"
PROJECT_TYPE="${2:-}"
DOMAIN="${3:-}"
TYPE_MAP_SCRIPT="/var/www/aiir/server/scripts/project-type-map.sh"

if [[ -z "${PROJECT_NAME}" || -z "${PROJECT_TYPE}" ]]; then
  cat >&2 <<'EOF'
usage:
  /var/www/aiir/human/create-project-by-type.sh <project-name> <project-type> [domain]
EOF
  exit 1
fi

if [[ ! -f "${TYPE_MAP_SCRIPT}" ]]; then
  echo "missing type map script: ${TYPE_MAP_SCRIPT}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${TYPE_MAP_SCRIPT}"

DB_PROFILE=""
RETENTION_DAYS=""
REGION="${AIIR_DB_REGION:-local}"

if ! aiir_is_known_project_type "${PROJECT_TYPE}"; then
  echo "unknown project_type: ${PROJECT_TYPE}" >&2
  echo "see /var/www/aiir/human/PROJECT_TYPES_V1.md" >&2
  exit 1
fi

read -r DB_PROFILE RETENTION_DAYS < <(aiir_map_project_type "${PROJECT_TYPE}")

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
