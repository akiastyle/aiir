#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="${1:?package-dir-required}"
OUT_DIR="${2:?out-dir-required}"
KEY_DIR="${AIIR_KEY_DIR:-/var/www/aiir/ai/keys}"
STATE_DIR="${AIIR_STATE_DIR:-/var/www/aiir/ai/state}"
NODE_ID_FILE="${AIIR_NODE_ID_FILE:-${STATE_DIR}/node.id}"
REQUIRE_SIGNED="${AIIR_REQUIRE_SIGNED_PACKAGE:-1}"
TRUSTED_DIR="${KEY_DIR}/trusted"
REVOKED_FILE="${AIIR_REVOKED_PEERS_FILE:-${STATE_DIR}/revoked.peers}"
LEDGER_FILE="${AIIR_IMPORT_LEDGER_FILE:-${STATE_DIR}/import-ledger.log}"
ALLOW_REPLAY="${AIIR_ALLOW_REPLAY:-0}"
SIGNED_AT_MAX_AGE_SEC="${AIIR_SIGNED_AT_MAX_AGE_SEC:-86400}"
SIGNED_AT_MAX_FUTURE_SEC="${AIIR_SIGNED_AT_MAX_FUTURE_SEC:-300}"

if [[ "${REQUIRE_SIGNED}" != "0" ]]; then
  [[ -s "${PKG_DIR}/package.sha256" ]] || { echo "missing package.sha256"; exit 1; }
  [[ -s "${PKG_DIR}/package.sig" ]] || { echo "missing package.sig"; exit 1; }
  [[ -s "${PKG_DIR}/package.sig.meta" ]] || { echo "missing package.sig.meta"; exit 1; }
  [[ -s "${PKG_DIR}/package.sig.payload" ]] || { echo "missing package.sig.payload"; exit 1; }
  SIGNER_ID="$(awk -F= '$1=="signer_id"{print $2}' "${PKG_DIR}/package.sig.payload" | tail -n1)"
  PUB_HASH_META="$(awk -F= '$1=="pub_sha256"{print $2}' "${PKG_DIR}/package.sig.payload" | tail -n1)"
  SIGNED_AT="$(awk -F= '$1=="signed_at"{print $2}' "${PKG_DIR}/package.sig.payload" | tail -n1)"
  PAYLOAD_SHA="$(awk -F= '$1=="package_sha256_file"{print $2}' "${PKG_DIR}/package.sig.payload" | tail -n1)"
  [[ -n "${SIGNER_ID}" ]] || { echo "invalid package.sig.meta signer_id"; exit 1; }
  if [[ -f "${REVOKED_FILE}" ]] && grep -Fxq "${SIGNER_ID}" "${REVOKED_FILE}"; then
    echo "signer revoked: ${SIGNER_ID}"
    exit 1
  fi

  LOCAL_ID=""
  if [[ -s "${NODE_ID_FILE}" ]]; then
    LOCAL_ID="$(tr -d '[:space:]' < "${NODE_ID_FILE}")"
  fi
  if [[ "${SIGNER_ID}" == "${LOCAL_ID}" ]]; then
    SIGN_PUB="${AIIR_SIGN_PUBLIC_KEY:-${KEY_DIR}/local/${LOCAL_ID}/signing_pub.pem}"
  else
    SIGN_PUB="${AIIR_SIGN_PUBLIC_KEY:-${TRUSTED_DIR}/${SIGNER_ID}.pub.pem}"
  fi
  [[ -s "${SIGN_PUB}" ]] || { echo "missing trusted public key: ${SIGN_PUB}"; exit 1; }
  PUB_HASH_LOCAL="$(openssl pkey -pubin -in "$SIGN_PUB" -outform DER | sha256sum | awk '{print $1}')"
  [[ -z "${PUB_HASH_META}" || "${PUB_HASH_META}" == "${PUB_HASH_LOCAL}" ]] || { echo "pubkey hash mismatch"; exit 1; }
  (
    cd "$PKG_DIR"
    sha256sum -c package.sha256
    openssl dgst -sha256 -verify "$SIGN_PUB" -signature package.sig package.sig.payload
  )
  ACTUAL_SHA="$(sha256sum "${PKG_DIR}/package.sha256" | awk '{print $1}')"
  [[ -n "${PAYLOAD_SHA}" && "${PAYLOAD_SHA}" == "${ACTUAL_SHA}" ]] || { echo "package sha digest mismatch"; exit 1; }

  if [[ -n "${SIGNED_AT}" ]]; then
    SIGNED_TS="$(date -u -d "${SIGNED_AT}" +%s 2>/dev/null || true)"
    NOW_TS="$(date -u +%s)"
    [[ -n "${SIGNED_TS}" ]] || { echo "invalid signed_at"; exit 1; }
    MAX_AGE="${SIGNED_AT_MAX_AGE_SEC}"
    MAX_FUTURE="${SIGNED_AT_MAX_FUTURE_SEC}"
    if [[ "${MAX_AGE}" -gt 0 ]]; then
      AGE=$((NOW_TS - SIGNED_TS))
      if [[ "${AGE}" -gt "${MAX_AGE}" ]]; then
        echo "signed_at expired: age=${AGE}s"
        exit 1
      fi
    fi
    if [[ "${MAX_FUTURE}" -gt 0 ]]; then
      FUTURE=$((SIGNED_TS - NOW_TS))
      if [[ "${FUTURE}" -gt "${MAX_FUTURE}" ]]; then
        echo "signed_at too far in future: +${FUTURE}s"
        exit 1
      fi
    fi
  else
    echo "missing signed_at"
    exit 1
  fi
  if [[ "${ALLOW_REPLAY}" != "1" ]]; then
    install -d -m 2770 -o root -g www-data "${STATE_DIR}" || true
    touch "${LEDGER_FILE}"
    chmod 0660 "${LEDGER_FILE}" || true
    SIG_HASH="$(sha256sum "${PKG_DIR}/package.sig" | awk '{print $1}')"
    PKG_HASH="$(sha256sum "${PKG_DIR}/package.sha256" | awk '{print $1}')"
    ENTRY="sig=${SIG_HASH}|pkg=${PKG_HASH}|signer=${SIGNER_ID}"
    if command -v flock >/dev/null 2>&1; then
      exec 9>>"${LEDGER_FILE}"
      flock -x 9
      if grep -Fq "${ENTRY}" "${LEDGER_FILE}"; then
        echo "replay blocked: ${SIGNER_ID}"
        exit 1
      fi
      printf 'ts=%s|%s|signed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${ENTRY}" "${SIGNED_AT}" >> "${LEDGER_FILE}"
      flock -u 9
      exec 9>&-
    else
      if grep -Fq "${ENTRY}" "${LEDGER_FILE}"; then
        echo "replay blocked: ${SIGNER_ID}"
        exit 1
      fi
      printf 'ts=%s|%s|signed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${ENTRY}" "${SIGNED_AT}" >> "${LEDGER_FILE}"
    fi
  fi
  echo "package-verify-ok: signer=${SIGNER_ID}"
fi

cd /var/www/aiir/ai/toolchain-native
make
./aiir-toolchain unpack-package "$PKG_DIR" "$OUT_DIR"
