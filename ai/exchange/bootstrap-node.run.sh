#!/usr/bin/env bash
set -euo pipefail

ROOT="${AIIR_ROOT:-/var/www/aiir}"
STATE_DIR="${AIIR_STATE_DIR:-${ROOT}/ai/state}"
KEY_DIR="${AIIR_KEY_DIR:-${ROOT}/ai/keys}"
NODE_ID_FILE="${AIIR_NODE_ID_FILE:-${STATE_DIR}/node.id}"
MODE_FILE="${AIIR_PEER_MODE_FILE:-${STATE_DIR}/peer.mode}"
ONBOARD_DIR="${AIIR_ONBOARD_DIR:-${STATE_DIR}/onboarding}"

/var/www/aiir/ai/exchange/init-signing-key.run.sh >/dev/null

NODE_ID="$(tr -d '[:space:]' < "$NODE_ID_FILE")"
LOCAL_PUB="${KEY_DIR}/local/${NODE_ID}/signing_pub.pem"
TRUSTED_COUNT="$(find "${KEY_DIR}/trusted" -maxdepth 1 -type f -name '*.pub.pem' 2>/dev/null | wc -l)"

MODE="isolated"
if [[ "${TRUSTED_COUNT}" -gt 0 ]]; then
  MODE="paired"
fi

install -d -m 2770 -o root -g www-data "$STATE_DIR"
install -d -m 2770 -o root -g www-data "$ONBOARD_DIR"
printf '%s\n' "$MODE" > "$MODE_FILE"
chown root:www-data "$MODE_FILE"
chmod 0660 "$MODE_FILE"

PUB_SHA256="$(openssl pkey -pubin -in "$LOCAL_PUB" -outform DER | sha256sum | awk '{print $1}')"
cp "$LOCAL_PUB" "${ONBOARD_DIR}/${NODE_ID}.pub.pem"
chown root:www-data "${ONBOARD_DIR}/${NODE_ID}.pub.pem"
chmod 0644 "${ONBOARD_DIR}/${NODE_ID}.pub.pem"

cat > "${ONBOARD_DIR}/node.info" <<EOF
node_id=${NODE_ID}
mode=${MODE}
pub_sha256=${PUB_SHA256}
public_key=${ONBOARD_DIR}/${NODE_ID}.pub.pem
trusted_peers=${TRUSTED_COUNT}
generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

cat > "${ONBOARD_DIR}/security.checklist" <<'EOF'
1) Non abilitare AI_POLICY_ALLOW_OPS='*' senza un perimetro preciso.
2) Non abilitare AI_POLICY_ALLOW_DB_EXEC in bootstrap iniziale.
3) Accetta solo pacchetti firmati da peer presenti in ai/keys/trusted.
4) Verifica fingerprint chiave peer out-of-band prima di trust-add-peer.
5) Mantieni runtime in isolated mode fino a trust esplicito.
EOF

cat > "${ONBOARD_DIR}/next.steps" <<'EOF'
1) Condividi solo la chiave pubblica locale.
2) Registra peer con: /var/www/aiir/ai/exchange/trust-add-peer.run.sh <peer-id> <peer-pub.pem>
3) Sincronizza con: /var/www/aiir/ai/exchange/sync-core.run.sh build|apply ...
EOF

chown root:www-data "${ONBOARD_DIR}/node.info" "${ONBOARD_DIR}/security.checklist" "${ONBOARD_DIR}/next.steps"
chmod 0640 "${ONBOARD_DIR}/node.info" "${ONBOARD_DIR}/security.checklist" "${ONBOARD_DIR}/next.steps"

echo "bootstrap-node-ok: node=${NODE_ID} mode=${MODE} trusted=${TRUSTED_COUNT}"
