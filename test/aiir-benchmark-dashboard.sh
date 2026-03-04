#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/var/www/aiir/test}"
LOG_FILE="${ROOT}/OPEN_REPO_TEST_LOG.csv"
LATEST_FILE="${ROOT}/OPEN_REPO_TEST_LATEST.csv"
OUT_MD="${ROOT}/OPEN_REPO_DASHBOARD.md"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "missing log file: $LOG_FILE" >&2
  exit 1
fi

now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
window_start="$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)"

if [[ ! -f "$LATEST_FILE" ]]; then
  tmp_latest="$(mktemp)"
  {
    head -n 1 "$LOG_FILE"
    awk -F, 'NR>1 {
      key=$2 FS $4;
      if (!(key in seen_ts) || $1 > seen_ts[key]) { seen_ts[key]=$1; seen_row[key]=$0 }
    } END { for (k in seen_row) print seen_row[k]; }' "$LOG_FILE" | sort -t, -k1,1 -k2,2
  } > "$tmp_latest"
  mv "$tmp_latest" "$LATEST_FILE"
fi

avg_latest="$(awk -F, 'NR>1 {sum+=$13; n++} END {if(n==0) print "0.00"; else printf "%.2f", sum/n}' "$LATEST_FILE")"
p50_latest="$(awk -F, 'NR>1 {print $13}' "$LATEST_FILE" | sort -n | awk '{a[NR]=$1} END {if(NR==0){print "0.00"} else if(NR%2==1){printf "%.2f", a[(NR+1)/2]} else {printf "%.2f", (a[NR/2]+a[NR/2+1])/2}}')"

tmp_7d="$(mktemp)"
{
  head -n 1 "$LOG_FILE"
  awk -F, -v ws="$window_start" 'NR>1 && $1 >= ws {print $0}' "$LOG_FILE"
} > "$tmp_7d"

avg_7d="$(awk -F, 'NR>1 {sum+=$13; n++} END {if(n==0) print "0.00"; else printf "%.2f", sum/n}' "$tmp_7d")"
p50_7d="$(awk -F, 'NR>1 {print $13}' "$tmp_7d" | sort -n | awk '{a[NR]=$1} END {if(NR==0){print "0.00"} else if(NR%2==1){printf "%.2f", a[(NR+1)/2]} else {printf "%.2f", (a[NR/2]+a[NR/2+1])/2}}')"

{
  echo "# AIIR Benchmark Dashboard"
  echo
  echo "Generated (UTC): \`${now_utc}\`"
  echo "Window start (7d, UTC): \`${window_start}\`"
  echo
  echo "## Summary"
  echo "- Latest set (dedup repo+commit): avg reduction=${avg_latest}% p50=${p50_latest}%"
  echo "- Last 7 days (all runs): avg reduction=${avg_7d}% p50=${p50_7d}%"
  echo
  echo "## Latest Top 10"
  echo "| Repo | Commit | Date (UTC) | Original MB | AIIR Net MB | Reduction | Note |"
  echo "|---|---|---:|---:|---:|---:|---|"
  awk -F, 'NR>1 {printf "%s,%s,%s,%s,%s,%s,%s\n", $13,$2,$4,$1,$6,$12,$14}' "$LATEST_FILE" \
    | sort -t, -k1,1nr \
    | head -n 10 \
    | awk -F, '{printf "| `%s` | `%s` | %s | %s | %s | %s%% | %s |\n", $2,$3,$4,$5,$6,$1,$7}'
  echo
  echo "## Latest Bottom 10"
  echo "| Repo | Commit | Date (UTC) | Original MB | AIIR Net MB | Reduction | Note |"
  echo "|---|---|---:|---:|---:|---:|---|"
  awk -F, 'NR>1 {printf "%s,%s,%s,%s,%s,%s,%s\n", $13,$2,$4,$1,$6,$12,$14}' "$LATEST_FILE" \
    | sort -t, -k1,1n \
    | head -n 10 \
    | awk -F, '{printf "| `%s` | `%s` | %s | %s | %s | %s%% | %s |\n", $2,$3,$4,$5,$6,$1,$7}'
  echo
  echo "## Files"
  echo "- Log: \`${LOG_FILE}\`"
  echo "- Latest: \`${LATEST_FILE}\`"
} > "$OUT_MD"

rm -f "$tmp_7d"

echo "dashboard-done: ${OUT_MD}"
