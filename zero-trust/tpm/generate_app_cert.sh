#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tpm2 flushcontext -t
tpm2_certify -C "$SCRIPT_DIR/ak.ctx" -c "$SCRIPT_DIR/app.ctx" -g sha256 -o "$SCRIPT_DIR/app_certify.out" -s "$SCRIPT_DIR/app_certify.sig"
