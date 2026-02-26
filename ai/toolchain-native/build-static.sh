#!/usr/bin/env bash
set -euo pipefail

cd /var/www/aiir/ai/toolchain-native
CC="${CC:-musl-gcc}"
if ! command -v "$CC" >/dev/null 2>&1; then
  CC=gcc
fi

$CC -O2 -std=c11 -Wall -Wextra -static -s \
  -o aiird-static \
  aiir_toolchain.c \
  ../runtime-server-native/ai_runtime_native.c \
  ../native-core/aiir_core.c \
  ../native-core/aiir_policy.c \
  ../native-core/aiir_state.c \
  ../native-core/aiir_drift.c

ln -sf aiird-static aiir-toolchain-static
