#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
PROJECTS_FILE="${AIIR_PROJECTS_FILE:-${ROOT}/ai/state/projects.ndjson}"
ENV_DIR="${ROOT}/server/env/projects"
POLICY_BASE="${ROOT}/ai/state/projects"
IDENT="${1:-}"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-optimize-project.sh <project-ref|project-name>
USAGE
}

if [[ -z "$IDENT" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$PROJECTS_FILE" ]]; then
  echo "{\"ok\":0,\"err\":\"projects_file\"}"
  exit 1
fi

line=""
if [[ "$IDENT" =~ ^prj_[a-z0-9]+$ ]]; then
  line="$(rg '"project_ref":"'"${IDENT}"'"' "$PROJECTS_FILE" | tail -n 1 || true)"
else
  line="$(rg '"project_name":"'"${IDENT}"'"' "$PROJECTS_FILE" | tail -n 1 || true)"
fi

if [[ -z "$line" ]]; then
  echo "{\"ok\":0,\"err\":\"project_not_found\",\"input\":\"${IDENT}\"}"
  exit 1
fi

project_ref="$(printf '%s' "$line" | sed -n 's/.*"project_ref":"\([^"]*\)".*/\1/p' | head -n1)"
db_ref="$(printf '%s' "$line" | sed -n 's/.*"db_ref":"\([^"]*\)".*/\1/p' | head -n1)"
project_name="$(printf '%s' "$line" | sed -n 's/.*"project_name":"\([^"]*\)".*/\1/p' | head -n1)"
db_profile="$(printf '%s' "$line" | sed -n 's/.*"db_profile":"\([^"]*\)".*/\1/p' | head -n1)"
region="$(printf '%s' "$line" | sed -n 's/.*"region":"\([^"]*\)".*/\1/p' | head -n1)"
retention_days="$(printf '%s' "$line" | sed -n 's/.*"retention_days":\([0-9][0-9]*\).*/\1/p' | head -n1)"

if [[ -z "$project_ref" || -z "$db_ref" ]]; then
  echo "{\"ok\":0,\"err\":\"project_line_invalid\"}"
  exit 1
fi

mkdir -p "$ENV_DIR" "${POLICY_BASE}/${project_ref}"
env_file="${ENV_DIR}/${project_ref}.env"
policy_file="${POLICY_BASE}/${project_ref}/policy.env"

if [[ ! -f "$env_file" ]]; then
  cat > "$env_file" <<ENV
PROJECT_NAME=${project_name}
PROJECT_REF=${project_ref}
DB_REF=${db_ref}
PROJECT_DOMAIN=
AIIR_HUMAN_DB_MODE=indirect
AIIR_DB_ALLOW_DIRECT_CREDENTIALS=0
AI_POLICY_ALLOW_DB_EXEC=0
AI_POLICY_ALLOW_OPS=
AI_CAP_REQUIRE=1
AI_LOG_REQUESTS=1
AIIR_DB_DEFAULT_PROFILE=${db_profile:-default}
AIIR_DB_REGION=${region:-local}
AIIR_DB_RETENTION_DAYS=${retention_days:-30}
ENV
fi

if [[ ! -f "$policy_file" ]]; then
  cat > "$policy_file" <<POL
PROJECT_REF=${project_ref}
DB_REF=${db_ref}
AIIR_POLICY_MODE=deny-by-default
AI_POLICY_ALLOW_DB_EXEC=0
AI_POLICY_ALLOW_OPS=
AI_CAP_REQUIRE=1
AIIR_DB_REQUIRE_CAPABILITY=1
AIIR_DB_ALLOW_DIRECT_CREDENTIALS=0
AIIR_HUMAN_DB_MODE=indirect
POL
fi

upsert_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  if rg -q "^${key}=" "$file"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

upsert_kv "$env_file" "PROJECT_NAME" "${project_name}"
upsert_kv "$env_file" "PROJECT_REF" "${project_ref}"
upsert_kv "$env_file" "DB_REF" "${db_ref}"
upsert_kv "$env_file" "AIIR_HUMAN_DB_MODE" "indirect"
upsert_kv "$env_file" "AIIR_DB_ALLOW_DIRECT_CREDENTIALS" "0"
upsert_kv "$env_file" "AI_POLICY_ALLOW_DB_EXEC" "0"
upsert_kv "$env_file" "AI_POLICY_ALLOW_OPS" ""
upsert_kv "$env_file" "AI_CAP_REQUIRE" "1"
upsert_kv "$env_file" "AI_LOG_REQUESTS" "1"
upsert_kv "$env_file" "AIIR_DB_DEFAULT_PROFILE" "${db_profile:-default}"
upsert_kv "$env_file" "AIIR_DB_REGION" "${region:-local}"
upsert_kv "$env_file" "AIIR_DB_RETENTION_DAYS" "${retention_days:-30}"

upsert_kv "$policy_file" "PROJECT_REF" "${project_ref}"
upsert_kv "$policy_file" "DB_REF" "${db_ref}"
upsert_kv "$policy_file" "AIIR_POLICY_MODE" "deny-by-default"
upsert_kv "$policy_file" "AI_POLICY_ALLOW_DB_EXEC" "0"
upsert_kv "$policy_file" "AI_POLICY_ALLOW_OPS" ""
upsert_kv "$policy_file" "AI_CAP_REQUIRE" "1"
upsert_kv "$policy_file" "AIIR_DB_REQUIRE_CAPABILITY" "1"
upsert_kv "$policy_file" "AIIR_DB_ALLOW_DIRECT_CREDENTIALS" "0"
upsert_kv "$policy_file" "AIIR_HUMAN_DB_MODE" "indirect"

cat <<EOF2
{"ok":1,"action":"optimize_project","project_ref":"${project_ref}","db_ref":"${db_ref}","project_name":"${project_name}","env_file":"${env_file}","policy_file":"${policy_file}","applied":{"deny_by_default":1,"capability_required":1,"human_indirect":1,"direct_credentials":0}}
EOF2
