#!/usr/bin/env bash
set -euo pipefail

cd /var/www/aiir/ai/toolchain-native
make clean
make
