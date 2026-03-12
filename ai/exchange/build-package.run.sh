#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:?source-dir-required}"
OUT_DIR="${2:?out-dir-required}"
CORE_DIR="${3:-${AI_CORE_DIR:-/var/www/aiir/ai/core}}"
KEY_DIR="${AIIR_KEY_DIR:-/var/www/aiir/ai/keys}"
STATE_DIR="${AIIR_STATE_DIR:-/var/www/aiir/ai/state}"
NODE_ID_FILE="${AIIR_NODE_ID_FILE:-${STATE_DIR}/node.id}"
CODEC_ENV_FILE="${AIIR_CODEC_ENV_FILE:-/var/www/aiir/server/env/ai-codec.env}"
HEURISTICS_FILE="${AIIR_HEURISTICS_REGISTRY:-${STATE_DIR}/heuristics/web-heuristics.v1.csv}"

if [[ -f "$CODEC_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CODEC_ENV_FILE"
fi
: "${AIIR_CODEC_OPERATIONAL:=binary}"
: "${AIIR_CODEC_TEXT_FALLBACK:=base64}"
: "${AIIR_CODEC_HUMAN_EMERGENCY:=base32}"
[[ "$AIIR_CODEC_OPERATIONAL" == "binary" ]] || { echo "invalid AIIR_CODEC_OPERATIONAL (expected: binary)"; exit 1; }
[[ "$AIIR_CODEC_TEXT_FALLBACK" == "base64" ]] || { echo "invalid AIIR_CODEC_TEXT_FALLBACK (expected: base64)"; exit 1; }
[[ "$AIIR_CODEC_HUMAN_EMERGENCY" == "base32" ]] || { echo "invalid AIIR_CODEC_HUMAN_EMERGENCY (expected: base32)"; exit 1; }

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
  HAS_HEURISTICS=0
  HEURISTICS_SHA256=""
  if [[ -f "$HEURISTICS_FILE" ]]; then
    mkdir -p heuristics
    cp "$HEURISTICS_FILE" heuristics/web-heuristics.v1.csv
    HAS_HEURISTICS=1
    HEURISTICS_SHA256="$(sha256sum heuristics/web-heuristics.v1.csv | awk '{print $1}')"
  fi
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
  if [[ "$HAS_HEURISTICS" == "1" ]]; then
    sha256sum heuristics/web-heuristics.v1.csv >> package.sha256
  fi
  {
    echo "signer_id=${SIGNER_ID}"
    echo "key_id=${SIGN_KEY_ID}"
    echo "pub_sha256=${PUB_SHA256}"
    echo "signed_at=${SIGNED_AT}"
    echo "algo=sha256+rsa"
    echo "has_heuristics=${HAS_HEURISTICS}"
    echo "heuristics_sha256=${HEURISTICS_SHA256}"
  } > package.sig.meta
  {
    cat package.sig.meta
    echo "package_sha256_file=$(sha256sum package.sha256 | awk '{print $1}')"
  } > package.sig.payload
  openssl dgst -sha256 -sign "$SIGN_KEY" -out package.sig package.sig.payload
)
