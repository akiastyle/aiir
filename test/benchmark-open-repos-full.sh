#!/usr/bin/env bash
set -euo pipefail

AIIR_ROOT="${AIIR_ROOT:-/var/www/aiir}"
TEST_BASE="${AIIR_TEST_BASE:-${AIIR_ROOT}/test}"
WORK_ROOT="${TEST_BASE}/full-work"
SRC_ROOT="${WORK_ROOT}/src"
PKG_ROOT="${WORK_ROOT}/pkg"
CONV_ROOT="${WORK_ROOT}/conv"
LOG_FILE="${TEST_BASE}/OPEN_REPO_FULL_LOG.csv"
LATEST_FILE="${TEST_BASE}/OPEN_REPO_FULL_LATEST.csv"
REPORT_FILE="${TEST_BASE}/OPEN_REPO_FULL_REPORT.md"
REPO_LIST_FILE="${TEST_BASE}/REPO_SOURCES.txt"
CORE_DIR="${AI_CORE_DIR:-${AIIR_ROOT}/ai/core}"
RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CLONE_TIMEOUT_SEC="${AIIR_CLONE_TIMEOUT_SEC:-900}"
CLONE_RETRIES="${AIIR_CLONE_RETRIES:-2}"
INGEST_TIMEOUT_SEC="${AIIR_INGEST_TIMEOUT_SEC:-1200}"
PARITY_TIMEOUT_SEC="${AIIR_PARITY_TIMEOUT_SEC:-600}"
FULL_ANALYSIS_MAX_MB="${AIIR_FULL_ANALYSIS_MAX_MB:-350}"
CSV_HEADER="run_utc,repo_url,repo_name,repo_commit,original_bytes,original_mb,aiir_pkg_bytes,aiir_pkg_mb,base_overhead_bytes,base_overhead_mb,aiir_net_bytes,aiir_net_mb,reduction_percent,native_reuse_percent,logic_file_parity,logic_token_parity,visual_parity,overall_parity,notes"

to_mb() {
  awk -v b="$1" 'BEGIN {printf "%.2f", b/1048576}'
}

json_num() {
  local key="$1"
  local file="$2"
  sed -n "s/.*\"${key}\":\([0-9.]*\).*/\1/p" "$file" | head -n1
}

mkdir -p "$SRC_ROOT" "$PKG_ROOT" "$CONV_ROOT" "$TEST_BASE"

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
  name="$(basename "$repo" .git)"
  src="${SRC_ROOT}/${name}"
  pkg="${PKG_ROOT}/${name}"
  conv="${CONV_ROOT}/${name}"
  rm -rf "$src" "$pkg" "$conv"

  clone_ok=0
  clone_note="clone_failed"
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

  if [[ "$clone_ok" != "1" ]]; then
    echo "${RUN_TS},${repo},${name},,0,0,0,0,${BASE_B},${BASE_MB},0,0,0,0,0,0,0,0,${clone_note}" >> "$LOG_FILE"
    continue
  fi

  commit_sha="$(git -C "$src" rev-parse --short HEAD 2>/dev/null || true)"

  if ! "${AIIR_ROOT}/ai/exchange/build-package.run.sh" "$src" "$pkg" "$CORE_DIR" >"${WORK_ROOT}/pkg_${name}.log" 2>&1; then
    orig_b="$(du -sb "$src" | awk '{print $1}')"
    orig_mb="$(to_mb "$orig_b")"
    echo "${RUN_TS},${repo},${name},${commit_sha},${orig_b},${orig_mb},0,0,${BASE_B},${BASE_MB},0,0,0,0,0,0,0,0,package_failed" >> "$LOG_FILE"
    continue
  fi

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
  logic_file="0"
  logic_token="0"
  visual="0"
  overall="0"

  if [[ "$orig_b" -gt "$max_full_b" ]]; then
    note="analysis_skipped_large"
  else
    if command -v timeout >/dev/null 2>&1; then
      timeout "${INGEST_TIMEOUT_SEC}s" "${AIIR_ROOT}/server/scripts/aiir" ingest "$src" "$conv" "$name" >"${WORK_ROOT}/ingest_${name}.json" 2>"${WORK_ROOT}/ingest_${name}.err" || note="ingest_failed"
    else
      "${AIIR_ROOT}/server/scripts/aiir" ingest "$src" "$conv" "$name" >"${WORK_ROOT}/ingest_${name}.json" 2>"${WORK_ROOT}/ingest_${name}.err" || note="ingest_failed"
    fi
  fi

  if [[ "$note" == "ok" ]]; then
    native_reuse="$(json_num native_reuse_percent "${WORK_ROOT}/ingest_${name}.json")"
    if [[ -z "$native_reuse" ]]; then native_reuse="0"; fi

    if command -v timeout >/dev/null 2>&1; then
      timeout "${PARITY_TIMEOUT_SEC}s" "${AIIR_ROOT}/server/scripts/aiir" parity "$src" "$conv" >"${WORK_ROOT}/parity_${name}.json" 2>"${WORK_ROOT}/parity_${name}.err" || note="parity_failed"
    else
      "${AIIR_ROOT}/server/scripts/aiir" parity "$src" "$conv" >"${WORK_ROOT}/parity_${name}.json" 2>"${WORK_ROOT}/parity_${name}.err" || note="parity_failed"
    fi
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

  echo "${RUN_TS},${repo},${name},${commit_sha},${orig_b},${orig_mb},${pkg_b},${pkg_mb},${BASE_B},${BASE_MB},${net_b},${net_mb},${red},${native_reuse},${logic_file},${logic_token},${visual},${overall},${note}" >> "$LOG_FILE"
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
  echo "# Open Repo Full Benchmark (AIIR MB + Parity)"
  echo
  echo "Last run (UTC): \`${RUN_TS}\`"
  echo
  echo "Base package overhead excluded from AIIR net size: ${BASE_MB} MB (${BASE_B} bytes)"
  echo "Full analysis threshold (ingest+parity): ${FULL_ANALYSIS_MAX_MB} MB source size"
  echo
  echo "| Repo | Commit | Original MB | AIIR Net MB | Reduction | Reuse | Logic | Visual | Overall | Note |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---:|---|"
  awk -F, 'NR>1 {printf "| `%s` | `%s` | %s | %s | %s%% | %s%% | %s%% | %s%% | %s%% | %s |\n", $2, $4, $6, $12, $13, $14, $15, $17, $18, $19}' "$TMP_LATEST" | tail -n 50
  echo
  avg_red="$(awk -F, 'NR>1 {sum+=$13; n++} END {if(n==0) printf "0.00"; else printf "%.2f", sum/n}' "$TMP_LATEST")"
  avg_overall_ok="$(awk -F, 'NR>1 && $19=="ok" {sum+=$18; n++} END {if(n==0) printf "0.00"; else printf "%.2f", sum/n}' "$TMP_LATEST")"
  skipped_large_count="$(awk -F, 'NR>1 && $19=="analysis_skipped_large" {c++} END{print c+0}' "$TMP_LATEST")"
  ok_count="$(awk -F, 'NR>1 && $19=="ok" {c++} END{print c+0}' "$TMP_LATEST")"
  total_count="$(awk -F, 'NR>1 {c++} END{print c+0}' "$TMP_LATEST")"
  echo "Summary (latest per repo+commit): reduction_avg=${avg_red}% overall_parity_avg_ok=${avg_overall_ok}% ok=${ok_count}/${total_count} skipped_large=${skipped_large_count}"
} > "$REPORT_FILE"

rm -rf "$WORK_ROOT"

echo "full-benchmark-done: ${LOG_FILE}"
echo "full-latest-done: ${LATEST_FILE}"
echo "full-report-done: ${REPORT_FILE}"
