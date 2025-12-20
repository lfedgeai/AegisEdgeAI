#!/bin/bash
# Simple test script for mTLS client
# Cleans up log files, sets up environment, and starts client in foreground

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Script directory (hybrid-cloud-poc root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Python app demo directory
PYTHON_APP_DIR="${SCRIPT_DIR}/python-app-demo"

echo "=========================================="
echo "mTLS Client Test Script"
echo "=========================================="
echo ""

# Step 1: Clean up existing processes and log files
echo -e "${YELLOW}Cleaning up existing processes and log files...${NC}"
# Kill any existing mTLS client processes
if pkill -f mtls-client-app.py 2>/dev/null; then
    sleep 1  # Give processes time to exit
    echo -e "${GREEN}✓ Killed existing mTLS client processes${NC}"
else
    echo -e "${GREEN}✓ No existing mTLS client processes found${NC}"
fi
# Clean up log files
rm -f /tmp/mtls-client-app.log
echo -e "${GREEN}✓ Log files cleaned${NC}"
echo ""

# Step 2: Set up environment variables
echo -e "${YELLOW}Setting up environment...${NC}"

# SPIRE configuration
export CLIENT_USE_SPIRE="${CLIENT_USE_SPIRE:-true}"
export SPIRE_AGENT_SOCKET="${SPIRE_AGENT_SOCKET:-/tmp/spire-agent/public/api.sock}"

# Server configuration (Envoy on on-prem)
# Default to current host IP if SERVER_HOST is not set
if [ -z "${SERVER_HOST:-}" ]; then
    # Detect current host IP address (excluding localhost/127.0.0.1)
    # Try hostname -I first (usually fastest and most reliable)
    CURRENT_HOST_IP=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i!~/^127\./) {print $i; exit}}')
    
    # Fallback to ip addr show if hostname -I didn't work or only returned 127.x.x.x
    if [ -z "$CURRENT_HOST_IP" ] || [[ "$CURRENT_HOST_IP" =~ ^127\. ]]; then
        CURRENT_HOST_IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -vE '^127\.' | head -1)
    fi
    
    if [ -z "$CURRENT_HOST_IP" ] || [[ "$CURRENT_HOST_IP" =~ ^127\. ]]; then
        echo "Error: Could not detect non-localhost IP address. Please set SERVER_HOST environment variable."
        exit 1
    fi
    export SERVER_HOST="$CURRENT_HOST_IP"
else
    export SERVER_HOST="$SERVER_HOST"
fi
export SERVER_PORT="${SERVER_PORT:-8080}"

# CA certificate for Envoy verification
export CA_CERT_PATH="${CA_CERT_PATH:-~/.mtls-demo/envoy-cert.pem}"

# Log file
export CLIENT_LOG_FILE="${CLIENT_LOG_FILE:-/tmp/mtls-client-app.log}"

echo -e "${GREEN}✓ Environment configured:${NC}"
echo "  CLIENT_USE_SPIRE=$CLIENT_USE_SPIRE"
echo "  SPIRE_AGENT_SOCKET=$SPIRE_AGENT_SOCKET"
echo "  SERVER_HOST=$SERVER_HOST"
echo "  SERVER_PORT=$SERVER_PORT"
echo "  CA_CERT_PATH=$CA_CERT_PATH"
echo "  CLIENT_LOG_FILE=$CLIENT_LOG_FILE"
echo ""

# Step 3: Verify prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if SPIRE agent socket exists (if using SPIRE)
if [ "$CLIENT_USE_SPIRE" = "true" ]; then
    if [ ! -S "$SPIRE_AGENT_SOCKET" ]; then
        echo -e "${YELLOW}⚠ Warning: SPIRE agent socket not found: $SPIRE_AGENT_SOCKET${NC}"
        echo "  Make sure SPIRE agent is running"
    else
        echo -e "${GREEN}✓ SPIRE agent socket found${NC}"
    fi
fi

# Check if CA certificate exists (if specified)
if [ -n "$CA_CERT_PATH" ] && [ "$CA_CERT_PATH" != "~/.mtls-demo/envoy-cert.pem" ]; then
    CA_CERT_EXPANDED="${CA_CERT_PATH/#\~/$HOME}"
    if [ ! -f "$CA_CERT_EXPANDED" ]; then
        echo -e "${YELLOW}⚠ Warning: CA certificate not found: $CA_CERT_EXPANDED${NC}"
    else
        echo -e "${GREEN}✓ CA certificate found${NC}"
    fi
fi

# Check if Python script exists
if [ ! -f "${PYTHON_APP_DIR}/mtls-client-app.py" ]; then
    echo "Error: mtls-client-app.py not found in $PYTHON_APP_DIR"
    exit 1
fi
echo -e "${GREEN}✓ Client script found${NC}"
echo ""

# Step 4: Start client in foreground
echo "=========================================="
echo -e "${GREEN}Starting mTLS client...${NC}"
echo "=========================================="
echo "Press Ctrl+C to stop"
echo ""

# Run the client from python-app-demo directory
cd "${PYTHON_APP_DIR}"
python3 mtls-client-app.py

