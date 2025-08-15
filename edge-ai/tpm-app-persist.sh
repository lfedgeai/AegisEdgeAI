#!/usr/bin/env bash
set -euo pipefail

FORCE=${1:-}

# [0] Optional force‑rotate AppSK
if [[ "$FORCE" == "--force" ]]; then
    echo "[FORCE] Evicting existing AppSK at $APP_HANDLE..."
    tpm2 evictcontrol -C o -c $APP_HANDLE || true
fi

# [1] Guard: skip if already exists
if tpm2 readpublic -c $APP_HANDLE >/dev/null 2>&1; then
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
tpm2 createprimary -C o -G rsa -c primary.ctx

# [4] Create AppSK blobs
echo "[STEP] Creating AppSK under primary..."
tpm2 create -C primary.ctx -G rsa -u app.pub -r app.priv

# [5] Keep primary, drop other transients
echo "[STEP] Flushing all extra transients..."
PRIMARY_HANDLE=$(tpm2 getcap handles-transient | grep -Eo '0x[0-9a-fA-F]+$' | head -n1)
for h in $(tpm2 getcap handles-transient | grep -Eo '0x[0-9a-fA-F]+$'); do
    [[ "$h" != "$PRIMARY_HANDLE" ]] && tpm2 flushcontext "$h"
done

# [6] Load AppSK
echo "[STEP] Loading AppSK..."
tpm2 load -C primary.ctx -u app.pub -r app.priv -c app.ctx

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
            -o appsig_info.bin -s appsig_cert.sig
    elif grep -q -- '--attest-file' <<<"$HELP"; then
        echo "[INFO] Using long-option syntax for certify"
        tpm2 certify -C $AK_HANDLE -c $APP_HANDLE -g sha256 \
            --attest-file appsig_info.bin \
            --signature-file appsig_cert.sig
    elif grep -q '^-m' <<<"$HELP"; then
        echo "[INFO] Using -m/-s syntax for certify (old)"
        tpm2 certify -C $AK_HANDLE -c $APP_HANDLE -g sha256 \
            -m appsig_info.bin -s appsig_cert.sig
    else
        echo "[WARN] Unknown certify syntax — not writing output files"
        exit 1
    fi

    echo "[INFO] Residency proof written: appsig_info.bin / appsig_cert.sig"
else
    echo "[WARN] No AK at $AK_HANDLE — skipping certify."
fi

echo "[SUCCESS] AppSK persisted at $APP_HANDLE."

