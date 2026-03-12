#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"
LOG_FILE="${AIIR_HEURISTICS_LOG_FILE:-${ROOT}/test/OPEN_REPO_FULL_LOG.csv}"
OUT_FILE="${AIIR_HEURISTICS_OUT_FILE:-${ROOT}/ai/state/heuristics/web-heuristics.v1.csv}"
MAX_ROWS="${AIIR_HEURISTICS_MAX_ROWS:-200}"

usage() {
  cat >&2 <<'USAGE'
usage:
  /var/www/aiir/server/scripts/aiir-heuristics-refresh.sh [--max-rows N] [--log <csv>] [--out <csv>]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-rows) MAX_ROWS="${2:-}"; shift 2 ;;
    --log) LOG_FILE="${2:-}"; shift 2 ;;
    --out) OUT_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ ! -f "$LOG_FILE" ]]; then
  echo "{\"ok\":0,\"err\":\"missing_log\",\"path\":\"${LOG_FILE}\"}"
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

tail -n "$((MAX_ROWS + 1))" "$LOG_FILE" > "$tmp"

read -r sum_html sum_css sum_js rows <<<"$(awk -F, '
  NR==1 { next }
  $29=="ok" {
    h += ($19+0)
    c += ($20+0)
    j += ($21+0)
    r += 1
  }
  END { printf "%.0f %.0f %.0f %d", h, c, j, r+0 }
' "$tmp")"

total_ops=$((sum_html + sum_css + sum_js))
if [[ "$rows" -le 0 || "$total_ops" -le 0 ]]; then
  sum_html=1
  sum_css=1
  sum_js=1
  total_ops=3
fi

w_html="$(awk -v x="$sum_html" -v t="$total_ops" 'BEGIN{printf "%.4f", 0.5 + (x/t)}')"
w_css="$(awk -v x="$sum_css" -v t="$total_ops" 'BEGIN{printf "%.4f", 0.5 + (x/t)}')"
w_js="$(awk -v x="$sum_js" -v t="$total_ops" 'BEGIN{printf "%.4f", 0.5 + (x/t)}')"
updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<EOF
version,scope,key,weight,samples,updated_utc
v1,ext,.html,${w_html},${rows},${updated_at}
v1,ext,.htm,${w_html},${rows},${updated_at}
v1,ext,.css,${w_css},${rows},${updated_at}
v1,ext,.scss,${w_css},${rows},${updated_at}
v1,ext,.sass,${w_css},${rows},${updated_at}
v1,ext,.js,${w_js},${rows},${updated_at}
v1,ext,.jsx,${w_js},${rows},${updated_at}
v1,ext,.ts,${w_js},${rows},${updated_at}
v1,ext,.tsx,${w_js},${rows},${updated_at}
v1,ext,.mjs,${w_js},${rows},${updated_at}
v1,ext,.cjs,${w_js},${rows},${updated_at}
EOF

cat <<EOF2
{"ok":1,"action":"heuristics_refresh","rows":${rows},"sum_html_ops":${sum_html},"sum_css_ops":${sum_css},"sum_js_ops":${sum_js},"out":"${OUT_FILE}","weights":{"html":${w_html},"css":${w_css},"js":${w_js}}}
EOF2
