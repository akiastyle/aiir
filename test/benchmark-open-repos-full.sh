#!/usr/bin/env bash
set -euo pipefail

AIIR_ROOT="${AIIR_ROOT:-/var/www/aiir}"
TEST_BASE="${AIIR_TEST_BASE:-${AIIR_ROOT}/test}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
WORK_ROOT="${TEST_BASE}/full-work-${RUN_ID}"
SRC_ROOT="${WORK_ROOT}/src"
PKG_ROOT="${WORK_ROOT}/pkg"
CONV_ROOT="${WORK_ROOT}/conv"
LOG_FILE="${TEST_BASE}/OPEN_REPO_FULL_LOG.csv"
LATEST_FILE="${TEST_BASE}/OPEN_REPO_FULL_LATEST.csv"
REPORT_FILE="${TEST_BASE}/OPEN_REPO_FULL_REPORT.md"
ARTIFACT_DELTA_FILE="${TEST_BASE}/OPEN_REPO_FULL_ARTIFACT_DELTA.csv"
PROFILE_FILE="${TEST_BASE}/OPEN_REPO_FULL_PROFILE.csv"
PROFILE_REPORT_FILE="${TEST_BASE}/OPEN_REPO_FULL_PROFILE_REPORT.md"
REPO_LIST_FILE="${TEST_BASE}/REPO_SOURCES.txt"
CORE_DIR="${AI_CORE_DIR:-${AIIR_ROOT}/ai/core}"
RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CLONE_TIMEOUT_SEC="${AIIR_CLONE_TIMEOUT_SEC:-900}"
CLONE_RETRIES="${AIIR_CLONE_RETRIES:-2}"
INGEST_TIMEOUT_SEC="${AIIR_INGEST_TIMEOUT_SEC:-1200}"
PARITY_TIMEOUT_SEC="${AIIR_PARITY_TIMEOUT_SEC:-600}"
FULL_ANALYSIS_MAX_MB="${AIIR_FULL_ANALYSIS_MAX_MB:-350}"
CHUNK_MAX_WEB_FILES="${AIIR_CHUNK_MAX_WEB_FILES:-4000}"
CHUNK_MAX_WEB_BYTES="${AIIR_CHUNK_MAX_WEB_BYTES:-157286400}"
CSV_HEADER="run_utc,repo_url,repo_name,repo_commit,original_bytes,original_mb,aiir_pkg_bytes,aiir_pkg_mb,base_overhead_bytes,base_overhead_mb,aiir_net_bytes,aiir_net_mb,reduction_percent,native_reuse_percent,paiir_total,paiir_custom_total,oaiir_total,oaiir_new_total,oaiir_html_ops_total,oaiir_css_ops_total,oaiir_js_ops_total,logic_file_parity,logic_token_parity,visual_parity,overall_parity,chunk_mode,chunk_web_files,chunk_web_bytes,notes"
PROFILE_HEADER="run_utc,repo_url,repo_name,repo_commit,clone_sec,package_sec,ingest_sec,parity_sec,total_sec,note"

to_mb() {
  awk -v b="$1" 'BEGIN {printf "%.2f", b/1048576}'
}

json_num() {
  local key="$1"
  local file="$2"
  sed -n "s/.*\"${key}\":\([0-9.]*\).*/\1/p" "$file" | head -n1
}

copy_web_sample() {
  local src="$1"
  local dst="$2"
  local max_files="$3"
  local max_bytes="$4"
  local manifest="$5"
  local copied=0
  local copied_bytes=0
  mkdir -p "$dst"
  : > "$manifest"
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    [[ -f "$abs" ]] || continue
    fbytes="$(wc -c < "$abs" | awk '{print $1}')"
    if [[ "$copied" -ge "$max_files" || $((copied_bytes + fbytes)) -gt "$max_bytes" ]]; then
      break
    fi
    rel="${abs#$src/}"
    out="${dst}/${rel}"
    mkdir -p "$(dirname "$out")"
    cp "$abs" "$out"
    echo "$abs" >> "$manifest"
    copied=$((copied+1))
    copied_bytes=$((copied_bytes+fbytes))
  done < <(rg --files -uu "$src" -g '*.html' -g '*.htm' -g '*.css' -g '*.scss' -g '*.js' -g '*.jsx' -g '*.ts' -g '*.tsx' 2>/dev/null | sort)
  echo "${copied},${copied_bytes}"
}

mkdir -p "$SRC_ROOT" "$PKG_ROOT" "$CONV_ROOT" "$TEST_BASE"
cleanup_work() {
  rm -rf "$WORK_ROOT"
}
trap cleanup_work EXIT

if [[ ! -f "$REPO_LIST_FILE" ]]; then
  cat > "$REPO_LIST_FILE" <<'LIST'
https://github.com/psf/requests.git
https://github.com/pallets/flask.git
https://github.com/jqlang/jq.git
LIST
fi

if [[ -f "$LOG_FILE" ]]; then
  current_header="$(head -n 1 "$LOG_FILE" || true)"
  if [[ "$current_header" != "$CSV_HEADER" ]]; then
    mv "$LOG_FILE" "${LOG_FILE%.csv}.legacy-$(date -u +%Y%m%dT%H%M%SZ).csv"
  fi
fi
if [[ ! -f "$LOG_FILE" ]]; then
  echo "$CSV_HEADER" > "$LOG_FILE"
fi
if [[ -f "$PROFILE_FILE" ]]; then
  current_profile_header="$(head -n 1 "$PROFILE_FILE" || true)"
  if [[ "$current_profile_header" != "$PROFILE_HEADER" ]]; then
    mv "$PROFILE_FILE" "${PROFILE_FILE%.csv}.legacy-$(date -u +%Y%m%dT%H%M%SZ).csv"
  fi
fi
if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "$PROFILE_HEADER" > "$PROFILE_FILE"
fi

repos=()
if [[ "$#" -gt 0 ]]; then
  repos=("$@")
else
  while IFS= read -r line; do
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    repos+=("$line")
  done < "$REPO_LIST_FILE"
fi

if [[ "${#repos[@]}" -eq 0 ]]; then
  echo "no repositories configured" >&2
  exit 1
fi

BASE_EMPTY_SRC="${WORK_ROOT}/base_empty_src"
BASE_EMPTY_PKG="${WORK_ROOT}/base_empty_pkg"
mkdir -p "$BASE_EMPTY_SRC"
: > "${BASE_EMPTY_SRC}/.keep"
BASE_B=0
BASE_MB="0.00"
if "${AIIR_ROOT}/ai/exchange/build-package.run.sh" "$BASE_EMPTY_SRC" "$BASE_EMPTY_PKG" "$CORE_DIR" >"${WORK_ROOT}/base_pkg.log" 2>&1; then
  BASE_B="$(du -sb "$BASE_EMPTY_PKG" | awk '{print $1}')"
  BASE_MB="$(to_mb "$BASE_B")"
fi

for repo in "${repos[@]}"; do
  repo_start_ts="$(date +%s)"
  clone_sec=0
  package_sec=0
  ingest_sec=0
  parity_sec=0
  name="$(basename "$repo" .git)"
  src="${SRC_ROOT}/${name}"
  pkg="${PKG_ROOT}/${name}"
  conv="${CONV_ROOT}/${name}"
  rm -rf "$src" "$pkg" "$conv"

  clone_ok=0
  clone_note="clone_failed"
  clone_start_ts="$(date +%s)"
  for attempt in $(seq 1 "$CLONE_RETRIES"); do
    rm -rf "$src"
    {
      echo "attempt=${attempt} timeout_sec=${CLONE_TIMEOUT_SEC} repo=${repo}"
      if command -v timeout >/dev/null 2>&1; then
        timeout "${CLONE_TIMEOUT_SEC}s" git clone --depth 1 "$repo" "$src"
      else
        git clone --depth 1 "$repo" "$src"
      fi
    } >"${WORK_ROOT}/clone_${name}.log" 2>&1 && {
      clone_ok=1
      clone_note="ok"
      break
    }
    rc=$?
    if [[ "$rc" -eq 124 ]]; then
      clone_note="clone_timeout"
    fi
  done
  clone_sec=$(( $(date +%s) - clone_start_ts ))

  if [[ "$clone_ok" != "1" ]]; then
    echo "${RUN_TS},${repo},${name},,0,0,0,0,${BASE_B},${BASE_MB},0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,none,0,0,${clone_note}" >> "$LOG_FILE"
    total_sec=$(( $(date +%s) - repo_start_ts ))
    echo "${RUN_TS},${repo},${name},,${clone_sec},${package_sec},${ingest_sec},${parity_sec},${total_sec},${clone_note}" >> "$PROFILE_FILE"
    continue
  fi

  commit_sha="$(git -C "$src" rev-parse --short HEAD 2>/dev/null || true)"

  package_start_ts="$(date +%s)"
  if ! "${AIIR_ROOT}/ai/exchange/build-package.run.sh" "$src" "$pkg" "$CORE_DIR" >"${WORK_ROOT}/pkg_${name}.log" 2>&1; then
    package_sec=$(( $(date +%s) - package_start_ts ))
    orig_b="$(du -sb "$src" | awk '{print $1}')"
    orig_mb="$(to_mb "$orig_b")"
    echo "${RUN_TS},${repo},${name},${commit_sha},${orig_b},${orig_mb},0,0,${BASE_B},${BASE_MB},0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,none,0,0,package_failed" >> "$LOG_FILE"
    total_sec=$(( $(date +%s) - repo_start_ts ))
    echo "${RUN_TS},${repo},${name},${commit_sha},${clone_sec},${package_sec},${ingest_sec},${parity_sec},${total_sec},package_failed" >> "$PROFILE_FILE"
    continue
  fi
  package_sec=$(( $(date +%s) - package_start_ts ))

  orig_b="$(du -sb "$src" | awk '{print $1}')"
  pkg_b="$(du -sb "$pkg" | awk '{print $1}')"
  net_b=$((pkg_b - BASE_B))
  if [[ "$net_b" -lt 0 ]]; then net_b=0; fi
  orig_mb="$(to_mb "$orig_b")"
  pkg_mb="$(to_mb "$pkg_b")"
  net_mb="$(to_mb "$net_b")"
  red="$(awk -v o="$orig_b" -v n="$net_b" 'BEGIN {if(o<=0) printf "0.00"; else printf "%.2f", ((o-n)/o)*100}')"
  max_full_b="$(awk -v mb="$FULL_ANALYSIS_MAX_MB" 'BEGIN {printf "%.0f", mb*1048576}')"

  note="ok"
  native_reuse="0"
  paiir_total="0"
  paiir_custom="0"
  oaiir_total="0"
  oaiir_new="0"
  oaiir_html_ops="0"
  oaiir_css_ops="0"
  oaiir_js_ops="0"
  logic_file="0"
  logic_token="0"
  visual="0"
  overall="0"
  chunk_mode="none"
  chunk_web_files="0"
  chunk_web_bytes="0"

  if [[ "$orig_b" -gt "$max_full_b" ]]; then
    chunk_src="${WORK_ROOT}/chunk_${name}"
    chunk_manifest="${WORK_ROOT}/chunk_${name}.manifest"
    rm -rf "$chunk_src"
    IFS=',' read -r chunk_web_files chunk_web_bytes < <(copy_web_sample "$src" "$chunk_src" "$CHUNK_MAX_WEB_FILES" "$CHUNK_MAX_WEB_BYTES" "$chunk_manifest")
    if [[ "$chunk_web_files" -gt 0 ]]; then
      chunk_mode="web_sample"
      ingest_start_ts="$(date +%s)"
      if command -v timeout >/dev/null 2>&1; then
        timeout "${INGEST_TIMEOUT_SEC}s" "${AIIR_ROOT}/server/scripts/aiir" ingest "$chunk_src" "$conv" "${name}-chunk" >"${WORK_ROOT}/ingest_${name}.json" 2>"${WORK_ROOT}/ingest_${name}.err" || note="ingest_failed"
      else
        "${AIIR_ROOT}/server/scripts/aiir" ingest "$chunk_src" "$conv" "${name}-chunk" >"${WORK_ROOT}/ingest_${name}.json" 2>"${WORK_ROOT}/ingest_${name}.err" || note="ingest_failed"
      fi
      ingest_sec=$(( $(date +%s) - ingest_start_ts ))
      if [[ "$note" == "ok" ]]; then
        native_reuse="$(json_num native_reuse_percent "${WORK_ROOT}/ingest_${name}.json")"
        paiir_total="$(json_num paiir_total "${WORK_ROOT}/ingest_${name}.json")"
        paiir_custom="$(json_num paiir_custom_total "${WORK_ROOT}/ingest_${name}.json")"
        oaiir_total="$(json_num oaiir_total "${WORK_ROOT}/ingest_${name}.json")"
        oaiir_new="$(json_num oaiir_new_total "${WORK_ROOT}/ingest_${name}.json")"
        oaiir_html_ops="$(json_num oaiir_html_ops_total "${WORK_ROOT}/ingest_${name}.json")"
        oaiir_css_ops="$(json_num oaiir_css_ops_total "${WORK_ROOT}/ingest_${name}.json")"
        oaiir_js_ops="$(json_num oaiir_js_ops_total "${WORK_ROOT}/ingest_${name}.json")"
        [[ -n "$native_reuse" ]] || native_reuse="0"
        [[ -n "$paiir_total" ]] || paiir_total="0"
        [[ -n "$paiir_custom" ]] || paiir_custom="0"
        [[ -n "$oaiir_total" ]] || oaiir_total="0"
        [[ -n "$oaiir_new" ]] || oaiir_new="0"
        [[ -n "$oaiir_html_ops" ]] || oaiir_html_ops="0"
        [[ -n "$oaiir_css_ops" ]] || oaiir_css_ops="0"
        [[ -n "$oaiir_js_ops" ]] || oaiir_js_ops="0"
        parity_start_ts="$(date +%s)"
        if command -v timeout >/dev/null 2>&1; then
          timeout "${PARITY_TIMEOUT_SEC}s" "${AIIR_ROOT}/server/scripts/aiir" parity "$chunk_src" "$conv" >"${WORK_ROOT}/parity_${name}.json" 2>"${WORK_ROOT}/parity_${name}.err" || note="parity_failed"
        else
          "${AIIR_ROOT}/server/scripts/aiir" parity "$chunk_src" "$conv" >"${WORK_ROOT}/parity_${name}.json" 2>"${WORK_ROOT}/parity_${name}.err" || note="parity_failed"
        fi
        parity_sec=$(( $(date +%s) - parity_start_ts ))
      fi
      if [[ "$note" == "ok" ]]; then
        logic_file="$(json_num logic_file_parity "${WORK_ROOT}/parity_${name}.json")"
        logic_token="$(json_num logic_token_parity "${WORK_ROOT}/parity_${name}.json")"
        visual="$(json_num visual_parity "${WORK_ROOT}/parity_${name}.json")"
        overall="$(json_num overall_parity "${WORK_ROOT}/parity_${name}.json")"
        [[ -n "$logic_file" ]] || logic_file="0"
        [[ -n "$logic_token" ]] || logic_token="0"
        [[ -n "$visual" ]] || visual="0"
        [[ -n "$overall" ]] || overall="0"
        note="analysis_chunked_large"
      fi
    else
      note="analysis_skipped_large_no_web"
    fi
  else
    ingest_start_ts="$(date +%s)"
    if command -v timeout >/dev/null 2>&1; then
      timeout "${INGEST_TIMEOUT_SEC}s" "${AIIR_ROOT}/server/scripts/aiir" ingest "$src" "$conv" "$name" >"${WORK_ROOT}/ingest_${name}.json" 2>"${WORK_ROOT}/ingest_${name}.err" || note="ingest_failed"
    else
      "${AIIR_ROOT}/server/scripts/aiir" ingest "$src" "$conv" "$name" >"${WORK_ROOT}/ingest_${name}.json" 2>"${WORK_ROOT}/ingest_${name}.err" || note="ingest_failed"
    fi
    ingest_sec=$(( $(date +%s) - ingest_start_ts ))
  fi

  if [[ "$note" == "ok" ]]; then
    native_reuse="$(json_num native_reuse_percent "${WORK_ROOT}/ingest_${name}.json")"
    if [[ -z "$native_reuse" ]]; then native_reuse="0"; fi
    paiir_total="$(json_num paiir_total "${WORK_ROOT}/ingest_${name}.json")"
    paiir_custom="$(json_num paiir_custom_total "${WORK_ROOT}/ingest_${name}.json")"
    oaiir_total="$(json_num oaiir_total "${WORK_ROOT}/ingest_${name}.json")"
    oaiir_new="$(json_num oaiir_new_total "${WORK_ROOT}/ingest_${name}.json")"
    oaiir_html_ops="$(json_num oaiir_html_ops_total "${WORK_ROOT}/ingest_${name}.json")"
    oaiir_css_ops="$(json_num oaiir_css_ops_total "${WORK_ROOT}/ingest_${name}.json")"
    oaiir_js_ops="$(json_num oaiir_js_ops_total "${WORK_ROOT}/ingest_${name}.json")"
    [[ -n "$paiir_total" ]] || paiir_total="0"
    [[ -n "$paiir_custom" ]] || paiir_custom="0"
    [[ -n "$oaiir_total" ]] || oaiir_total="0"
    [[ -n "$oaiir_new" ]] || oaiir_new="0"
    [[ -n "$oaiir_html_ops" ]] || oaiir_html_ops="0"
    [[ -n "$oaiir_css_ops" ]] || oaiir_css_ops="0"
    [[ -n "$oaiir_js_ops" ]] || oaiir_js_ops="0"

    parity_start_ts="$(date +%s)"
    if command -v timeout >/dev/null 2>&1; then
      timeout "${PARITY_TIMEOUT_SEC}s" "${AIIR_ROOT}/server/scripts/aiir" parity "$src" "$conv" >"${WORK_ROOT}/parity_${name}.json" 2>"${WORK_ROOT}/parity_${name}.err" || note="parity_failed"
    else
      "${AIIR_ROOT}/server/scripts/aiir" parity "$src" "$conv" >"${WORK_ROOT}/parity_${name}.json" 2>"${WORK_ROOT}/parity_${name}.err" || note="parity_failed"
    fi
    parity_sec=$(( $(date +%s) - parity_start_ts ))
  fi

  if [[ "$note" == "ok" ]]; then
    logic_file="$(json_num logic_file_parity "${WORK_ROOT}/parity_${name}.json")"
    logic_token="$(json_num logic_token_parity "${WORK_ROOT}/parity_${name}.json")"
    visual="$(json_num visual_parity "${WORK_ROOT}/parity_${name}.json")"
    overall="$(json_num overall_parity "${WORK_ROOT}/parity_${name}.json")"
    [[ -n "$logic_file" ]] || logic_file="0"
    [[ -n "$logic_token" ]] || logic_token="0"
    [[ -n "$visual" ]] || visual="0"
    [[ -n "$overall" ]] || overall="0"
  fi

  echo "${RUN_TS},${repo},${name},${commit_sha},${orig_b},${orig_mb},${pkg_b},${pkg_mb},${BASE_B},${BASE_MB},${net_b},${net_mb},${red},${native_reuse},${paiir_total},${paiir_custom},${oaiir_total},${oaiir_new},${oaiir_html_ops},${oaiir_css_ops},${oaiir_js_ops},${logic_file},${logic_token},${visual},${overall},${chunk_mode},${chunk_web_files},${chunk_web_bytes},${note}" >> "$LOG_FILE"
  total_sec=$(( $(date +%s) - repo_start_ts ))
  echo "${RUN_TS},${repo},${name},${commit_sha},${clone_sec},${package_sec},${ingest_sec},${parity_sec},${total_sec},${note}" >> "$PROFILE_FILE"
done

TMP_LATEST="${WORK_ROOT}/latest.csv"
{
  echo "$CSV_HEADER"
  awk -F, 'NR>1 {
    key=$2 FS $4;
    if (!(key in seen_ts) || $1 > seen_ts[key]) {
      seen_ts[key]=$1;
      seen_row[key]=$0;
    }
  } END {
    for (k in seen_row) print seen_row[k];
  }' "$LOG_FILE" | sort -t, -k1,1 -k2,2
} > "$TMP_LATEST"
cp "$TMP_LATEST" "$LATEST_FILE"

{
  echo "run_utc,repo_url,repo_name,repo_commit,paiir_total,paiir_custom_total,paiir_base_total,oaiir_total,oaiir_new_total,oaiir_existing_total,oaiir_html_ops_total,oaiir_css_ops_total,oaiir_js_ops_total,overall_parity,note"
  awk -F, 'NR>1 {
    paiir_base=$15-$16; if (paiir_base<0) paiir_base=0;
    oaiir_existing=$17-$18; if (oaiir_existing<0) oaiir_existing=0;
    printf "%s,%s,%s,%s,%s,%s,%d,%s,%s,%d,%s,%s,%s,%s,%s\n", $1,$2,$3,$4,$15,$16,paiir_base,$17,$18,oaiir_existing,$19,$20,$21,$25,$29;
  }' "$TMP_LATEST"
} > "$ARTIFACT_DELTA_FILE"

{
  echo "# Open Repo Full Benchmark (AIIR MB + Parity)"
  echo
  echo "Last run (UTC): \`${RUN_TS}\`"
  echo
  echo "Base package overhead excluded from AIIR net size: ${BASE_MB} MB (${BASE_B} bytes)"
  echo "Full analysis threshold (ingest+parity): ${FULL_ANALYSIS_MAX_MB} MB source size"
  echo
  echo "| Repo | Commit | Original MB | AIIR Net MB | Reduction | Reuse | PAIIR | OAIIR | Logic | Visual | Overall | Chunk | Note |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|"
  awk -F, 'NR>1 {printf "| `%s` | `%s` | %s | %s | %s%% | %s%% | %s (%s custom) | %s (+%s) | %s%% | %s%% | %s%% | %s | %s |\n", $2, $4, $6, $12, $13, $14, $15, $16, $17, $18, $22, $24, $25, $26, $29}' "$TMP_LATEST" | tail -n 50
  echo
  skipped_large_count="$(awk -F, 'NR>1 && $29 ~ /^analysis_skipped_large/ {c++} END{print c+0}' "$TMP_LATEST")"
  chunked_count="$(awk -F, 'NR>1 && $29=="analysis_chunked_large" {c++} END{print c+0}' "$TMP_LATEST")"
  ok_count="$(awk -F, 'NR>1 && $29=="ok" {c++} END{print c+0}' "$TMP_LATEST")"
  total_count="$(awk -F, 'NR>1 {c++} END{print c+0}' "$TMP_LATEST")"
  paiir_custom_added_total="$(awk -F, 'NR>1 {sum+=$16} END{print sum+0}' "$TMP_LATEST")"
  oaiir_new_added_total="$(awk -F, 'NR>1 {sum+=$18} END{print sum+0}' "$TMP_LATEST")"
  repos_with_oaiir_new="$(awk -F, 'NR>1 && ($18+0)>0 {c++} END{print c+0}' "$TMP_LATEST")"
  repos_with_custom_paiir="$(awk -F, 'NR>1 && ($16+0)>0 {c++} END{print c+0}' "$TMP_LATEST")"
  parity_below_100="$(awk -F, 'NR>1 && ($25+0)<100 {c++} END{print c+0}' "$TMP_LATEST")"
  echo "Artifact delta (latest per repo+commit): paiir_custom_added_total=${paiir_custom_added_total} oaiir_new_added_total=${oaiir_new_added_total} repos_with_custom_paiir=${repos_with_custom_paiir}/${total_count} repos_with_oaiir_new=${repos_with_oaiir_new}/${total_count} parity_below_100=${parity_below_100}/${total_count} ok=${ok_count}/${total_count} chunked=${chunked_count} skipped_large=${skipped_large_count}"
  echo "Artifact delta csv: ${ARTIFACT_DELTA_FILE}"
} > "$REPORT_FILE"

{
  echo "# Open Repo Full Benchmark Profiling"
  echo
  echo "Last run (UTC): \`${RUN_TS}\`"
  echo
  echo "| Repo | Commit | Clone s | Package s | Ingest s | Parity s | Total s | Note |"
  echo "|---|---|---:|---:|---:|---:|---:|---|"
  awk -F, -v ts="$RUN_TS" 'NR>1 && $1==ts {printf "| `%s` | `%s` | %s | %s | %s | %s | %s | %s |\n", $2, $4, $5, $6, $7, $8, $9, $10}' "$PROFILE_FILE"
  echo
  tot_clone="$(awk -F, -v ts="$RUN_TS" 'NR>1 && $1==ts {s+=$5} END{print s+0}' "$PROFILE_FILE")"
  tot_package="$(awk -F, -v ts="$RUN_TS" 'NR>1 && $1==ts {s+=$6} END{print s+0}' "$PROFILE_FILE")"
  tot_ingest="$(awk -F, -v ts="$RUN_TS" 'NR>1 && $1==ts {s+=$7} END{print s+0}' "$PROFILE_FILE")"
  tot_parity="$(awk -F, -v ts="$RUN_TS" 'NR>1 && $1==ts {s+=$8} END{print s+0}' "$PROFILE_FILE")"
  tot_total="$(awk -F, -v ts="$RUN_TS" 'NR>1 && $1==ts {s+=$9} END{print s+0}' "$PROFILE_FILE")"
  run_count="$(awk -F, -v ts="$RUN_TS" 'NR>1 && $1==ts {c++} END{print c+0}' "$PROFILE_FILE")"
  echo "Totals (run scope): repos=${run_count} clone_sec=${tot_clone} package_sec=${tot_package} ingest_sec=${tot_ingest} parity_sec=${tot_parity} total_sec=${tot_total}"
} > "$PROFILE_REPORT_FILE"

echo "full-benchmark-done: ${LOG_FILE}"
echo "full-latest-done: ${LATEST_FILE}"
echo "full-report-done: ${REPORT_FILE}"
echo "full-profile-done: ${PROFILE_FILE}"
echo "full-profile-report-done: ${PROFILE_REPORT_FILE}"
