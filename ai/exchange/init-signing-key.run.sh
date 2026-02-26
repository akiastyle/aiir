#!/usr/bin/env bash
set -euo pipefail

KEY_DIR="${AIIR_KEY_DIR:-/var/www/aiir/ai/keys}"
STATE_DIR="${AIIR_STATE_DIR:-/var/www/aiir/ai/state}"
NODE_ID_FILE="${AIIR_NODE_ID_FILE:-${STATE_DIR}/node.id}"

if [[ -n "${AIIR_NODE_ID:-}" ]]; then
  NODE_ID="${AIIR_NODE_ID}"
elif [[ -s "${NODE_ID_FILE}" ]]; then
  NODE_ID="$(tr -d '[:space:]' < "${NODE_ID_FILE}")"
else
  NODE_ID="$(openssl rand -hex 16)"
fi

LOCAL_DIR="${KEY_DIR}/local/${NODE_ID}"
TRUSTED_DIR="${KEY_DIR}/trusted"
PRIV="${AIIR_SIGN_PRIVATE_KEY:-${LOCAL_DIR}/signing_priv.pem}"
PUB="${AIIR_SIGN_PUBLIC_KEY:-${LOCAL_DIR}/signing_pub.pem}"

umask 077
install -d -m 2770 -o root -g www-data "$STATE_DIR"
install -d -m 2750 -o root -g www-data "$LOCAL_DIR"
install -d -m 2750 -o root -g www-data "$TRUSTED_DIR"

printf '%s\n' "$NODE_ID" > "$NODE_ID_FILE"
chown root:www-data "$NODE_ID_FILE"
chmod 0640 "$NODE_ID_FILE"

if [[ ! -s "$PRIV" || ! -s "$PUB" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$PRIV"
  openssl pkey -in "$PRIV" -pubout -out "$PUB"
fi

chown root:www-data "$PRIV" "$PUB"
chmod 0640 "$PRIV"
chmod 0644 "$PUB"
echo "key-init-ok: node=${NODE_ID} pub=${PUB}"
