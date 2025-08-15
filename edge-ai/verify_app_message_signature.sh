#!/usr/bin/env bash
set -euo pipefail

# Configuration: adjust as needed
KEY_CTX="app.ctx"      # TPM key context for verification (public key part)
MESSAGE="msg.bin"      # Original message file
SIGNATURE="sig.bin"    # Signature file to verify

# Flush TPM transient objects and sessions
tpm2 flushcontext -t
tpm2 flushcontext -l
tpm2 flushcontext -s

echo "[INFO] TPM contexts flushed."

echo "[INFO] Verifying signature $SIGNATURE on message $MESSAGE using key $KEY_CTX..."

# Verify the signature over the original message
tpm2_verifysignature -c "$KEY_CTX" -g sha256 -m "$MESSAGE" -s "$SIGNATURE"

echo "[INFO] Signature verification successful."

