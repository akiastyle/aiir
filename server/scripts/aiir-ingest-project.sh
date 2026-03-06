#!/usr/bin/env bash
set -euo pipefail

# Canonical AI-first command path.
# Legacy compatibility is preserved by delegating to the existing converter.
exec /var/www/aiir/server/scripts/aiir-convert-project.sh "$@"
