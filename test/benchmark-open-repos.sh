#!/usr/bin/env bash
set -euo pipefail

AIIR_ROOT="${AIIR_ROOT:-/var/www/aiir}"
TEST_BASE="${AIIR_TEST_BASE:-${AIIR_ROOT}/test}"
WORK_ROOT="${TEST_BASE}/work"
SRC_ROOT="${WORK_ROOT}/src"
PKG_ROOT="${WORK_ROOT}/pkg"
LOG_FILE="${TEST_BASE}/OPEN_REPO_TEST_LOG.csv"
REPORT_FILE="${TEST_BASE}/OPEN_REPO_TESTS.md"
LATEST_FILE="${TEST_BASE}/OPEN_REPO_TEST_LATEST.csv"
DBOARD_SCRIPT="${TEST_BASE}/aiir-benchmark-dashboard.sh"
DBOARD_FILE="${TEST_BASE}/OPEN_REPO_DASHBOARD.md"
REPO_LIST_FILE="${TEST_BASE}/REPO_SOURCES.txt"
CORE_DIR="${AI_CORE_DIR:-${AIIR_ROOT}/ai/core}"
RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CSV_HEADER="run_utc,repo_url,repo_name,repo_commit,original_bytes,original_mb,aiir_pkg_bytes,aiir_pkg_mb,base_overhead_bytes,base_overhead_mb,aiir_net_bytes,aiir_net_mb,reduction_percent,notes"

to_mb() {
  awk -v b="$1" 'BEGIN {printf "%.2f", b/1048576}'
}

mkdir -p "${SRC_ROOT}" "${PKG_ROOT}" "${TEST_BASE}"

if [[ ! -f "${REPO_LIST_FILE}" ]]; then
  cat > "${REPO_LIST_FILE}" <<'LIST'
https://github.com/psf/requests.git
https://github.com/pallets/flask.git
https://github.com/jqlang/jq.git
LIST
fi

if [[ -f "${LOG_FILE}" ]]; then
  current_header="$(head -n 1 "${LOG_FILE}" || true)"
  if [[ "${current_header}" != "${CSV_HEADER}" ]]; then
    mv "${LOG_FILE}" "${LOG_FILE%.csv}.legacy-$(date -u +%Y%m%dT%H%M%SZ).csv"
  fi
fi
if [[ ! -f "${LOG_FILE}" ]]; then
  echo "${CSV_HEADER}" > "${LOG_FILE}"
fi

repos=()
if [[ "$#" -gt 0 ]]; then
  repos=("$@")
else
  while IFS= read -r line; do
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "${line}" || "${line:0:1}" == "#" ]] && continue
    repos+=("${line}")
  done < "${REPO_LIST_FILE}"
fi

if [[ "${#repos[@]}" -eq 0 ]]; then
  echo "no repositories configured" >&2
  exit 1
fi

BASE_EMPTY_SRC="${WORK_ROOT}/base_empty_src"
BASE_EMPTY_PKG="${WORK_ROOT}/base_empty_pkg"
mkdir -p "${BASE_EMPTY_SRC}"
: > "${BASE_EMPTY_SRC}/.keep"
BASE_B=0
BASE_MB="0.00"
if "${AIIR_ROOT}/ai/exchange/build-package.run.sh" "${BASE_EMPTY_SRC}" "${BASE_EMPTY_PKG}" "${CORE_DIR}" >"${WORK_ROOT}/base_pkg.log" 2>&1; then
  BASE_B="$(du -sb "${BASE_EMPTY_PKG}" | awk '{print $1}')"
  BASE_MB="$(to_mb "${BASE_B}")"
fi

for repo in "${repos[@]}"; do
  name="$(basename "${repo}" .git)"
  src="${SRC_ROOT}/${name}"
  pkg="${PKG_ROOT}/${name}"
  rm -rf "${src}" "${pkg}"

  if ! git clone --depth 1 "${repo}" "${src}" >"${WORK_ROOT}/clone_${name}.log" 2>&1; then
    echo "${RUN_TS},${repo},${name},,0,0,0,0,${BASE_B},${BASE_MB},0,0,0,clone_failed" >> "${LOG_FILE}"
    continue
  fi

  commit_sha="$(git -C "${src}" rev-parse --short HEAD 2>/dev/null || true)"

  if ! "${AIIR_ROOT}/ai/exchange/build-package.run.sh" "${src}" "${pkg}" "${CORE_DIR}" >"${WORK_ROOT}/pkg_${name}.log" 2>&1; then
    orig_b="$(du -sb "${src}" | awk '{print $1}')"
    orig_mb="$(to_mb "${orig_b}")"
    echo "${RUN_TS},${repo},${name},${commit_sha},${orig_b},${orig_mb},0,0,${BASE_B},${BASE_MB},0,0,0,package_failed" >> "${LOG_FILE}"
    continue
  fi

  orig_b="$(du -sb "${src}" | awk '{print $1}')"
  pkg_b="$(du -sb "${pkg}" | awk '{print $1}')"
  net_b=$((pkg_b - BASE_B))
  if [[ "${net_b}" -lt 0 ]]; then
    net_b=0
  fi

  orig_mb="$(to_mb "${orig_b}")"
  pkg_mb="$(to_mb "${pkg_b}")"
  net_mb="$(to_mb "${net_b}")"
  red="$(awk -v o="${orig_b}" -v n="${net_b}" 'BEGIN { if (o<=0) printf "0.00"; else printf "%.2f", ((o-n)/o)*100 }')"

  echo "${RUN_TS},${repo},${name},${commit_sha},${orig_b},${orig_mb},${pkg_b},${pkg_mb},${BASE_B},${BASE_MB},${net_b},${net_mb},${red},ok" >> "${LOG_FILE}"
done

TMP_LATEST="${WORK_ROOT}/latest.csv"
{
  echo "${CSV_HEADER}"
  awk -F, 'NR>1 {
    key=$2 FS $4;
    if (!(key in seen_ts) || $1 > seen_ts[key]) {
      seen_ts[key]=$1;
      seen_row[key]=$0;
    }
  } END {
    for (k in seen_row) print seen_row[k];
  }' "${LOG_FILE}" | sort -t, -k1,1 -k2,2
} > "${TMP_LATEST}"
cp "${TMP_LATEST}" "${LATEST_FILE}"

{
  echo "# Open Repo Benchmarks (AIIR)"
  echo
  echo "Last run (UTC): \`${RUN_TS}\`"
  echo
  echo "Base package overhead excluded from AIIR net size: ${BASE_MB} MB (${BASE_B} bytes)"
  echo
  echo "| Repo | Commit | Date (UTC) | Original MB | AIIR Net MB | Reduction | Note |"
  echo "|---|---|---:|---:|---:|---:|---|"
  awk -F, 'NR>1 {printf "| `%s` | `%s` | %s | %s | %s | %s%% | %s |\n", $2, $4, $1, $6, $12, $13, $14}' "${TMP_LATEST}" | tail -n 50
  echo
  avg_red="$(awk -F, 'NR>1 {sum+=$13; n++} END {if(n==0) printf "0.00"; else printf "%.2f", sum/n}' "${TMP_LATEST}")"
  p50_red="$(awk -F, 'NR>1 {print $13}' "${TMP_LATEST}" | sort -n | awk '{a[NR]=$1} END {if(NR==0){print "0.00"} else if(NR%2==1){printf "%.2f", a[(NR+1)/2]} else {printf "%.2f", (a[NR/2]+a[NR/2+1])/2}}')"
  echo "Reduction summary (latest per repo+commit): avg=${avg_red}% p50=${p50_red}%"
  echo
  echo "Notes:"
  echo "- Download, conversion and logs are executed under \`${TEST_BASE}\`."
  echo "- AIIR net size = total AIIR package size - base package overhead."
  echo "- Latest view file: \`${LATEST_FILE}\` (deduplicated by repo+commit, most recent run kept)."
  echo "- Cleanup keeps only CSV/report/repo-list/scripts in \`${TEST_BASE}\`; temporary repos/packages are removed."
} > "${REPORT_FILE}"

rm -rf "${WORK_ROOT}"

if [[ -x "${DBOARD_SCRIPT}" ]]; then
  "${DBOARD_SCRIPT}" "${TEST_BASE}" >/dev/null
fi

echo "benchmark-done: ${LOG_FILE}"
echo "report-done: ${REPORT_FILE}"
if [[ -f "${DBOARD_FILE}" ]]; then
  echo "dashboard-done: ${DBOARD_FILE}"
fi
