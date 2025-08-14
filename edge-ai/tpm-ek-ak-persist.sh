#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
export SWTPM_PORT=2321
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=${SWTPM_PORT}"

EK_HANDLE=0x81010001
AK_HANDLE=0x8101000A

echo "[STEP] Using TPM2TOOLS_TCTI=$TPM2TOOLS_TCTI"
echo "[STEP] EK handle will be $EK_HANDLE"
echo "[STEP] AK handle will be $AK_HANDLE"

# --- HELPER: flush all transient & session handles ---
flush_all() {
  for cap in handles-transient handles-loaded-session handles-saved-session; do
    for h in $(tpm2 getcap "$cap" 2>/dev/null); do
      [[ "$h" == "-" ]] && continue
      if [[ "$h" =~ ^0x[0-9A-Fa-f]+$ ]]; then
        echo "[INFO] Flushing $cap handle $h"
        tpm2 flushcontext "$h"
      fi
    done
  done
}

# --- HELPER: safe evict ---
safe_evict() {
  local handle="$1"
  if tpm2 getcap handles-persistent | grep -q "$handle"; then
    echo "[INFO] Evicting existing persistent handle $handle"
    tpm2 evictcontrol -C o "$handle" || true
  else
    echo "[INFO] Handle $handle not listed; forcing eviction to clear phantom state"
    tpm2 evictcontrol -C o "$handle" || true
  fi
}

# --- 1. Start clean ---
echo "[STEP] Flushing transient/session handles..."
flush_all

# --- 2. Evict any existing EK/AK ---
echo "[STEP] Evicting existing EK/AK persistent handles (if any)..."
safe_evict "$EK_HANDLE"
safe_evict "$AK_HANDLE"

# --- 3. Create & persist EK ---
echo "[STEP] Creating EK..."
tpm2 createek -G rsa -c ek.ctx -u ek.pub
tpm2 evictcontrol -C o -c ek.ctx "$EK_HANDLE"

# --- 4. Flush again to free transient slots ---
echo "[STEP] Flushing again after EK creation..."
flush_all

# --- 5. Create & persist AK using persisted EK handle ---
echo "[STEP] Creating AK using EK handle $EK_HANDLE..."
tpm2 createak -C "$EK_HANDLE" -c ak.ctx \
  --hash-alg sha256 --signing-alg rsassa --key-alg rsa
tpm2 evictcontrol -C o -c ak.ctx "$AK_HANDLE"

# --- 6. Final state ---
echo "[STEP] Persistent handles now present:"
tpm2 getcap handles-persistent

