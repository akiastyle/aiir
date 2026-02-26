#!/usr/bin/env bash
set -euo pipefail

PEER_ID="${1:?peer-id-required}"
PEER_PUB_FILE="${2:?peer-public-key-required}"
KEY_DIR="${AIIR_KEY_DIR:-/var/www/aiir/ai/keys}"
TRUSTED_DIR="${KEY_DIR}/trusted"
STATE_DIR="${AIIR_STATE_DIR:-/var/www/aiir/ai/state}"
MODE_FILE="${AIIR_PEER_MODE_FILE:-${STATE_DIR}/peer.mode}"
REVOKED_FILE="${AIIR_REVOKED_PEERS_FILE:-${STATE_DIR}/revoked.peers}"

[[ -s "$PEER_PUB_FILE" ]] || { echo "missing peer key: $PEER_PUB_FILE"; exit 1; }
[[ "$PEER_ID" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "invalid peer id"; exit 1; }

install -d -m 2750 -o root -g www-data "$TRUSTED_DIR"
TARGET="${TRUSTED_DIR}/${PEER_ID}.pub.pem"
cp "$PEER_PUB_FILE" "$TARGET"
chown root:www-data "$TARGET"
chmod 0644 "$TARGET"
if [[ -f "${REVOKED_FILE}" ]]; then
  tmp="$(mktemp)"
  grep -Fxv "${PEER_ID}" "${REVOKED_FILE}" > "${tmp}" || true
  cat "${tmp}" > "${REVOKED_FILE}"
  rm -f "${tmp}"
  chown root:www-data "${REVOKED_FILE}" || true
  chmod 0660 "${REVOKED_FILE}" || true
fi

FPR="$(openssl pkey -pubin -in "$TARGET" -outform DER | sha256sum | awk '{print $1}')"
install -d -m 2770 -o root -g www-data "$STATE_DIR"
printf 'paired\n' > "$MODE_FILE"
chown root:www-data "$MODE_FILE"
chmod 0660 "$MODE_FILE"
echo "trust-add-ok: peer=${PEER_ID} sha256=${FPR}"
