#!/bin/bash
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

# Install wasm32 target if not present
rustup target add wasm32-wasi 2>/dev/null || true

# Build WASM module
cargo build --target wasm32-wasi --release

# Copy to Envoy plugins directory
OUTPUT_DIR="/opt/envoy/plugins"
sudo mkdir -p "$OUTPUT_DIR"
sudo cp target/wasm32-wasi/release/sensor_verification_wasm.wasm "$OUTPUT_DIR/"
sudo chmod 644 "$OUTPUT_DIR/sensor_verification_wasm.wasm"

echo "✓ WASM filter built and installed to $OUTPUT_DIR/sensor_verification_wasm.wasm"

