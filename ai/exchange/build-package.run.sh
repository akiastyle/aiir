#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:?source-dir-required}"
OUT_DIR="${2:?out-dir-required}"
CORE_DIR="${3:-${AI_CORE_DIR:-/var/www/aiir/ai/core}}"
KEY_DIR="${AIIR_KEY_DIR:-/var/www/aiir/ai/keys}"
STATE_DIR="${AIIR_STATE_DIR:-/var/www/aiir/ai/state}"
NODE_ID_FILE="${AIIR_NODE_ID_FILE:-${STATE_DIR}/node.id}"

cd /var/www/aiir/ai/toolchain-native
make
./aiir-toolchain build-package "$SRC_DIR" "$OUT_DIR" "$CORE_DIR"

/var/www/aiir/ai/exchange/init-signing-key.run.sh >/dev/null
SIGNER_ID="${AIIR_NODE_ID:-$(tr -d '[:space:]' < "$NODE_ID_FILE")}"
LOCAL_DIR="${KEY_DIR}/local/${SIGNER_ID}"
SIGN_KEY="${AIIR_SIGN_PRIVATE_KEY:-${LOCAL_DIR}/signing_priv.pem}"
SIGN_PUB="${AIIR_SIGN_PUBLIC_KEY:-${LOCAL_DIR}/signing_pub.pem}"
SIGN_KEY_ID="${AIIR_SIGN_KEY_ID:-${SIGNER_ID}-v1}"
PUB_SHA256="$(openssl pkey -pubin -in "$SIGN_PUB" -outform DER | sha256sum | awk '{print $1}')"
SIGNED_AT="${AIIR_SIGNED_AT_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

(
  cd "$OUT_DIR"
  rm -f package.sha256 package.sig package.sig.meta package.sig.payload
  sha256sum \
    manifest.aiir \
    files.table.aiir \
    paths.blob.aiir \
    content.table.aiir \
    source.blob.aiir \
    m2m.ai2ai.lite.table.aiir \
    m2m.ai2ai.lite.blob.aiir \
    m2m.ai2ai.source.adapt.table.aiir \
    m2m.ai2ai.source.adapt.ids.aiir \
    m2m.ai2ai.source.adapt.blob.aiir \
    m2m.db.packet.aiir \
    > package.sha256
  {
    echo "signer_id=${SIGNER_ID}"
    echo "key_id=${SIGN_KEY_ID}"
    echo "pub_sha256=${PUB_SHA256}"
    echo "signed_at=${SIGNED_AT}"
    echo "algo=sha256+rsa"
  } > package.sig.meta
  {
    cat package.sig.meta
    echo "package_sha256_file=$(sha256sum package.sha256 | awk '{print $1}')"
  } > package.sig.payload
  openssl dgst -sha256 -sign "$SIGN_KEY" -out package.sig package.sig.payload
)
