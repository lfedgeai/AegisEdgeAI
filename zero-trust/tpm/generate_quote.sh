#!/usr/bin/env bash
set -euo pipefail

# TPM Quote Generation Script
# This script generates a TPM quote using the Attestation Key (AK)

# Load configuration from environment or use defaults
export SWTPM_PORT="${SWTPM_PORT:-2321}"
export TPM2TOOLS_TCTI="${TPM2TOOLS_TCTI:-swtpm:host=127.0.0.1,port=${SWTPM_PORT}}"
export AK_HANDLE="${AK_HANDLE:-0x8101000A}"

echo "[INFO] TPM Quote Generation Script"
echo "[INFO] TPM2TOOLS_TCTI: $TPM2TOOLS_TCTI"
echo "[INFO] AK handle: $AK_HANDLE"

# Get script directory for file operations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Generate a random nonce (32 bytes = 64 hex characters)
NONCE_HEX="${NONCE_HEX:-12}"  # Nonce used in quote generation
echo "[INFO] Using nonce: $NONCE_HEX"

# Check if AK exists
echo "[STEP] Checking if AK exists at handle $AK_HANDLE..."
if ! tpm2 readpublic -c "$AK_HANDLE" >/dev/null 2>&1; then
    echo "[ERROR] AK not found at handle $AK_HANDLE"
    echo "[ERROR] Please run tpm-ek-ak-persist.sh first to create the AK"
    exit 1
fi

# Flush TPM contexts
echo "[STEP] Flushing TPM contexts..."
tpm2 flushcontext -t

# Generate quote
echo "[STEP] Generating TPM quote..."
echo "[INFO] Quote will be saved to:"
echo "[INFO]   - Message: appsk_quote.msg"
echo "[INFO]   - Signature: appsk_quote.sig"
echo "[INFO]   - PCRs: appsk_quote.pcrs"

tpm2_quote -c "$SCRIPT_DIR/ak.ctx" \
           -l sha256:0,1 \
           -m "$SCRIPT_DIR/appsk_quote.msg" \
           -s "$SCRIPT_DIR/appsk_quote.sig" \
           -o "$SCRIPT_DIR/appsk_quote.pcrs" \
           -q "$NONCE_HEX" \
           -g sha256

if [ $? -eq 0 ]; then
    echo "[SUCCESS] TPM quote generated successfully"
    echo "[INFO] Quote files:"
    echo "[INFO]   - Message: appsk_quote.msg"
    echo "[INFO]   - Signature: appsk_quote.sig"
    echo "[INFO]   - PCRs: appsk_quote.pcrs"
    echo "[INFO]   - Nonce used: $NONCE_HEX"
else
    echo "[ERROR] Failed to generate TPM quote"
    exit 1
fi
