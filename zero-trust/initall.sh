#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./initall.sh            # hardware TPM, force-evict by default
#   ./initall.sh --swtpm    # use swtpm emulator
#   ./initall.sh --no-evict # hardware TPM, but skip eviction

USE_SWTPM=false
FORCE_EVICT=true

for arg in "$@"; do
  case "$arg" in
    --swtpm)    USE_SWTPM=true ;;
    --no-evict) FORCE_EVICT=false ;;
  esac
done

cd tpm

# Clean up old artifacts
rm -f *.ctx *.pem *.pub *.priv *.bin *.sig *.out *.msg *.pcrs *.hash

if $USE_SWTPM; then
  echo "[INFO] Starting with swtpm emulator..."
  ./swtpm.sh
  sleep 1
else
  # Hardware TPM path
  if [[ -e /dev/tpmrm0 ]]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
  elif [[ -e /dev/tpm0 ]]; then
    export TPM2TOOLS_TCTI="device:/dev/tpm0"
  else
    echo "[ERROR] No TPM device found. Enable TPM2.0 in BIOS/UEFI." >&2
    exit 1
  fi
  echo "[INFO] Using hardware TPM via ${TPM2TOOLS_TCTI}"

  if $FORCE_EVICT; then
    echo "[INFO] Force-evicting all persistent handles..."
    ./evict-all.sh
    sleep 1
  else
    echo "[INFO] Skipping eviction of persistent handles."
  fi
fi

# Provision EK/AK and application keys
./tpm-ek-ak-persist.sh
sleep 1
./tpm-app-persist.sh
sleep 1

# Generate and verify a quote
./generate_quote.sh
sleep 1
./verify_quote.sh
sleep 1

# Sign and verify an application message
./sign_app_message.sh
sleep 1
./verify_app_message_signature.sh

cd ..

# Cleanup agents
sleep 1
./cleanup_all_agents.sh --force

