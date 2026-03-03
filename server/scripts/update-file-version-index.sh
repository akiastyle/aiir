#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/var/www/aiir}"
OUT_CSV="${2:-${ROOT}/docs/FILE_VERSION_INDEX.csv}"
OUT_CHANGELOG="${3:-${ROOT}/docs/CHANGELOG_AIIR.md}"
MAX_LOG="${MAX_LOG:-40}"

if [[ ! -d "${ROOT}/.git" ]]; then
  echo "not a git repository: ${ROOT}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_CSV}")" "$(dirname "${OUT_CHANGELOG}")"

owner_scope_for_path() {
  local p="$1"
  if [[ "$p" == human/* ]]; then
    echo "human"
  elif [[ "$p" == ai/* || "$p" == server/* || "$p" == docs/* || "$p" == test/* ]]; then
    echo "ai"
  else
    echo "shared"
  fi
}

change_tag_for_path() {
  local p="$1"
  case "$p" in
    human/*) echo "human" ;;
    ai/runtime-server-native/*|server/env/*|server/systemd/*) echo "runtime" ;;
    ai/exchange/*|ai/keys/*|ai/state/*|ai/native-core/*) echo "security" ;;
    docs/*) echo "docs" ;;
    server/scripts/*|server/container/*|server/nginx/*|server/apache/*) echo "ops" ;;
    test/*) echo "analysis" ;;
    *) echo "core" ;;
  esac
}

{
  echo "path,last_commit,last_commit_date_utc,last_subject,owner_scope,change_tag"
  git -C "${ROOT}" ls-files | while IFS= read -r path; do
    if [[ -z "${path}" ]]; then
      continue
    fi
    read -r h d s < <(git -C "${ROOT}" log -n 1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format='%h %cd %s' -- "${path}")
    owner="$(owner_scope_for_path "${path}")"
    tag="$(change_tag_for_path "${path}")"
    subj="${s//\"/\"\"}"
    printf '"%s","%s","%s","%s","%s","%s"\n' "$path" "$h" "$d" "$subj" "$owner" "$tag"
  done
} > "${OUT_CSV}"

{
  echo "# AIIR Changelog (Tracked)"
  echo
  echo "Updated at (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo
  echo "## Recent Commits"
  git -C "${ROOT}" log -n "${MAX_LOG}" --date=format-local:%Y-%m-%dT%H:%M:%SZ --format='- `%h` %cd %s'
  echo
  echo "## Generated Files"
  echo "- \`${OUT_CSV}\`"
  echo "- \`${OUT_CHANGELOG}\`"
} > "${OUT_CHANGELOG}"

echo "version-index-updated: ${OUT_CSV}"
echo "changelog-updated: ${OUT_CHANGELOG}"
