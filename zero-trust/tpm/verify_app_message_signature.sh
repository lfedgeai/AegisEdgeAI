#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Accept parameters for agent-specific files
PUBKEY="${1:-$SCRIPT_DIR/appsk_pubkey.pem}"      # Public key file (exported)
MESSAGE="${2:-$SCRIPT_DIR/appsig_info.bin}"      # Original signed message
SIGNATURE="${3:-$SCRIPT_DIR/appsig.bin}"         # Signature to verify

# Extract agent name from signature file path for unique hash file
AGENT_NAME=$(basename "$SIGNATURE" _appsig.bin)
HASHFILE="$SCRIPT_DIR/${AGENT_NAME}_appsig_info.hash"    # Temporary file for SHA-256 hash

echo "[INFO] Hashing the message with SHA-256..."
openssl dgst -sha256 -binary < "$MESSAGE" > "$HASHFILE"

echo "[INFO] Verifying signature with OpenSSL pkeyutl..."
openssl pkeyutl -verify -pubin -inkey "$PUBKEY" -sigfile "$SIGNATURE" -in "$HASHFILE" -pkeyopt digest:sha256

if [ $? -eq 0 ]; then
    echo "[INFO] Signature valid!"
    rm -f "$HASHFILE"
else
    echo "[ERROR] Signature verification failed!"
    rm -f "$HASHFILE"
    exit 1
fi


