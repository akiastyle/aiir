#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
PROVISION_SCRIPT="${ROOT}/server/scripts/provision-project-domain.sh"
OPTIMIZE_SCRIPT="${ROOT}/server/scripts/aiir-optimize-project.sh"
DOWN_SCRIPT="${ROOT}/server/scripts/aiir-down.sh"
TYPE_MAP_SCRIPT="${ROOT}/server/scripts/project-type-map.sh"

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

if [[ ! -f "$TYPE_MAP_SCRIPT" ]]; then
  echo "{\"ok\":0,\"err\":\"type_map_missing\",\"path\":\"${TYPE_MAP_SCRIPT}\"}"
  exit 1
fi
# shellcheck disable=SC1090
source "$TYPE_MAP_SCRIPT"

msg="$*"
shopt -s nocasematch

extract_project_field() {
  local line="$1"
  local field="$2"
  printf '%s' "$line" | sed -n "s/.*\"${field}\":\"\([^\"]*\)\".*/\1/p" | head -n1
}

find_project_line() {
  local ident="$1"
  if [[ ! -f "$AIIR_PROJECTS_FILE" ]]; then
    return 1
  fi
  if [[ "$ident" =~ ^prj_[a-z0-9]+$ ]]; then
    rg '"project_ref":"'"${ident}"'"' "$AIIR_PROJECTS_FILE" | tail -n 1
  else
    rg '"project_name":"'"${ident}"'"' "$AIIR_PROJECTS_FILE" | tail -n 1
  fi
}

list_projects_json() {
  if [[ ! -f "$AIIR_PROJECTS_FILE" ]]; then
    echo '{"ok":1,"count":0,"projects":[]}'
    return 0
  fi
  mapfile -t lines < <(
    awk '
      {
        if (match($0, /"project_ref":"[^"]+"/)) {
          ref=substr($0, RSTART+15, RLENGTH-16);
          row[ref]=$0;
        }
      }
      END {
        for (r in row) print row[r];
      }' "$AIIR_PROJECTS_FILE" | tail -n 20
  )
  printf '{"ok":1,"count":%d,"projects":[' "${#lines[@]}"
  idx=0
  for line in "${lines[@]}"; do
    ts="$(printf '%s' "$line" | sed -n 's/.*"ts":\([0-9][0-9]*\).*/\1/p' | head -n1)"
    project_ref="$(extract_project_field "$line" "project_ref")"
    db_ref="$(extract_project_field "$line" "db_ref")"
    project_name="$(extract_project_field "$line" "project_name")"
    db_profile="$(extract_project_field "$line" "db_profile")"
    region="$(extract_project_field "$line" "region")"
    if [[ "$idx" -gt 0 ]]; then printf ','; fi
    printf '{"ts":%s,"project_ref":"%s","db_ref":"%s","project_name":"%s","db_profile":"%s","region":"%s"}' \
      "${ts:-0}" "${project_ref}" "${db_ref}" "${project_name}" "${db_profile}" "${region}"
    idx=$((idx+1))
  done
  echo ']}'
}

# Safety gate for destructive intents.
if [[ "$msg" =~ (delete|elimina|destroy|drop|wipe|reset|formatta|ferma[[:space:]]+runtime|stop[[:space:]]+runtime) ]]; then
  if [[ ! "$msg" =~ (conferma|confirm) ]]; then
    echo '{"ok":0,"err":"confirmation_required","hint":"aggiungi conferma/confirm al comando"}'
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
    echo "{\"ok\":0,\"err\":\"project_not_found\",\"input\":\"${ident}\"}"
    exit 1
  fi
  project_ref="$(extract_project_field "$line" "project_ref")"
  db_ref="$(extract_project_field "$line" "db_ref")"
  project_name="$(extract_project_field "$line" "project_name")"
  db_profile="$(extract_project_field "$line" "db_profile")"
  region="$(extract_project_field "$line" "region")"
  retention_days="$(printf '%s' "$line" | sed -n 's/.*"retention_days":\([0-9][0-9]*\).*/\1/p' | head -n1)"
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
  echo '{"ok":0,"err":"intent","hint":"stato | lista progetti | stato progetto <id> | crea progetto <name> [tipo X] [dominio Y] | ottimizza progetto <id> | ferma runtime conferma"}'
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
