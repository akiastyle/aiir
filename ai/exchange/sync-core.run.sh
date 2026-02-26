#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode-required(build|apply)}"

case "$MODE" in
  build)
    SRC_DIR="${2:?source-dir-required}"
    OUT_PKG_DIR="${3:?package-dir-required}"
    CORE_DIR="${4:-${AI_CORE_DIR:-/var/www/aiir/ai/core}}"
    /var/www/aiir/ai/exchange/build-package.run.sh "$SRC_DIR" "$OUT_PKG_DIR" "$CORE_DIR"
    ;;
  apply)
    PKG_DIR="${2:?package-dir-required}"
    OUT_DIR="${3:?out-dir-required}"
    /var/www/aiir/ai/exchange/unpack-package.run.sh "$PKG_DIR" "$OUT_DIR"
    ;;
  *)
    echo "usage: $0 build <src-dir> <out-package-dir> [core-dir]" >&2
    echo "   or: $0 apply <package-dir> <out-dir>" >&2
    exit 1
    ;;
esac
