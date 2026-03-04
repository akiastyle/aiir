#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
PRESETS_DIR="${ROOT}/server/ui-presets"
PROJECTS_FILE="${AIIR_PROJECTS_FILE:-${ROOT}/ai/state/projects.ndjson}"
PROJECTS_LIB="${ROOT}/server/scripts/projects-ndjson-lib.sh"
LOCK_FILE="${AIIR_OPS_LOCK_FILE:-${ROOT}/ai/state/.ops.lock}"

IDENT="${1:-}"
PRESET_RAW="${2:-utility}"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-ui-scaffold.sh <project-ref|project-name> [utility|material|bootstrap-like]
USAGE
}

if [[ -z "$IDENT" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$PROJECTS_LIB" ]]; then
  echo '{"ok":0,"err":"projects_lib_missing"}'
  exit 1
fi
# shellcheck disable=SC1090
source "$PROJECTS_LIB"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  echo '{"ok":0,"err":"projects_file_missing"}'
  exit 1
fi

preset="$(printf '%s' "$PRESET_RAW" | tr '[:upper:]' '[:lower:]')"
case "$preset" in
  utility|material|bootstrap-like) ;;
  *)
    echo "{\"ok\":0,\"err\":\"preset\",\"hint\":\"utility|material|bootstrap-like\"}"
    exit 1 ;;
esac

if [[ "$IDENT" =~ ^prj_[A-Za-z0-9]+$ ]]; then
  line="$(aiir_project_line_latest "$PROJECTS_FILE" ref "$IDENT" || true)"
else
  line="$(aiir_project_line_latest "$PROJECTS_FILE" name "$IDENT" || true)"
fi

if [[ -z "$line" ]]; then
  printf '{"ok":0,"err":"project_not_found","input":"%s"}\n' "$IDENT"
  exit 1
fi

project_ref="$(aiir_json_get_str "$line" project_ref)"
project_name="$(aiir_json_get_str "$line" project_name)"

if [[ -z "$project_ref" ]]; then
  echo '{"ok":0,"err":"project_line_invalid"}'
  exit 1
fi

css_src="${PRESETS_DIR}/${preset}.css"
html_src="${PRESETS_DIR}/starter.html"
if [[ ! -f "$css_src" || ! -f "$html_src" ]]; then
  echo '{"ok":0,"err":"preset_assets_missing"}'
  exit 1
fi

ui_dir="${ROOT}/ai/state/projects/${project_ref}/ui"
ui_css="${ui_dir}/ui.css"
ui_html="${ui_dir}/index.html"
ui_meta="${ui_dir}/preset.json"

apply_ui() {
  mkdir -p "$ui_dir"
  cp "$css_src" "$ui_css"
  sed -e "s/{{TITLE}}/${project_name:-$project_ref}/g" -e "s/{{PRESET}}/${preset}/g" "$html_src" > "$ui_html"
  cat > "$ui_meta" <<META
{"project_ref":"${project_ref}","project_name":"${project_name}","preset":"${preset}","ui_css":"${ui_css}","ui_html":"${ui_html}"}
META
}

if command -v flock >/dev/null 2>&1; then
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  flock -x 9
  apply_ui
  flock -u 9
  exec 9>&-
else
  apply_ui
fi

cat <<EOF2
{"ok":1,"action":"ui_scaffold","project_ref":"${project_ref}","project_name":"${project_name}","preset":"${preset}","ui_dir":"${ui_dir}","ui_css":"${ui_css}","ui_html":"${ui_html}","next":"serve index.html via your web layer or import into human UI editor"}
EOF2
