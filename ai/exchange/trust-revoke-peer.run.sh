#!/usr/bin/env bash
set -euo pipefail

PEER_ID="${1:?peer-id-required}"
KEY_DIR="${AIIR_KEY_DIR:-/var/www/aiir/ai/keys}"
STATE_DIR="${AIIR_STATE_DIR:-/var/www/aiir/ai/state}"
TRUSTED_DIR="${KEY_DIR}/trusted"
REVOKED_FILE="${AIIR_REVOKED_PEERS_FILE:-${STATE_DIR}/revoked.peers}"
MODE_FILE="${AIIR_PEER_MODE_FILE:-${STATE_DIR}/peer.mode}"

[[ "$PEER_ID" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "invalid peer id"; exit 1; }

install -d -m 2750 -o root -g www-data "$TRUSTED_DIR"
install -d -m 2770 -o root -g www-data "$STATE_DIR"

rm -f "${TRUSTED_DIR}/${PEER_ID}.pub.pem"
touch "${REVOKED_FILE}"
chmod 0660 "${REVOKED_FILE}" || true
if ! grep -Fxq "${PEER_ID}" "${REVOKED_FILE}"; then
  printf '%s\n' "${PEER_ID}" >> "${REVOKED_FILE}"
fi

TRUSTED_COUNT="$(find "${TRUSTED_DIR}" -maxdepth 1 -type f -name '*.pub.pem' 2>/dev/null | wc -l)"
if [[ "${TRUSTED_COUNT}" -gt 0 ]]; then
  printf 'paired\n' > "${MODE_FILE}"
else
  printf 'isolated\n' > "${MODE_FILE}"
fi
chown root:www-data "${MODE_FILE}" "${REVOKED_FILE}" || true
chmod 0660 "${MODE_FILE}" || true

echo "trust-revoke-ok: peer=${PEER_ID} trusted=${TRUSTED_COUNT}"
