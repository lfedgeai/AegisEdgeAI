#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEY_CTX="$SCRIPT_DIR/app.ctx"            # TPM key context for signing
MESSAGE="$SCRIPT_DIR/appsig_info.bin"    # Original message file
SIGNATURE="$SCRIPT_DIR/appsig.bin"       # Output signature file
DIGEST="$SCRIPT_DIR/appsig_info.hash"    # SHA-256 hash file (used if signing hash)

# Flush TPM contexts
tpm2 flushcontext -t
tpm2 flushcontext -l
tpm2 flushcontext -s
echo "[INFO] TPM contexts flushed."

echo "[INFO] Generating SHA-256 hash of message to sign..."
openssl dgst -sha256 -binary < "$MESSAGE" > "$DIGEST"
echo "[INFO] Signing precomputed hash with rsassa scheme..."
tpm2_sign -c "$KEY_CTX" -g sha256 --scheme rsassa -d "$DIGEST" -f plain -o "$SIGNATURE"

echo "[INFO] Signature generated: $SIGNATURE"
