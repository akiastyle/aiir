#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-7788}"

curl -fsS "http://${HOST}:${PORT}/health"
echo
curl -fsS "http://${HOST}:${PORT}/ai/meta"
echo
