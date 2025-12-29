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

# Unified-Identity - Setup: Generate Python protobuf stubs from workload.proto

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROTO_DIR="$SCRIPT_DIR/../go-spiffe/proto"
PROTO_FILE="$PROTO_DIR/spiffe/workload/workload.proto"
OUTPUT_DIR="$SCRIPT_DIR/generated"

echo "Generating Python protobuf stubs..."
echo "  Proto file: $PROTO_FILE"
echo "  Output dir: $OUTPUT_DIR"
echo ""

if [ ! -f "$PROTO_FILE" ]; then
    echo "Error: Proto file not found at $PROTO_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check if grpc_tools is available
if ! python3 -m grpc_tools.protoc --version >/dev/null 2>&1; then
    echo "Error: grpc_tools not found"
    echo "Install it with: pip install grpcio-tools"
    exit 1
fi

# Generate Python protobuf stubs
echo "Running protoc..."
python3 -m grpc_tools.protoc \
    --proto_path="$PROTO_DIR" \
    --python_out="$OUTPUT_DIR" \
    --grpc_python_out="$OUTPUT_DIR" \
    "$PROTO_FILE"

if [ $? -eq 0 ]; then
    echo "✓ Protobuf stubs generated successfully in $OUTPUT_DIR"

    # Create __init__.py files to make it a proper Python package
    echo "Creating __init__.py files for package structure..."
    touch "$OUTPUT_DIR/__init__.py"
    touch "$OUTPUT_DIR/spiffe/__init__.py"
    touch "$OUTPUT_DIR/spiffe/workload/__init__.py"

    echo ""
    echo "Generated files:"
    find "$OUTPUT_DIR" -name "*.py" | head -5
    echo ""
    echo "✓ Package structure ready"
else
    echo "✗ Failed to generate protobuf stubs"
    exit 1
fi
