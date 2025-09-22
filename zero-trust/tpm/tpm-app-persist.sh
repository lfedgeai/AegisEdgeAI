#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Compile the C program if the binary doesn't exist
if [ ! -f "$SCRIPT_DIR/tpm-app-persist" ]; then
    echo "[INFO] Compiling tpm-app-persist C program..."
    make -C "$SCRIPT_DIR"
fi

# Execute the C program with all provided arguments
"$SCRIPT_DIR/tpm-app-persist" "$@"
