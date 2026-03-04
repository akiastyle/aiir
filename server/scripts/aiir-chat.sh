#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
PROVISION_SCRIPT="${ROOT}/server/scripts/provision-project-domain.sh"
OPTIMIZE_SCRIPT="${ROOT}/server/scripts/aiir-optimize-project.sh"
DOWN_SCRIPT="${ROOT}/server/scripts/aiir-down.sh"
TYPE_MAP_SCRIPT="${ROOT}/server/scripts/project-type-map.sh"
PROJECTS_LIB="${ROOT}/server/scripts/projects-ndjson-lib.sh"

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
  aiir-chat.sh "lista progetti"
  aiir-chat.sh "stato progetto crm-alpha"
  aiir-chat.sh "ottimizza progetto crm-alpha"
  aiir-chat.sh "ferma runtime conferma"
USAGE
  exit 1
fi

json_err() {
  local code="$1"
  local hint="${2:-}"
  if [[ -n "$hint" ]]; then
    printf '{"ok":0,"err":"%s","hint":"%s"}\n' "$code" "$hint"
  else
    printf '{"ok":0,"err":"%s"}\n' "$code"
  fi
}

requires_confirmation() {
  local text="$1"
  local patterns=(
    'delete'
    'elimina'
    'destroy'
    'drop'
    'wipe'
    'reset'
    'formatta'
    'ferma[[:space:]]+runtime'
    'stop[[:space:]]+runtime'
  )
  local p
  for p in "${patterns[@]}"; do
    if [[ "$text" =~ $p ]]; then
      return 0
    fi
  done
  return 1
}

if [[ ! -f "$TYPE_MAP_SCRIPT" ]]; then
  json_err "type_map_missing" "$TYPE_MAP_SCRIPT"
  exit 1
fi
# shellcheck disable=SC1090
source "$TYPE_MAP_SCRIPT"
if [[ ! -f "$PROJECTS_LIB" ]]; then
  json_err "projects_lib_missing" "$PROJECTS_LIB"
  exit 1
fi
# shellcheck disable=SC1090
source "$PROJECTS_LIB"

msg="$*"
shopt -s nocasematch

find_project_line() {
  local ident="$1"
  if [[ ! -f "$AIIR_PROJECTS_FILE" ]]; then
    return 1
  fi
  if [[ "$ident" =~ ^prj_[a-z0-9]+$ ]]; then
    aiir_project_line_latest "$AIIR_PROJECTS_FILE" "ref" "$ident"
  else
    aiir_project_line_latest "$AIIR_PROJECTS_FILE" "name" "$ident"
  fi
}

list_projects_json() {
  if [[ ! -f "$AIIR_PROJECTS_FILE" ]]; then
    echo '{"ok":1,"count":0,"projects":[]}'
    return 0
  fi
  mapfile -t lines < <(aiir_project_lines_latest_unique "$AIIR_PROJECTS_FILE" 20)
  printf '{"ok":1,"count":%d,"projects":[' "${#lines[@]}"
  idx=0
  for line in "${lines[@]}"; do
    ts="$(aiir_json_get_num "$line" "ts")"
    project_ref="$(aiir_json_get_str "$line" "project_ref")"
    db_ref="$(aiir_json_get_str "$line" "db_ref")"
    project_name="$(aiir_json_get_str "$line" "project_name")"
    db_profile="$(aiir_json_get_str "$line" "db_profile")"
    region="$(aiir_json_get_str "$line" "region")"
    if [[ "$idx" -gt 0 ]]; then printf ','; fi
    printf '{"ts":%s,"project_ref":"%s","db_ref":"%s","project_name":"%s","db_profile":"%s","region":"%s"}' \
      "${ts:-0}" "${project_ref}" "${db_ref}" "${project_name}" "${db_profile}" "${region}"
    idx=$((idx+1))
  done
  echo ']}'
}

if [[ "$msg" =~ ^(help|aiuto)$ ]]; then
  cat <<'EOF'
{"ok":1,"intent":"help","commands":[{"name":"stato","example":"aiir chat \"stato\""},{"name":"lista_progetti","example":"aiir chat \"lista progetti\""},{"name":"stato_progetto","example":"aiir chat \"stato progetto crm-alpha\""},{"name":"crea_progetto","example":"aiir chat \"crea progetto crm-alpha tipo webapp dominio crm.local\""},{"name":"ottimizza_progetto","example":"aiir chat \"ottimizza progetto crm-alpha\""},{"name":"ferma_runtime","example":"aiir chat \"ferma runtime conferma\""}],"error_codes":["intent_unknown","confirmation_required","project_not_found","type_map_missing","projects_lib_missing"]}
EOF
  exit 0
fi

# Safety gate for destructive intents.
if requires_confirmation "$msg"; then
  if [[ ! "$msg" =~ (conferma|confirm) ]]; then
    json_err "confirmation_required" "aggiungi conferma/confirm al comando"
    exit 1
  fi
fi

if [[ "$msg" =~ ^(stato|status|health)$ ]]; then
  curl -fsS "http://${AI_RUNTIME_HOST}:${AI_RUNTIME_PORT}/health"
  exit 0
fi

if [[ "$msg" =~ ^(lista[[:space:]]+progetti|list[[:space:]]+projects|ultimi[[:space:]]+progetti|last[[:space:]]+projects)$ ]]; then
  list_projects_json
  exit 0
fi

if [[ "$msg" =~ ^(stato[[:space:]]+progetto|project[[:space:]]+status)[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]{1,95})$ ]]; then
  ident="${BASH_REMATCH[2]}"
  line="$(find_project_line "$ident" || true)"
  if [[ -z "$line" ]]; then
    printf '{"ok":0,"err":"project_not_found","input":"%s"}\n' "$ident"
    exit 1
  fi
  project_ref="$(aiir_json_get_str "$line" "project_ref")"
  db_ref="$(aiir_json_get_str "$line" "db_ref")"
  project_name="$(aiir_json_get_str "$line" "project_name")"
  db_profile="$(aiir_json_get_str "$line" "db_profile")"
  region="$(aiir_json_get_str "$line" "region")"
  retention_days="$(aiir_json_get_num "$line" "retention_days")"
  echo "{\"ok\":1,\"project_ref\":\"${project_ref}\",\"db_ref\":\"${db_ref}\",\"project_name\":\"${project_name}\",\"db_profile\":\"${db_profile}\",\"region\":\"${region}\",\"retention_days\":${retention_days:-0},\"status\":\"provisioning_or_ready\"}"
  exit 0
fi

if [[ "$msg" =~ ^(ottimizza[[:space:]]+progetto|optimize[[:space:]]+project)[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]{1,95})$ ]]; then
  ident="${BASH_REMATCH[2]}"
  "$OPTIMIZE_SCRIPT" "$ident"
  exit 0
fi

if [[ "$msg" =~ ^(ferma[[:space:]]+runtime|stop[[:space:]]+runtime)([[:space:]]+conferma|[[:space:]]+confirm)?$ ]]; then
  "$DOWN_SCRIPT" --host "$AI_RUNTIME_HOST" --port "$AI_RUNTIME_PORT"
  exit 0
fi

project=""
domain=""
type="webapp"

if [[ "$msg" =~ ^(crea[[:space:]]+progetto|create[[:space:]]+project)[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]{1,63}) ]]; then
  project="${BASH_REMATCH[2]}"
else
  json_err "intent_unknown" "stato | lista progetti | stato progetto <id> | crea progetto <name> [tipo X] [dominio Y] | ottimizza progetto <id> | ferma runtime conferma"
  exit 1
fi

if [[ "$msg" =~ (dominio|domain)[[:space:]]*[:=]?[[:space:]]*([A-Za-z0-9.-]+) ]]; then
  domain="${BASH_REMATCH[2]}"
fi
if [[ "$msg" =~ (tipo|type)[[:space:]]*[:=]?[[:space:]]*([A-Za-z_]+) ]]; then
  type="${BASH_REMATCH[2]}"
fi

read -r db_profile retention_days < <(aiir_map_project_type "$type")

AIIR_DB_DEFAULT_PROFILE="$db_profile" \
AIIR_DB_RETENTION_DAYS="$retention_days" \
"$PROVISION_SCRIPT" "$project" "$domain"
