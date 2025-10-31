#!/usr/bin/env bash
set -euo pipefail

# Vars
export SWTPM_DIR="${SWTPM_DIR:-$HOME/.swtpm/ztpm}"
export SWTPM_PORT="${SWTPM_PORT:-2321}"
export SWTPM_CTRL="${SWTPM_CTRL:-2322}"

# Kill old swtpm
pkill -f "swtpm socket" || true
rm -rf "$SWTPM_DIR"
mkdir -p "$SWTPM_DIR"

# Start swtpm on TCP, detached, with logging
echo "[INFO] Launching swtpm on ports ${SWTPM_PORT}/${SWTPM_CTRL} with state dir ${SWTPM_DIR}"
nohup swtpm socket --tpm2 \
  --server type=tcp,port=${SWTPM_PORT} \
  --ctrl   type=tcp,port=${SWTPM_CTRL} \
  --tpmstate dir="${SWTPM_DIR}" \
  --flags not-need-init \
  >"${SWTPM_DIR}/swtpm.log" 2>&1 &

SWTPM_PID=$!
sleep 1

if ! kill -0 "$SWTPM_PID" 2>/dev/null; then
  echo "[ERROR] swtpm failed to start. Check ${SWTPM_DIR}/swtpm.log"
  exit 1
fi

# Tell tpm2-tools to use it
export PREFIX="/opt/homebrew"
if [[ "$(uname)" == "Darwin" ]]; then
  export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
  export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
else
  export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=${SWTPM_PORT}"
fi

# Initialise and test
echo "[INFO] Initialising TPM2 simulator..."
tpm2 startup -c
tpm2 getcap properties-fixed | head -5

echo "[INFO] swtpm is up (PID ${SWTPM_PID}, log at ${SWTPM_DIR}/swtpm.log)"

