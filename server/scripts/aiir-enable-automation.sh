#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
MODE="auto"
DRY_RUN="0"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-enable-automation.sh [--mode auto|systemd|cron] [--dry-run]

notes:
  - systemd mode installs/enables:
    - aiir-state-backup.timer
    - aiir-smoke.timer
    - aiir-self-audit.timer
  - cron mode installs:
    - /etc/cron.d/aiir-maintenance from server/cron/aiir-maintenance
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2 ;;
    --dry-run)
      DRY_RUN="1"
      shift ;;
    -h|--help)
      usage
      exit 0 ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 1 ;;
  esac
done

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "dry-run: $*"
  else
    "$@"
  fi
}

enable_systemd() {
  local unit_dir="/etc/systemd/system"
  local units=(
    "aiir-state-backup.service"
    "aiir-state-backup.timer"
    "aiir-smoke.service"
    "aiir-smoke.timer"
    "aiir-self-audit.service"
    "aiir-self-audit.timer"
  )
  local u
  for u in "${units[@]}"; do
    run_cmd cp "${ROOT}/server/systemd/${u}" "${unit_dir}/${u}"
  done
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable --now aiir-state-backup.timer
  run_cmd systemctl enable --now aiir-smoke.timer
  run_cmd systemctl enable --now aiir-self-audit.timer
}

enable_cron() {
  local src="${ROOT}/server/cron/aiir-maintenance"
  local dst="/etc/cron.d/aiir-maintenance"
  run_cmd cp "$src" "$dst"
  run_cmd chmod 644 "$dst"
}

selected_mode="$MODE"
if [[ "$MODE" == "auto" ]]; then
  if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
    selected_mode="systemd"
  else
    selected_mode="cron"
  fi
fi

case "$selected_mode" in
  systemd)
    enable_systemd ;;
  cron)
    enable_cron ;;
  *)
    echo "invalid mode: $selected_mode" >&2
    exit 1 ;;
esac

cat <<EOF2
{"ok":1,"action":"enable_automation","mode":"${selected_mode}","dry_run":${DRY_RUN}}
EOF2
