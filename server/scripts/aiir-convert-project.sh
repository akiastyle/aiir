#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
BUILD_SCRIPT="${ROOT}/ai/exchange/build-package.run.sh"
OAIIR_REGISTRY="${ROOT}/docs/OAIIR_WEB_OPCODE_REGISTRY_V0.csv"
OAIIR_HTML_CATALOG="${ROOT}/docs/OAIIR_WEB_HTML_CATALOG_V0.csv"
OAIIR_CSS_CATALOG="${ROOT}/docs/OAIIR_WEB_CSS_CATALOG_V0.csv"
OAIIR_JS_CATALOG="${ROOT}/docs/OAIIR_WEB_JS_CATALOG_V0.csv"

SRC_DIR="${1:-}"
OUT_DIR="${2:-}"
PROJECT_ID_RAW="${3:-}"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-convert-project.sh <source-dir> <out-dir> [project-id]
USAGE
}

if [[ -z "$SRC_DIR" || -z "$OUT_DIR" ]]; then
  usage
  exit 1
fi
if [[ ! -d "$SRC_DIR" ]]; then
  echo '{"ok":0,"err":"source_dir"}'
  exit 1
fi
if [[ ! -f "$OAIIR_REGISTRY" ]]; then
  echo '{"ok":0,"err":"oaiir_registry"}'
  exit 1
fi
if [[ ! -f "$OAIIR_HTML_CATALOG" ]]; then
  echo '{"ok":0,"err":"oaiir_html_catalog"}'
  exit 1
fi
if [[ ! -f "$OAIIR_CSS_CATALOG" ]]; then
  echo '{"ok":0,"err":"oaiir_css_catalog"}'
  exit 1
fi
if [[ ! -f "$OAIIR_JS_CATALOG" ]]; then
  echo '{"ok":0,"err":"oaiir_js_catalog"}'
  exit 1
fi

project_id="$PROJECT_ID_RAW"
if [[ -z "$project_id" ]]; then
  project_id="$(basename "$SRC_DIR" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')"
  project_id="${project_id#-}"
  project_id="${project_id%-}"
  [[ -n "$project_id" ]] || project_id="project"
fi

PKG_DIR="${OUT_DIR}/package"
NORM_DIR="${OUT_DIR}/normalized-web"
REPORT_DIR="${OUT_DIR}/reports"
CMD_FILE="${REPORT_DIR}/project-commands.aiir.json"
MAP_FILE="${REPORT_DIR}/conversion-map.csv"
REPORT_FILE="${REPORT_DIR}/migration-report.json"
OAIIR_FILE="${REPORT_DIR}/oaiir-opcodes.csv"
OAIIR_HTML_IR_FILE="${REPORT_DIR}/oaiir-html-ir.ndjson"
OAIIR_CSS_IR_FILE="${REPORT_DIR}/oaiir-css-ir.ndjson"
OAIIR_JS_IR_FILE="${REPORT_DIR}/oaiir-js-ir.ndjson"
OAIIR_HTML_MAX_FILES="${OAIIR_HTML_MAX_FILES:-120}"
OAIIR_CSS_MAX_FILES="${OAIIR_CSS_MAX_FILES:-120}"
OAIIR_JS_MAX_FILES="${OAIIR_JS_MAX_FILES:-120}"
OAIIR_HTML_TOKENS_PER_FILE="${OAIIR_HTML_TOKENS_PER_FILE:-2000}"
OAIIR_CSS_LINES_PER_FILE="${OAIIR_CSS_LINES_PER_FILE:-1500}"
OAIIR_JS_LINES_PER_FILE="${OAIIR_JS_LINES_PER_FILE:-1500}"

mkdir -p "$PKG_DIR" "$NORM_DIR" "$REPORT_DIR"

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Build AIIR package via native command path.
if ! "$BUILD_SCRIPT" "$SRC_DIR" "$PKG_DIR" >"${TMPDIR}/build.log" 2>&1; then
  echo '{"ok":0,"err":"build_package_failed"}'
  cat "${TMPDIR}/build.log" >&2 || true
  exit 1
fi

# Collect source files.
all_files_tmp="${TMPDIR}/all-files.txt"
rg --files -uu "$SRC_DIR" > "$all_files_tmp"

# Normalize/copy web-relevant files preserving relative paths.
web_files_tmp="${TMPDIR}/web-files.txt"
: > "$web_files_tmp"
while IFS= read -r f; do
  case "$f" in
    *.html|*.htm|*.css|*.scss|*.js|*.jsx|*.ts|*.tsx)
      echo "$f" >> "$web_files_tmp" ;;
  esac
done < "$all_files_tmp"

# Copy web files.
while IFS= read -r abs; do
  [[ -z "$abs" ]] && continue
  rel="${abs#$SRC_DIR/}"
  dst="${NORM_DIR}/${rel}"
  mkdir -p "$(dirname "$dst")"
  cp "$abs" "$dst"
done < "$web_files_tmp"

# Build conversion map and native/custom counters.
echo 'source_rel,target_rel,mode' > "$MAP_FILE"
web_count=0
native_count=0
custom_count=0
while IFS= read -r abs; do
  [[ -z "$abs" ]] && continue
  rel="${abs#$SRC_DIR/}"
  mode="native"
  native_count=$((native_count+1))
  web_count=$((web_count+1))
  printf '%s,%s,%s\n' "$rel" "$rel" "$mode" >> "$MAP_FILE"
done < "$web_files_tmp"

# Base + custom command model for project.
base_cmds=(
  "page.render.static"
  "style.apply.theme"
  "script.exec.basic"
  "route.bind"
  "data.read"
  "data.write"
)
custom_cmds=()
# Single-pass detection to reduce repeated scans on very large repositories.
eval "$(
  awk '
    BEGIN {
      sql=0; mig=0; py=0; go=0; js=0; spa=0; ctr=0;
    }
    {
      l=tolower($0);
      if (l ~ /\.sql$/) sql=1;
      if (l ~ /\/migrations?\// || l ~ /\/migration\//) mig=1;
      if (l ~ /\.py$/) py=1;
      if (l ~ /\.go$/) go=1;
      if (l ~ /\.(js|ts)$/) js=1;
      if (l ~ /vite\.config/ || l ~ /webpack\.config/ || l ~ /next\.config/ || l ~ /angular\.json/ || l ~ /nuxt\.config/ || l ~ /svelte\.config/) spa=1;
      if (l ~ /dockerfile/ || l ~ /docker-compose/ || l ~ /compose\.ya?ml/) ctr=1;
    }
    END {
      printf "HAS_SQL=%d\n", sql;
      printf "HAS_MIG=%d\n", mig;
      printf "HAS_PY=%d\n", py;
      printf "HAS_GO=%d\n", go;
      printf "HAS_JS=%d\n", js;
      printf "HAS_SPA=%d\n", spa;
      printf "HAS_CTR=%d\n", ctr;
    }
  ' "$all_files_tmp"
)"
if [[ "${HAS_SQL:-0}" == "1" ]]; then custom_cmds+=("project.db.sql.exec"); fi
if [[ "${HAS_MIG:-0}" == "1" ]]; then custom_cmds+=("project.db.migrate"); fi
if [[ "${HAS_PY:-0}" == "1" ]]; then custom_cmds+=("project.api.python.handle"); fi
if [[ "${HAS_GO:-0}" == "1" ]]; then custom_cmds+=("project.api.go.handle"); fi
if [[ "${HAS_JS:-0}" == "1" ]]; then custom_cmds+=("project.api.js.handle"); fi
if [[ "${HAS_SPA:-0}" == "1" ]]; then custom_cmds+=("project.web.bundle.spa"); fi
if [[ "${HAS_CTR:-0}" == "1" ]]; then custom_cmds+=("project.ops.container"); fi

# Unique custom commands.
custom_unique_tmp="${TMPDIR}/custom-unique.txt"
printf '%s\n' "${custom_cmds[@]:-}" | awk 'NF && !seen[$0]++' > "$custom_unique_tmp"
custom_unique_count="$(awk 'NF{c++} END{print c+0}' "$custom_unique_tmp")"
base_count="${#base_cmds[@]}"
paiir_total=$((base_count + custom_unique_count))
all_primitives_tmp="${TMPDIR}/all-primitives.txt"
{
  printf '%s\n' "${base_cmds[@]}"
  cat "$custom_unique_tmp"
} | awk 'NF && !seen[$0]++' > "$all_primitives_tmp"

echo 'primitive,opcode,status,scope' > "$OAIIR_FILE"
oaiir_total=0
oaiir_new_total=0
oaiir_dynamic_next=900000
# Load opcode registry once (primitive -> opcode/status) to avoid per-row awk scans.
declare -A oaiir_opcode_map=()
declare -A oaiir_status_map=()
while IFS=, read -r primitive opcode status _rest; do
  [[ -z "${primitive:-}" ]] && continue
  [[ "$primitive" == "primitive" ]] && continue
  oaiir_opcode_map["$primitive"]="$opcode"
  oaiir_status_map["$primitive"]="$status"
done < "$OAIIR_REGISTRY"

while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  opcode="${oaiir_opcode_map[$p]:-}"
  status="${oaiir_status_map[$p]:-}"
  if [[ -z "$opcode" ]]; then
    opcode="$oaiir_dynamic_next"
    oaiir_dynamic_next=$((oaiir_dynamic_next+1))
    status="project_dynamic"
    oaiir_new_total=$((oaiir_new_total+1))
  fi
  scope="base"
  if [[ "$p" == project.* ]]; then
    scope="custom"
  fi
  printf '%s,%s,%s,%s\n' "$p" "$opcode" "$status" "$scope" >> "$OAIIR_FILE"
  oaiir_total=$((oaiir_total+1))
done < "$all_primitives_tmp"

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

oaiir_html_ops_total=0
: > "$OAIIR_HTML_IR_FILE"
while IFS= read -r html_abs; do
  [[ -z "$html_abs" ]] && continue
  rel="${html_abs#$NORM_DIR/}"
  seq=0
  rel_json="$(json_escape "$rel")"
  printf '{"op":3000,"name":"file.begin","file":"%s","seq":%d}\n' "$rel_json" "$seq" >> "$OAIIR_HTML_IR_FILE"
  seq=$((seq+1))
  oaiir_html_ops_total=$((oaiir_html_ops_total+1))

  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    if [[ "$token" == \<\!* || "$token" == \<\?* ]]; then
      continue
    fi
    if [[ "$token" == \<* ]]; then
      if [[ "$token" == \</* ]]; then
        tag="$(printf '%s' "$token" | sed -n 's#^</\([a-zA-Z0-9:_-][a-zA-Z0-9:_-]*\)[^>]*>$#\1#p' | tr '[:upper:]' '[:lower:]')"
        [[ -n "$tag" ]] || continue
        tag_json="$(json_escape "$tag")"
        printf '{"op":3004,"name":"node.close","file":"%s","seq":%d,"tag":"%s"}\n' "$rel_json" "$seq" "$tag_json" >> "$OAIIR_HTML_IR_FILE"
        seq=$((seq+1))
        oaiir_html_ops_total=$((oaiir_html_ops_total+1))
        continue
      fi

      tag="$(printf '%s' "$token" | sed -n 's#^<\([a-zA-Z0-9:_-][a-zA-Z0-9:_-]*\).*#\1#p' | tr '[:upper:]' '[:lower:]')"
      [[ -n "$tag" ]] || continue
      tag_json="$(json_escape "$tag")"
      printf '{"op":3001,"name":"node.open","file":"%s","seq":%d,"tag":"%s"}\n' "$rel_json" "$seq" "$tag_json" >> "$OAIIR_HTML_IR_FILE"
      seq=$((seq+1))
      oaiir_html_ops_total=$((oaiir_html_ops_total+1))

      while IFS= read -r attr; do
        [[ -z "$attr" ]] && continue
        lower_attr="$(printf '%s' "$attr" | tr '[:upper:]' '[:lower:]')"
        attr_json="$(json_escape "$lower_attr")"
        printf '{"op":3002,"name":"attr.set","file":"%s","seq":%d,"tag":"%s","attr":"%s"}\n' "$rel_json" "$seq" "$tag_json" "$attr_json" >> "$OAIIR_HTML_IR_FILE"
        seq=$((seq+1))
        oaiir_html_ops_total=$((oaiir_html_ops_total+1))
      done < <(printf '%s' "$token" | grep -oE '[A-Za-z_:][-A-Za-z0-9_:.-]*=' | sed 's/=$//' | sort -u)
      continue
    fi

    text="$(printf '%s' "$token" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
    [[ -n "$text" ]] || continue
    text_json="$(json_escape "$text")"
    printf '{"op":3003,"name":"text.set","file":"%s","seq":%d,"text":"%s"}\n' "$rel_json" "$seq" "$text_json" >> "$OAIIR_HTML_IR_FILE"
    seq=$((seq+1))
    oaiir_html_ops_total=$((oaiir_html_ops_total+1))
  done < <(grep -oE '<[^>]+>|[^<]+' "$html_abs" | head -n "$OAIIR_HTML_TOKENS_PER_FILE" || true)
done < <(rg --files -uu "$NORM_DIR" -g '*.html' -g '*.htm' 2>/dev/null | sort | head -n "$OAIIR_HTML_MAX_FILES")

oaiir_css_ops_total=0
: > "$OAIIR_CSS_IR_FILE"
while IFS= read -r css_abs; do
  [[ -z "$css_abs" ]] && continue
  rel="${css_abs#$NORM_DIR/}"
  rel_json="$(json_escape "$rel")"
  seq=0
  printf '{"op":3200,"name":"style.file.begin","file":"%s","seq":%d}\n' "$rel_json" "$seq" >> "$OAIIR_CSS_IR_FILE"
  seq=$((seq+1))
  oaiir_css_ops_total=$((oaiir_css_ops_total+1))

  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == "/*"* ]] && continue
    if [[ "$trimmed" == @* ]]; then
      at_json="$(json_escape "$trimmed")"
      printf '{"op":3203,"name":"atrule","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$at_json" >> "$OAIIR_CSS_IR_FILE"
      seq=$((seq+1))
      oaiir_css_ops_total=$((oaiir_css_ops_total+1))
      continue
    fi
    if [[ "$trimmed" == *"{"* ]]; then
      selector="$(printf '%s' "$trimmed" | sed 's/{.*$//' | sed 's/[[:space:]]*$//')"
      [[ -n "$selector" ]] || continue
      sel_json="$(json_escape "$selector")"
      printf '{"op":3201,"name":"selector.open","file":"%s","seq":%d,"selector":"%s"}\n' "$rel_json" "$seq" "$sel_json" >> "$OAIIR_CSS_IR_FILE"
      seq=$((seq+1))
      oaiir_css_ops_total=$((oaiir_css_ops_total+1))
      continue
    fi
    if [[ "$trimmed" == *:* ]]; then
      prop="$(printf '%s' "$trimmed" | sed 's/:.*$//' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]*$//')"
      value="$(printf '%s' "$trimmed" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/;[[:space:]]*$//')"
      [[ -n "$prop" ]] || continue
      prop_json="$(json_escape "$prop")"
      value_json="$(json_escape "$value")"
      printf '{"op":3202,"name":"decl.set","file":"%s","seq":%d,"prop":"%s","value":"%s"}\n' "$rel_json" "$seq" "$prop_json" "$value_json" >> "$OAIIR_CSS_IR_FILE"
      seq=$((seq+1))
      oaiir_css_ops_total=$((oaiir_css_ops_total+1))
      continue
    fi
  done < <(head -n "$OAIIR_CSS_LINES_PER_FILE" "$css_abs")
done < <(rg --files -uu "$NORM_DIR" -g '*.css' -g '*.scss' 2>/dev/null | sort | head -n "$OAIIR_CSS_MAX_FILES")

oaiir_js_ops_total=0
: > "$OAIIR_JS_IR_FILE"
while IFS= read -r js_abs; do
  [[ -z "$js_abs" ]] && continue
  rel="${js_abs#$NORM_DIR/}"
  rel_json="$(json_escape "$rel")"
  seq=0
  printf '{"op":3300,"name":"script.file.begin","file":"%s","seq":%d}\n' "$rel_json" "$seq" >> "$OAIIR_JS_IR_FILE"
  seq=$((seq+1))
  oaiir_js_ops_total=$((oaiir_js_ops_total+1))

  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == "//"* ]] && continue

    if [[ "$trimmed" == import* ]]; then
      v="$(json_escape "$trimmed")"
      printf '{"op":3301,"name":"import.decl","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$v" >> "$OAIIR_JS_IR_FILE"
      seq=$((seq+1)); oaiir_js_ops_total=$((oaiir_js_ops_total+1)); continue
    fi
    if [[ "$trimmed" == export* ]]; then
      v="$(json_escape "$trimmed")"
      printf '{"op":3302,"name":"export.decl","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$v" >> "$OAIIR_JS_IR_FILE"
      seq=$((seq+1)); oaiir_js_ops_total=$((oaiir_js_ops_total+1)); continue
    fi
    if [[ "$trimmed" == function* || "$trimmed" == *" function "* ]]; then
      v="$(json_escape "$trimmed")"
      printf '{"op":3303,"name":"fn.decl","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$v" >> "$OAIIR_JS_IR_FILE"
      seq=$((seq+1)); oaiir_js_ops_total=$((oaiir_js_ops_total+1)); continue
    fi
    if [[ "$trimmed" == class* ]]; then
      v="$(json_escape "$trimmed")"
      printf '{"op":3304,"name":"class.decl","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$v" >> "$OAIIR_JS_IR_FILE"
      seq=$((seq+1)); oaiir_js_ops_total=$((oaiir_js_ops_total+1)); continue
    fi
    if [[ "$trimmed" == const* || "$trimmed" == let* || "$trimmed" == var* ]]; then
      v="$(json_escape "$trimmed")"
      printf '{"op":3305,"name":"var.decl","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$v" >> "$OAIIR_JS_IR_FILE"
      seq=$((seq+1)); oaiir_js_ops_total=$((oaiir_js_ops_total+1)); continue
    fi
    if [[ "$trimmed" == *"addEventListener("* ]]; then
      v="$(json_escape "$trimmed")"
      printf '{"op":3307,"name":"event.bind","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$v" >> "$OAIIR_JS_IR_FILE"
      seq=$((seq+1)); oaiir_js_ops_total=$((oaiir_js_ops_total+1)); continue
    fi
    if [[ "$trimmed" == *"("*")"* && "$trimmed" != "if ("* && "$trimmed" != "for ("* && "$trimmed" != "while ("* && "$trimmed" != "switch ("* ]]; then
      v="$(json_escape "$trimmed")"
      printf '{"op":3306,"name":"call.expr","file":"%s","seq":%d,"value":"%s"}\n' "$rel_json" "$seq" "$v" >> "$OAIIR_JS_IR_FILE"
      seq=$((seq+1)); oaiir_js_ops_total=$((oaiir_js_ops_total+1)); continue
    fi
  done < <(head -n "$OAIIR_JS_LINES_PER_FILE" "$js_abs")
done < <(rg --files -uu "$NORM_DIR" -g '*.js' -g '*.jsx' -g '*.ts' -g '*.tsx' 2>/dev/null | sort | head -n "$OAIIR_JS_MAX_FILES")

pkg_bytes="$(du -sb "$PKG_DIR" | awk '{print $1}')"
pkg_mb="$(awk -v b="$pkg_bytes" 'BEGIN {printf "%.2f", b/1048576}')"
source_bytes="$(du -sb "$SRC_DIR" | awk '{print $1}')"
source_mb="$(awk -v b="$source_bytes" 'BEGIN {printf "%.2f", b/1048576}')"
reuse_pct="$(awk -v n="$native_count" -v t="$web_count" 'BEGIN {if (t<=0) printf "100.00"; else printf "%.2f", (n/t)*100}')"

{
  echo '{'
  printf '  "project_id":"%s",\n' "$project_id"
  printf '  "source_dir":"%s",\n' "$SRC_DIR"
  printf '  "out_dir":"%s",\n' "$OUT_DIR"
  printf '  "source_bytes":%s,\n' "$source_bytes"
  printf '  "source_mb":%s,\n' "$source_mb"
  printf '  "aiir_package_bytes":%s,\n' "$pkg_bytes"
  printf '  "aiir_package_mb":%s,\n' "$pkg_mb"
  printf '  "web_files_total":%d,\n' "$web_count"
  printf '  "native_reuse_files":%d,\n' "$native_count"
  printf '  "custom_mapping_files":%d,\n' "$custom_count"
  printf '  "native_reuse_percent":%s,\n' "$reuse_pct"
  printf '  "paiir_base_total":%d,\n' "$base_count"
  printf '  "paiir_custom_total":%d,\n' "$custom_unique_count"
  printf '  "paiir_total":%d,\n' "$paiir_total"
  printf '  "oaiir_total":%d,\n' "$oaiir_total"
  printf '  "oaiir_new_total":%d,\n' "$oaiir_new_total"
  printf '  "oaiir_html_ops_total":%d,\n' "$oaiir_html_ops_total"
  printf '  "oaiir_css_ops_total":%d,\n' "$oaiir_css_ops_total"
  printf '  "oaiir_js_ops_total":%d,\n' "$oaiir_js_ops_total"
  printf '  "oaiir_file":"%s",\n' "$OAIIR_FILE"
  printf '  "oaiir_html_ir_file":"%s",\n' "$OAIIR_HTML_IR_FILE"
  printf '  "oaiir_css_ir_file":"%s",\n' "$OAIIR_CSS_IR_FILE"
  printf '  "oaiir_js_ir_file":"%s",\n' "$OAIIR_JS_IR_FILE"
  printf '  "conversion_map":"%s",\n' "$MAP_FILE"
  printf '  "commands_file":"%s"\n' "$CMD_FILE"
  echo '}'
} > "$REPORT_FILE"

{
  echo '{'
  echo '  "base_commands":['
  echo '    "page.render.static",'
  echo '    "style.apply.theme",'
  echo '    "script.exec.basic",'
  echo '    "route.bind",'
  echo '    "data.read",'
  echo '    "data.write"'
  echo '  ],'
  echo '  "custom_commands":['
  i=0
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if [[ "$i" -gt 0 ]]; then echo ','; fi
    printf '    "%s"' "$c"
    i=$((i+1))
  done < "$custom_unique_tmp"
  echo
  echo '  ],'
  printf '  "paiir":{"base_total":%d,"custom_total":%d,"total":%d},\n' "$base_count" "$custom_unique_count" "$paiir_total"
  printf '  "oaiir":{"total":%d,"new_total":%d,"html_ops_total":%d,"css_ops_total":%d,"js_ops_total":%d,"registry":"%s","html_catalog":"%s","css_catalog":"%s","js_catalog":"%s","project_file":"%s","html_ir_file":"%s","css_ir_file":"%s","js_ir_file":"%s"}\n' "$oaiir_total" "$oaiir_new_total" "$oaiir_html_ops_total" "$oaiir_css_ops_total" "$oaiir_js_ops_total" "$OAIIR_REGISTRY" "$OAIIR_HTML_CATALOG" "$OAIIR_CSS_CATALOG" "$OAIIR_JS_CATALOG" "$OAIIR_FILE" "$OAIIR_HTML_IR_FILE" "$OAIIR_CSS_IR_FILE" "$OAIIR_JS_IR_FILE"
  echo '}'
} > "$CMD_FILE"

cat <<EOF2
{"ok":1,"action":"ingest_project","legacy_action":"convert_project","project_id":"${project_id}","report":"${REPORT_FILE}","commands":"${CMD_FILE}","oaiir":"${OAIIR_FILE}","oaiir_html_ir":"${OAIIR_HTML_IR_FILE}","oaiir_css_ir":"${OAIIR_CSS_IR_FILE}","oaiir_js_ir":"${OAIIR_JS_IR_FILE}","normalized_web":"${NORM_DIR}","package_dir":"${PKG_DIR}","native_reuse_percent":${reuse_pct},"paiir_base_total":${base_count},"paiir_custom_total":${custom_unique_count},"paiir_total":${paiir_total},"oaiir_total":${oaiir_total},"oaiir_new_total":${oaiir_new_total},"oaiir_html_ops_total":${oaiir_html_ops_total},"oaiir_css_ops_total":${oaiir_css_ops_total},"oaiir_js_ops_total":${oaiir_js_ops_total}}
EOF2
