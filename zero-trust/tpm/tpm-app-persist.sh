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

echo "[INFO] AK handle: ${AK_HANDLE}"
echo "[INFO] App handle: ${APP_HANDLE}"

# Use agent-specific files if provided, otherwise use defaults
if [[ -n "${AGENT_CTX:-}" && -n "${AGENT_PUBKEY:-}" ]]; then
  AGENT_CTX_PATH="${SCRIPT_DIR}/${AGENT_CTX}"
  AGENT_PUBKEY_PATH="${SCRIPT_DIR}/${AGENT_PUBKEY}"
  echo "[INFO] Using agent-specific TPM files:"
  echo "[INFO]   Context file: ${AGENT_CTX_PATH}"
  echo "[INFO]   Public key:   ${AGENT_PUBKEY_PATH}"
else
  AGENT_CTX_PATH="${SCRIPT_DIR}/app.ctx"
  AGENT_PUBKEY_PATH="${SCRIPT_DIR}/appsk_pubkey.pem"
  echo "[INFO] Using default TPM files:"
  echo "[INFO]   Context file: ${AGENT_CTX_PATH}"
  echo "[INFO]   Public key:   ${AGENT_PUBKEY_PATH}"
fi

# [0] Optional force‑rotate AppSK
if [[ "${FORCE}" == "--force" ]]; then
  echo "[FORCE] Evicting existing AppSK at ${APP_HANDLE}..."
  tpm2 evictcontrol -C o -c "${APP_HANDLE}" || true
fi

# [1] Guard: if AppSK already persisted, export its public and exit
if tpm2_readpublic -c "${APP_HANDLE}" >/dev/null 2>&1; then
  echo "[INFO] AppSK already exists at ${APP_HANDLE} — exporting public and skipping creation."
  tpm2_readpublic -c "${APP_HANDLE}" -f pem -o "${AGENT_PUBKEY_PATH}"
  echo "[INFO] Exported TPM public key to ${AGENT_PUBKEY_PATH}"
  exit 0
fi

# [2] Pre‑clean: flush all stale contexts/sessions
echo "[STEP] Flushing ALL stale contexts..."
tpm2 flushcontext --transient-object || true
tpm2 flushcontext --loaded-session   || true
tpm2 flushcontext --saved-session    || true

# [3] Create primary (use context file, no handle scraping)
echo "[STEP] Creating primary..."
PRIMARY_CTX="${SCRIPT_DIR}/primary.ctx"
tpm2 createprimary -C o -G rsa -c "${PRIMARY_CTX}"
echo "[DEBUG] Primary context: ${PRIMARY_CTX}"

# [4] Create AppSK blobs under primary
echo "[STEP] Creating AppSK under primary..."
base_name="$(basename "${AGENT_CTX_PATH}" .ctx)"
AGENT_PUB_FILE="${SCRIPT_DIR}/${base_name}.pub"
AGENT_PRIV_FILE="${SCRIPT_DIR}/${base_name}.priv"

tpm2 create -C "${PRIMARY_CTX}" -G rsa -u "${AGENT_PUB_FILE}" -r "${AGENT_PRIV_FILE}"

# [5] Load AppSK
echo "[STEP] Loading AppSK..."
tpm2 load -C "${PRIMARY_CTX}" -u "${AGENT_PUB_FILE}" -r "${AGENT_PRIV_FILE}" -c "${AGENT_CTX_PATH}"
echo "[DEBUG] AppSK context: ${AGENT_CTX_PATH}"

# [6] Persist AppSK
echo "[STEP] Persisting AppSK at ${APP_HANDLE}..."
tpm2 evictcontrol -C o -c "${AGENT_CTX_PATH}" "${APP_HANDLE}"

# [7] Cleanup transients
echo "[CLEANUP] Flushing primary and any remaining transients..."
tpm2 flushcontext "${PRIMARY_CTX}" || true
tpm2 flushcontext --transient-object || true

# [8] Show persistent state
echo "[DEBUG] Persistent handles now:"
tpm2 getcap handles-persistent

# [9] Optional residency proof — syntax detection for tpm2_certify
if tpm2_readpublic -c "${AK_HANDLE}" >/dev/null 2>&1; then
  echo "[STEP] Certifying AppSK with AK at ${AK_HANDLE}..."

  HELP="$(tpm2_certify --help 2>&1 || true)"

  tpm2_certify -C "$SCRIPT_DIR/ak.ctx" -c "$AGENT_CTX_PATH" -g sha256 -o "$SCRIPT_DIR/appsig_info.bin" -s "$SCRIPT_DIR/app_certify.sig"

  echo "[INFO] Residency proof written: app_certify.out, app_certify.sig"
else
  echo "[WARN] No AK at ${AK_HANDLE} — skipping certify."
fi

# [10] Export public key for the persisted AppSK to the expected path
echo "[STEP] Exporting AppSK public as PEM..."
tpm2_readpublic -c "${APP_HANDLE}" -f pem -o "${AGENT_PUBKEY_PATH}"
echo "[INFO] Exported TPM public key to ${AGENT_PUBKEY_PATH}"

echo "[SUCCESS] AppSK persisted at ${APP_HANDLE} and public exported."

