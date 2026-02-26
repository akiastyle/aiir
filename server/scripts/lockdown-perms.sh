#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/aiir"

install -d -m 2770 -o root -g www-data "$ROOT/ai/state"
install -d -m 2770 -o root -g www-data "$ROOT/ai/log"
install -d -m 2750 -o root -g www-data "$ROOT/ai/keys"
install -d -m 2750 -o root -g www-data "$ROOT/ai/keys/local"
install -d -m 2750 -o root -g www-data "$ROOT/ai/keys/trusted"

chown -R root:www-data "$ROOT"

# Read-only by default for runtime user/group.
find "$ROOT" -type d -exec chmod 2755 {} +
find "$ROOT" -type f -exec chmod 0644 {} +

# Keep executable entry points.
find "$ROOT" -type f \( -name "*.sh" -o -name "*.run.sh" -o -name "aiird" -o -name "aiird-static" -o -name "ai-runtime-native" \) -exec chmod 0755 {} +

# Writable runtime state/log only.
find "$ROOT/ai/state" -type d -exec chmod 2770 {} +
find "$ROOT/ai/state" -type f -exec chmod 0660 {} +
find "$ROOT/ai/log" -type d -exec chmod 2770 {} +
find "$ROOT/ai/log" -type f -exec chmod 0660 {} +

# Signing keys: public readable, private restricted.
find "$ROOT/ai/keys/local" -type d -exec chmod 2750 {} + 2>/dev/null || true
find "$ROOT/ai/keys/trusted" -type d -exec chmod 2750 {} + 2>/dev/null || true
find "$ROOT/ai/keys/local" -type f -name "*_priv.pem" -exec chmod 0640 {} + 2>/dev/null || true
find "$ROOT/ai/keys/local" -type f -name "*_pub.pem" -exec chmod 0644 {} + 2>/dev/null || true
find "$ROOT/ai/keys/local" -type f -name "signing_priv.pem" -exec chmod 0640 {} + 2>/dev/null || true
find "$ROOT/ai/keys/local" -type f -name "signing_pub.pem" -exec chmod 0644 {} + 2>/dev/null || true
find "$ROOT/ai/keys/trusted" -type f -name "*.pem" -exec chmod 0644 {} + 2>/dev/null || true

echo "lockdown-ok: $ROOT"
