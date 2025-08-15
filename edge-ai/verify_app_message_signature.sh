#!/usr/bin/env bash
set -euo pipefail

# Configuration (update these as needed)
PUBKEY="appsk_pubkey.pem"      # Public key file (exported)
MESSAGE="appsig_info.bin"      # Original signed message
SIGNATURE="appsig.bin"         # Signature to verify
HASHFILE="appsig_info.hash"    # Temporary file for SHA-256 hash

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


