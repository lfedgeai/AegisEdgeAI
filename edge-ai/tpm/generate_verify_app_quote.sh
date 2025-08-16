#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nonce is 12
#tpm2_quote -c "$SCRIPT_DIR/app.ctx" -l sha256:0,1 -m "$SCRIPT_DIR/appsk_quote.msg" -s "$SCRIPT_DIR/appsk_quote.sig" -o "$SCRIPT_DIR/appsk_quote.pcrs" -q 12 -g sha256
tpm2 flushcontext -t
tpm2_checkquote -u "$SCRIPT_DIR/ak_pub.pem"   -m "$SCRIPT_DIR/appsk_quote.msg"   -s "$SCRIPT_DIR/appsk_quote.sig"   -f "$SCRIPT_DIR/appsk_quote.pcrs"   -g sha256   -q 12
