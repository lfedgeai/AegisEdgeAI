#!/usr/bin/env bash
set -euo pipefail

# Use the same TCTI for all ESAPI/tpm2-tools binaries
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321"
export TCTI="swtpm:host=127.0.0.1,port=2321"   # if your C code reads TCTI

# Clean previous artifacts (ignore errors)
cd tpm
rm -f *.ctx *.pem *.pub *.priv *.bin *.sig *.out *.msg *.pcrs *.hash || true

# Start swtpm and wait until it responds
./swtpm.sh &
sleep 1
# Health check: query caps to ensure the simulator is actually ready
#tpm2_getrandom 4 >/dev/null 2>&1 || (echo "[ERROR] swtpm not ready"; exit 1)

./tpm-ek-ak-persist.sh
sleep 1
cd ..

# Work in plugin directory to keep paths consistent
cd ./spire-tpm-plugin
rm -f *.ctx *.pem *.pub *.priv *.out *.msg *.pcrs *.hash || true

# Build helpers (if needed)
./ma-app-persist
# Persist AppSK and save context (app.ctx) + PEM
./tpm-app-persist --force app.ctx appsk_pubkey.pem

sleep 1
./ma-app-selftest
# Self-test: load the context and read public to verify app.ctx is valid
./tpm-app-selftest app.ctx || { echo "[ERROR] app.ctx failed self-test"; exit 1; }

# Prepare a message to sign (example)
echo -n "hello-aegis" > appmsg.bin

sleep 1
# Sign: produce signature and sig-info assets explicitly
./ma-app-sign
./tpm-app-sign app.ctx appmsg.bin appsig.bin appsig_info.bin

sleep 1
# Optional: verify signature using PEM
openssl dgst -sha256 -verify appsk_pubkey.pem -signature appsig.bin appmsg.bin && \
  echo "[SUCCESS] OpenSSL verified signature"

