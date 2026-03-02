#!/usr/bin/env bash
set -euo pipefail

AIIR_ROOT="${AIIR_ROOT:-/var/www/aiir}"
TEST_BASE="${AIIR_TEST_BASE:-${AIIR_ROOT}/test}"
WORK_ROOT="${TEST_BASE}/work"
SRC_ROOT="${WORK_ROOT}/src"
REPO_LIST_FILE="${TEST_BASE}/REPO_SOURCES.txt"
EXCLUDE_FILE="${TEST_BASE}/FEATURE_EXCLUSIONS.txt"
MATRIX_CSV="${TEST_BASE}/FEATURE_MATRIX.csv"
BACKLOG_MD="${TEST_BASE}/AIIR_IMPROVEMENT_BACKLOG.md"
RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${SRC_ROOT}" "${TEST_BASE}"

if [[ ! -f "${REPO_LIST_FILE}" ]]; then
  echo "missing repo list: ${REPO_LIST_FILE}" >&2
  exit 1
fi

repos=()
while IFS= read -r line; do
  line="${line#${line%%[![:space:]]*}}"
  line="${line%${line##*[![:space:]]}}"
  [[ -z "${line}" || "${line:0:1}" == "#" ]] && continue
  repos+=("${line}")
done < "${REPO_LIST_FILE}"

if [[ "${#repos[@]}" -eq 0 ]]; then
  echo "no repositories configured" >&2
  exit 1
fi

# key|label|regex
features=(
  "jwt_auth|JWT/OAuth auth|jwt|oauth2|openid|oidc|bearer token"
  "mtls|mTLS/client certificate|mTLS|mutual tls|client certificate"
  "rbac|RBAC/permissions|\\brbac\\b|role[-_ ]based access|authorization policy|access control"
  "otel_tracing|OpenTelemetry/tracing|opentelemetry|otel|traceparent|tracing"
  "metrics|Metrics endpoint|prometheus|/metrics|metrics endpoint"
  "structured_logging|Structured logging|json log|structured logging|logrus|zap|winston|pino"
  "config_reload|Config reload|reload config|hot reload|sighup"
  "idempotency|Idempotency keys|idempotency-key|idempotent"
  "retry_backoff|Retry/backoff policies|retry policy|exponential backoff|backoff"
  "api_schema|API schema/OpenAPI|openapi|swagger|json schema"
  "middleware_ext|Middleware/plugin extension|middleware stack|plugin system|extension point|interceptor"
  "fuzzing|Fuzz/property testing|fuzz|property-based|quickcheck"
)

is_excluded_feature() {
  local key="$1"
  [[ -f "${EXCLUDE_FILE}" ]] || return 1
  while IFS= read -r line; do
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "${line}" || "${line:0:1}" == "#" ]] && continue
    if [[ "${line}" == "${key}" ]]; then
      return 0
    fi
  done < "${EXCLUDE_FILE}"
  return 1
}

has_pattern() {
  local dir="$1"
  local regex="$2"
  if rg -i -n -m 1 --glob '!*.min.*' --glob '!*.svg' --glob '!*.png' --glob '!*.jpg' --glob '!*.lock' "$regex" "$dir" >/dev/null 2>&1; then
    echo 1
  else
    echo 0
  fi
}

echo "run_utc,target_type,target_name,target_commit,feature_key,feature_label,present" > "${MATRIX_CSV}"

# AIIR baseline scan
for feat in "${features[@]}"; do
  key="${feat%%|*}"
  rest="${feat#*|}"
  label="${rest%%|*}"
  regex="${rest#*|}"
  present="$(has_pattern "${AIIR_ROOT}/ai" "${regex}")"
  if [[ "${present}" == "0" ]]; then
    present="$(has_pattern "${AIIR_ROOT}/server" "${regex}")"
  fi
  if [[ "${present}" == "0" ]]; then
    present="$(has_pattern "${AIIR_ROOT}/docs" "${regex}")"
  fi
  echo "${RUN_TS},aiir,aiir-core-runtime-security,${AIIR_COMMIT:-$(git -C "${AIIR_ROOT}" rev-parse --short HEAD 2>/dev/null || true)},${key},${label},${present}" >> "${MATRIX_CSV}"
done

# External repositories scan
for repo in "${repos[@]}"; do
  name="$(basename "${repo}" .git)"
  dir="${SRC_ROOT}/${name}"
  rm -rf "${dir}"
  if ! git clone --depth 1 "${repo}" "${dir}" >"${WORK_ROOT}/an_clone_${name}.log" 2>&1; then
    for feat in "${features[@]}"; do
      key="${feat%%|*}"
      rest="${feat#*|}"
      label="${rest%%|*}"
      echo "${RUN_TS},repo,${repo},,${key},${label},-1" >> "${MATRIX_CSV}"
    done
    continue
  fi
  commit="$(git -C "${dir}" rev-parse --short HEAD 2>/dev/null || true)"
  for feat in "${features[@]}"; do
    key="${feat%%|*}"
    rest="${feat#*|}"
    label="${rest%%|*}"
    regex="${rest#*|}"
    present="$(has_pattern "${dir}" "${regex}")"
    echo "${RUN_TS},repo,${repo},${commit},${key},${label},${present}" >> "${MATRIX_CSV}"
  done
done

# Build backlog report
{
  echo "# AIIR Improvement Backlog (AI-first)"
  echo
  echo "Generated at (UTC): \`${RUN_TS}\`"
  echo
  echo "Scope: compare AIIR (ai/server/docs) against features commonly found in sampled open repositories."
  echo
  echo "## Priority Candidates (missing in AIIR, common in repos)"
  printf "| Feature | Repos with feature | AIIR has feature | Priority | Action |\\n"
  printf "|---|---:|---:|---|---|\\n"

  for feat in "${features[@]}"; do
    key="${feat%%|*}"
    rest="${feat#*|}"
    label="${rest%%|*}"
    if is_excluded_feature "${key}"; then
      continue
    fi

    aiir_has="$(awk -F, -v k="${key}" '$2=="aiir" && $5==k {print $7; exit}' "${MATRIX_CSV}")"
    repo_yes="$(awk -F, -v k="${key}" '$2=="repo" && $5==k && $7==1 {c++} END {print c+0}' "${MATRIX_CSV}")"
    repo_total="$(awk -F, -v k="${key}" '$2=="repo" && $5==k && $7!=-1 {c++} END {print c+0}' "${MATRIX_CSV}")"

    if [[ "${aiir_has:-0}" == "0" && "${repo_yes}" -ge 2 ]]; then
      priority="high"
      action="design+implement in core/runtime/security and document in docs-tech"
    elif [[ "${aiir_has:-0}" == "0" && "${repo_yes}" -eq 1 ]]; then
      priority="medium"
      action="evaluate with targeted PoC and decide adoption"
    else
      continue
    fi
    echo "| ${label} | ${repo_yes}/${repo_total} | ${aiir_has:-0} | ${priority} | ${action} |"
  done

  echo
  echo "## Strengthen Existing Capabilities"
  printf "| Feature | Repos with feature | AIIR has feature | Action |\\n"
  printf "|---|---:|---:|---|\\n"
  for feat in "${features[@]}"; do
    key="${feat%%|*}"
    rest="${feat#*|}"
    label="${rest%%|*}"
    if is_excluded_feature "${key}"; then
      continue
    fi
    aiir_has="$(awk -F, -v k="${key}" '$2=="aiir" && $5==k {print $7; exit}' "${MATRIX_CSV}")"
    repo_yes="$(awk -F, -v k="${key}" '$2=="repo" && $5==k && $7==1 {c++} END {print c+0}' "${MATRIX_CSV}")"
    repo_total="$(awk -F, -v k="${key}" '$2=="repo" && $5==k && $7!=-1 {c++} END {print c+0}' "${MATRIX_CSV}")"
    if [[ "${aiir_has:-0}" == "1" && "${repo_yes}" -ge 2 ]]; then
      echo "| ${label} | ${repo_yes}/${repo_total} | ${aiir_has} | tighten tests, docs, and defaults for production hardening |"
    fi
  done

  echo
  echo "## Artifacts"
  echo "- Feature matrix CSV: \`${MATRIX_CSV}\`"
  echo "- Repo source list: \`${REPO_LIST_FILE}\`"
  if [[ -f "${EXCLUDE_FILE}" ]]; then
    echo "- Feature exclusions: \`${EXCLUDE_FILE}\`"
  fi
} > "${BACKLOG_MD}"

rm -rf "${WORK_ROOT}"

echo "analysis-done: ${MATRIX_CSV}"
echo "backlog-done: ${BACKLOG_MD}"
