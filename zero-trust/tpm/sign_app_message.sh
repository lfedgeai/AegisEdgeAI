#!/usr/bin/env bash
set -euo pipefail

export PREFIX="/opt/homebrew"
if [[ "$(uname)" == "Darwin" ]]; then
  export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
  export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Accept context file as parameter, default to app.ctx if not provided
KEY_CTX="${1:-$SCRIPT_DIR/app.ctx}"      # TPM key context for signing
# Message file is optional - use default if not provided
MESSAGE="${2:-$SCRIPT_DIR/appsig_info.bin}"    # Original message file

# Extract agent name from context file path for unique file names
AGENT_NAME=$(basename "$KEY_CTX" .ctx)

# Use agent-specific files only if not using default app.ctx
if [[ "$KEY_CTX" == "$SCRIPT_DIR/app.ctx" ]]; then
    # Use default file names
    SIGNATURE="$SCRIPT_DIR/appsig.bin"       # Output signature file
    DIGEST="$SCRIPT_DIR/appsig_info.hash"    # SHA-256 hash file (used if signing hash)
    APPSIG_INFO="$SCRIPT_DIR/appsig_info.bin" # Message file
else
    # Use agent-specific file names
    SIGNATURE="$SCRIPT_DIR/${AGENT_NAME}_appsig.bin"       # Output signature file
    DIGEST="$SCRIPT_DIR/${AGENT_NAME}_appsig_info.hash"    # SHA-256 hash file (used if signing hash)
    APPSIG_INFO="$SCRIPT_DIR/${AGENT_NAME}_appsig_info.bin" # Agent-specific message file
fi

# Validate that the context file exists
if [[ ! -f "$KEY_CTX" ]]; then
    echo "[ERROR] TPM context file not found: $KEY_CTX"
    exit 1
fi

echo "[INFO] Using TPM context file: $KEY_CTX"

# Copy message to target location (only if different)
if [[ "$MESSAGE" != "$APPSIG_INFO" ]]; then
    cp "$MESSAGE" "$APPSIG_INFO"
    echo "[INFO] Message copied to: $APPSIG_INFO"
else
    echo "[INFO] Message file already in correct location: $APPSIG_INFO"
fi

# Ensure the target file exists
if [[ ! -f "$APPSIG_INFO" ]]; then
    echo "[ERROR] Target message file not found: $APPSIG_INFO"
    exit 1
fi

# Flush TPM contexts
tpm2 flushcontext -t
tpm2 flushcontext -l
tpm2 flushcontext -s
echo "[INFO] TPM contexts flushed."

echo "[INFO] Generating SHA-256 hash of message to sign..."
openssl dgst -sha256 -binary < "$APPSIG_INFO" > "$DIGEST"
echo "[INFO] Signing precomputed hash with rsassa scheme..."
tpm2_sign -c "$KEY_CTX" -g sha256 --scheme rsassa -d "$DIGEST" -f plain -o "$SIGNATURE"

echo "[INFO] Signature generated: $SIGNATURE"

# Output signature and digest in the expected format
if [[ -f "$SIGNATURE" ]]; then
    # Convert signature to hex
    SIGNATURE_HEX=$(xxd -p "$SIGNATURE" | tr -d '\n')
    echo "Signature: $SIGNATURE_HEX"
fi

if [[ -f "$DIGEST" ]]; then
    # Convert digest to hex
    DIGEST_HEX=$(xxd -p "$DIGEST" | tr -d '\n')
    echo "Digest: $DIGEST_HEX"
fi
