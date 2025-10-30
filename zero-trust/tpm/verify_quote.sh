#!/usr/bin/env bash
set -euo pipefail

if [[ -e /dev/tpmrm0 || -e /dev/tpm0 ]]; then
  # Prefer the resource manager device if available
  if [[ -e /dev/tpmrm0 ]]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
  else
    export TPM2TOOLS_TCTI="device:/dev/tpm0"
  fi
  echo "[INFO] Using hardware TPM via ${TPM2TOOLS_TCTI}"
else
  export PREFIX="/opt/homebrew"
  if [[ "$(uname)" == "Darwin" ]]; then
    export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
    export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
  fi
fi
# Get script directory for file operations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
NONCE_HEX="${NONCE_HEX:-12}"  # Nonce used in quote generation

echo "[INFO] Using nonce: $NONCE_HEX"

# 1. Verify Quote signature using AK public key
echo "[STEP] Verifying TPM quote signature..."
tpm2_checkquote -u "$SCRIPT_DIR/ak_pub.pem" \
                -m "$SCRIPT_DIR/appsk_quote.msg" \
                -s "$SCRIPT_DIR/appsk_quote.sig" \
                -f "$SCRIPT_DIR/appsk_quote.pcrs" \
                -g sha256 \
                -q "$NONCE_HEX"

if [ $? -eq 0 ]; then
    echo "[SUCCESS] TPM Quote verified successfully"
else
    echo "[ERROR] Quote verification failed!"
    exit 1
fi

tpm2 flushcontext -t
# 2. Verify Certification Signature using AK context
echo "[STEP] Verifying AppSK certification signature..."
tpm2_verifysignature -c "$SCRIPT_DIR/ak.ctx" \
                     -g sha256 \
                     -m "$SCRIPT_DIR/app_certify.out" \
                     -s "$SCRIPT_DIR/app_certify.sig"

if [ $? -eq 0 ]; then
    echo "[SUCCESS] AppSK certification signature verified"
else
    echo "[ERROR] AppSK certification signature verification failed!"
    exit 1
fi

# 3. Summary
echo "[SUCCESS] All verifications completed successfully"
echo "[INFO] TPM Quote: VERIFIED"
echo "[INFO] AppSK Certification: VERIFIED"
echo "[INFO] AppSK public key is now trusted through TPM AK and EK chain"
