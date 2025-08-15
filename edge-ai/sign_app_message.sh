#!/usr/bin/env bash
set -euo pipefail

# Configuration: adjust as needed
KEY_CTX="app.ctx"     # TPM key context for signing (your AppSK or other signing key)
MESSAGE="msg.bin"     # Input message file to sign
SIGNATURE="sig.bin"   # Output signature file

# Flush TPM transient objects and sessions to free memory
tpm2 flushcontext -t
tpm2 flushcontext -l
tpm2 flushcontext -s

echo "[INFO] TPM contexts flushed."

# Optional: You can uncomment and provide password here if your key requires authorization
# AUTH_PASS="" # e.g. AUTH_PASS="mysecret"
# AUTH_OPT=()
# if [[ -n "$AUTH_PASS" ]]; then
#   AUTH_OPT=(-p "$AUTH_PASS")
# fi

echo "[INFO] Signing message file $MESSAGE with key $KEY_CTX..."

# Sign the message file using SHA256 hash algorithm
# Pass authorization option if needed: "${AUTH_OPT[@]}"
tpm2_sign -c "$KEY_CTX" -g sha256 -o "$SIGNATURE" "$MESSAGE"

echo "[INFO] Signature generated: $SIGNATURE"

