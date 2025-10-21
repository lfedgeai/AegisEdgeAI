#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- CONFIG ---
export SWTPM_PORT=2321

# Detect architecture and OS for appropriate configuration
ARCH=$(uname -m)
OS=$(uname -s)

case "$OS" in
  Darwin)
    # macOS (both Intel and Apple Silicon)
    export PREFIX="/opt/homebrew"
    export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
    export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
    ;;
  Linux)
    # Linux (x86_64 and ARM64)
    case "$ARCH" in
      aarch64|arm64)
        # ARM64 Linux - may have custom installation paths
        export PREFIX="/usr/local"
        export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
        export PATH="${PREFIX}/bin:${PATH}"
        echo "[INFO] ARM64 Linux detected - using PREFIX=${PREFIX}"
        ;;
      *)
        # x86_64 and other Linux architectures
        export PREFIX="/usr"
        ;;
    esac
    export TPM2TOOLS_TCTI="${TPM2TOOLS_TCTI:-swtpm:host=127.0.0.1,port=${SWTPM_PORT}}"
    ;;
  *)
    echo "[WARN] Unknown OS: $OS - using default configuration"
    export PREFIX="/usr"
    export TPM2TOOLS_TCTI="${TPM2TOOLS_TCTI:-swtpm:host=127.0.0.1,port=${SWTPM_PORT}}"
    ;;
esac

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
tpm2 createek -G rsa -c "$SCRIPT_DIR/ek.ctx" -u "$SCRIPT_DIR/ek.pub"
tpm2 evictcontrol -C o -c "$SCRIPT_DIR/ek.ctx" "$EK_HANDLE"

# --- 4. Flush again to free transient slots ---
echo "[STEP] Flushing again after EK creation..."
flush_all

# --- 5. Create & persist AK using persisted EK handle ---
echo "[STEP] Creating AK using EK handle $EK_HANDLE..."
tpm2 createak -C "$EK_HANDLE" -c "$SCRIPT_DIR/ak.ctx" \
  --hash-alg sha256 --signing-alg rsassa --key-alg rsa
tpm2 evictcontrol -C o -c "$SCRIPT_DIR/ak.ctx" "$AK_HANDLE"

# --- 6. Export AK public key PEM (for verifier) ---
tpm2 flushcontext -t
echo "[STEP] Exporting AK public key for verification..."
tpm2_readpublic -c "$SCRIPT_DIR/ak.ctx" -f pem -o "$SCRIPT_DIR/ak_pub.pem"
echo "[SUCCESS] AK Public Key exported to $SCRIPT_DIR/ak_pub.pem"

# --- 7. Final state ---
echo "[STEP] Persistent handles now present:"
tpm2 getcap handles-persistent

