#!/bin/bash
# Quick rebuild of SPIRE Server only

set -e

echo "Rebuilding SPIRE Server..."
cd spire
rm -f bin/spire-server
go build -o bin/spire-server ./cmd/spire-server
echo "✅ Done! Binary: $(ls -lh bin/spire-server | awk '{print $5}')"
