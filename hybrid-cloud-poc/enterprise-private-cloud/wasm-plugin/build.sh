#!/bin/bash

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build WASM filter for Envoy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building WASM filter..."

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo "Error: Rust/Cargo not found. Installing..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Source cargo env if it exists
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Check which WASM target is available
WASM_TARGET=""
if rustup target list --installed 2>/dev/null | grep -q "^wasm32-wasi$"; then
    WASM_TARGET="wasm32-wasi"
    echo "Using wasm32-wasi target"
elif rustup target list --installed 2>/dev/null | grep -q "^wasm32-wasip1$"; then
    WASM_TARGET="wasm32-wasip1"
    echo "Using wasm32-wasip1 target (wasm32-wasi not available)"
else
    # Try to install wasm32-wasi first
    echo "Installing wasm32-wasi target..."
    if rustup target add wasm32-wasi 2>&1 | grep -q "error\|Error"; then
        # If that fails, try wasm32-wasip1
        echo "wasm32-wasi not available, trying wasm32-wasip1..."
        if rustup target add wasm32-wasip1 2>&1 | grep -q "error\|Error"; then
            echo "Error: Could not install wasm32-wasi or wasm32-wasip1 target"
            echo "Available WASM targets:"
            rustc --print target-list 2>/dev/null | grep wasm || echo "Could not list targets"
            exit 1
        else
            WASM_TARGET="wasm32-wasip1"
        fi
    else
        WASM_TARGET="wasm32-wasi"
    fi
fi

if [ -z "$WASM_TARGET" ]; then
    echo "Error: No suitable WASM target found or installed."
    exit 1
fi

# Build WASM module
echo "Building for target: $WASM_TARGET"
cargo build --target "$WASM_TARGET" --release

# Copy to Envoy plugins directory
OUTPUT_DIR="/opt/envoy/plugins"
sudo mkdir -p "$OUTPUT_DIR"
sudo cp "target/$WASM_TARGET/release/sensor_verification_wasm.wasm" "$OUTPUT_DIR/"
sudo chmod 644 "$OUTPUT_DIR/sensor_verification_wasm.wasm"

echo "✓ WASM filter built and installed to $OUTPUT_DIR/sensor_verification_wasm.wasm"
