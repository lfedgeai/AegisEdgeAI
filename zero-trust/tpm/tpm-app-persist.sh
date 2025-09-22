#!/usr/bin/env bash
set -euo pipefail

# Parse command line arguments
FORCE=${1:-}
AGENT_CTX=${2:-}
AGENT_PUBKEY=${3:-}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define TPM handles
export AK_HANDLE="${AK_HANDLE:-0x8101000A}"
export APP_HANDLE="${APP_HANDLE:-0x8101000B}"

echo "[INFO] AK handle: $AK_HANDLE"
echo "[INFO] App handle: $APP_HANDLE"

# Use agent-specific files if provided, otherwise use defaults
if [[ -n "$AGENT_CTX" && -n "$AGENT_PUBKEY" ]]; then
    AGENT_CTX_PATH="$SCRIPT_DIR/$AGENT_CTX"
    AGENT_PUBKEY_PATH="$SCRIPT_DIR/$AGENT_PUBKEY"
    echo "[INFO] Using agent-specific TPM files:"
    echo "[INFO]   Context file: $AGENT_CTX_PATH"
    echo "[INFO]   Public key: $AGENT_PUBKEY_PATH"
else
    # Use default hardcoded values for simple testing
    AGENT_CTX_PATH="$SCRIPT_DIR/app.ctx"
    AGENT_PUBKEY_PATH="$SCRIPT_DIR/appsk_pubkey.pem"
    echo "[INFO] Using default TPM files:"
    echo "[INFO]   Context file: $AGENT_CTX_PATH"
    echo "[INFO]   Public key: $AGENT_PUBKEY_PATH"
fi

# [0] Optional force‑rotate AppSK
if [[ "$FORCE" == "--force" ]]; then
    echo "[FORCE] Evicting existing AppSK at $APP_HANDLE..."
    tpm2 evictcontrol -C o -c $APP_HANDLE || true
fi

# [1] Guard: skip if already exists
if tpm2 readpublic -c $APP_HANDLE >/dev/null 2>&1; then
    # Export the public key in PEM format from a TPM key context
    # Use agent-specific context and public key files
    KEY_CTX="$AGENT_CTX_PATH"
    PUB_PEM="$AGENT_PUBKEY_PATH"

    # Extract public part and convert to PEM (done on device with TPM)
    tpm2_readpublic -c "$KEY_CTX" -f pem -o "$PUB_PEM"
    echo "[INFO] Exported TPM public key to $PUB_PEM"

    echo "[INFO] AppSK already exists at $APP_HANDLE — skipping creation."
    exit 0
fi

# [2] Pre‑clean: flush all stale contexts
echo "[STEP] Flushing ALL stale contexts..."
tpm2 flushcontext --transient || true
tpm2 flushcontext --loaded-session || true
tpm2 flushcontext --saved-session || true

# [3] Create primary
echo "[STEP] Creating primary..."
tpm2 createprimary -C o -G rsa -c "$SCRIPT_DIR/primary.ctx"

# [4] Create AppSK blobs
echo "[STEP] Creating AppSK under primary..."
# Generate unique key files for this agent
AGENT_PUB_FILE="$SCRIPT_DIR/${AGENT_CTX%.ctx}.pub"
AGENT_PRIV_FILE="$SCRIPT_DIR/${AGENT_CTX%.ctx}.priv"

tpm2 create -C "$SCRIPT_DIR/primary.ctx" -G rsa -u "$AGENT_PUB_FILE" -r "$AGENT_PRIV_FILE"

# [5] Keep primary, drop other transients
echo "[STEP] Flushing all extra transients..."
PRIMARY_HANDLE=$(tpm2 getcap handles-transient | grep -Eo '0x[0-9a-fA-F]+$' | head -n1)
for h in $(tpm2 getcap handles-transient | grep -Eo '0x[0-9a-fA-F]+$'); do
    [[ "$h" != "$PRIMARY_HANDLE" ]] && tpm2 flushcontext "$h"
done

# [6] Load AppSK
echo "[STEP] Loading AppSK..."
tpm2 load -C "$SCRIPT_DIR/primary.ctx" -u "$AGENT_PUB_FILE" -r "$AGENT_PRIV_FILE" -c "$AGENT_CTX_PATH"

# Capture AppSK transient
APPSK_HANDLE=$(tpm2 getcap handles-transient | grep -Eo '0x[0-9a-fA-F]+$' | grep -v "$PRIMARY_HANDLE" | head -n1)
echo "[DEBUG] AppSK transient handle: $APPSK_HANDLE"

# [7] Persist AppSK
echo "[STEP] Persisting AppSK at $APP_HANDLE..."
tpm2 evictcontrol -C o -c "$APPSK_HANDLE" "$APP_HANDLE"

# [8] Cleanup transients
echo "[CLEANUP] Flushing primary and any remaining transients..."
tpm2 flushcontext "$PRIMARY_HANDLE" || true
for h in $(tpm2 getcap handles-transient | grep -Eo '0x[0-9a-fA-F]+$'); do
    tpm2 flushcontext "$h"
done

# [9] Show persistent state
echo "[DEBUG] Persistent handles now:"
tpm2 getcap handles-persistent

# [10] Optional residency proof — help‑driven syntax detection
if tpm2 readpublic -c $AK_HANDLE >/dev/null 2>&1; then
    echo "[STEP] Certifying AppSK with AK at $AK_HANDLE..."

    HELP=$(tpm2 certify --help 2>&1)

    if grep -q -- '-o' <<<"$HELP" && grep -q -- '-s' <<<"$HELP"; then
        echo "[INFO] Using -o/-s syntax for certify"
        tpm2 certify -C $AK_HANDLE -c $APP_HANDLE -g sha256 \
            -o "$SCRIPT_DIR/appsig_info.bin" -s "$SCRIPT_DIR/appsig_cert.sig"
    elif grep -q -- '--attest-file' <<<"$HELP"; then
        echo "[INFO] Using long-option syntax for certify"
        tpm2 certify -C $AK_HANDLE -c $APP_HANDLE -g sha256 \
            --attest-file "$SCRIPT_DIR/appsig_info.bin" \
            --signature-file "$SCRIPT_DIR/appsig_cert.sig"
    elif grep -q '^-m' <<<"$HELP"; then
        echo "[INFO] Using -m/-s syntax for certify (old)"
        tpm2 certify -C $AK_HANDLE -c $APP_HANDLE -g sha256 \
            -m "$SCRIPT_DIR/appsig_info.bin" -s "$SCRIPT_DIR/appsig_cert.sig"
    else
        echo "[WARN] Unknown certify syntax — not writing output files"
        exit 1
    fi

    echo "[INFO] Residency proof written: appsig_info.bin / appsig_cert.sig"
else
    echo "[WARN] No AK at $AK_HANDLE — skipping certify."
fi

echo "[SUCCESS] AppSK persisted at $APP_HANDLE."

# Export the public key in PEM format from a TPM key context
# Use agent-specific or default files
KEY_CTX="$AGENT_CTX_PATH"
PUB_PEM="$AGENT_PUBKEY_PATH"

# Extract public part and convert to PEM (done on device with TPM)
tpm2_readpublic -c "$KEY_CTX" -f pem -o "$PUB_PEM"
echo "[INFO] Exported TPM public key to $PUB_PEM"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tpm2 flushcontext -t
tpm2_certify -C "$SCRIPT_DIR/ak.ctx" -c "$AGENT_CTX_PATH" -g sha256 -o "$SCRIPT_DIR/app_certify.out" -s "$SCRIPT_DIR/app_certify.sig"
echo "[INFO] APP certification by AK complete"
