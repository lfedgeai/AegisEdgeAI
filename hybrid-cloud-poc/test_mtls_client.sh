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

# We'll use mtls-client-app.py which already works

# Check if get_imei_imsi_huawei.sh exists
if [ ! -f "${SCRIPT_DIR}/get_imei_imsi_huawei.sh" ]; then
    echo "Error: get_imei_imsi_huawei.sh not found in $SCRIPT_DIR"
    exit 1
fi
echo -e "${GREEN}✓ IMEI/IMSI script found${NC}"
echo ""

# Step 4: Execute get_imei_imsi_huawei.sh ONCE at the start and check for specific values
# Note: This is executed only once, not for each HTTP request
echo "=========================================="
echo -e "${YELLOW}Checking IMEI/IMSI (executed once at start)...${NC}"
echo "=========================================="

# Execute get_imei_imsi_huawei.sh once and capture output
# Temporarily disable set -e to handle script failures gracefully
set +e
IMEI_OUTPUT=$(cd "${SCRIPT_DIR}" && timeout 10 ./get_imei_imsi_huawei.sh 2>&1)
IMEI_EXIT_CODE=$?
set -e

# Check if script failed or timed out
if [ $IMEI_EXIT_CODE -ne 0 ]; then
    if [ $IMEI_EXIT_CODE -eq 124 ]; then
        echo -e "${YELLOW}⚠ IMEI/IMSI script timed out (may be waiting for sudo password)${NC}"
    else
        echo -e "${YELLOW}⚠ IMEI/IMSI script failed (exit code: $IMEI_EXIT_CODE)${NC}"
    fi
fi

echo "$IMEI_OUTPUT"
echo ""

# Check if output contains the expected IMEI and IMSI
EXPECTED_IMEI="356345043865103"
EXPECTED_IMSI="214070610960475"
IMEI_FOUND=false
IMSI_FOUND=false

# Temporarily disable set -e for grep checks (grep returns non-zero if not found)
set +e
echo "$IMEI_OUTPUT" | grep -q "$EXPECTED_IMEI"
if [ $? -eq 0 ]; then
    IMEI_FOUND=true
    echo -e "${GREEN}✓ Expected IMEI found: $EXPECTED_IMEI${NC}"
else
    echo -e "${YELLOW}⚠ Expected IMEI not found: $EXPECTED_IMEI${NC}"
fi

echo "$IMEI_OUTPUT" | grep -q "$EXPECTED_IMSI"
if [ $? -eq 0 ]; then
    IMSI_FOUND=true
    echo -e "${GREEN}✓ Expected IMSI found: $EXPECTED_IMSI${NC}"
else
    echo -e "${YELLOW}⚠ Expected IMSI not found: $EXPECTED_IMSI${NC}"
fi
set -e

if [ "$IMEI_FOUND" = true ] && [ "$IMSI_FOUND" = true ]; then
    EXPECT_SUCCESS=true
    echo -e "${GREEN}✓ Both IMEI and IMSI match - expecting HTTP request to succeed${NC}"
else
    EXPECT_SUCCESS=false
    echo -e "${YELLOW}⚠ IMEI/IMSI mismatch - expecting 'Geo Claim Missing' response${NC}"
fi
echo ""

# Step 5: Send HTTP request and validate response
echo "=========================================="
echo -e "${GREEN}Sending HTTP request...${NC}"
echo "=========================================="

# Run mtls-client-app.py with timeout to capture first response
# Temporarily disable set -e to capture output even if request fails
set +e
cd "${PYTHON_APP_DIR}"

# Run mtls-client-app.py in background, capture output, and kill after first response
# Use timeout to ensure it doesn't run forever
HTTP_RESPONSE=$(timeout 10 python3 mtls-client-app.py 2>&1 | head -100)
HTTP_EXIT_CODE=$?

# If timeout killed it, that's fine - we got the response
if [ $HTTP_EXIT_CODE -eq 124 ]; then
    HTTP_EXIT_CODE=0  # Timeout is expected, treat as success for our purposes
fi
set -e

echo "$HTTP_RESPONSE"
echo ""

# Check the response based on expectations
# Temporarily disable set -e for grep checks
set +e
if [ "$EXPECT_SUCCESS" = true ]; then
    # Expect success - look for "SERVER ACK: HELLO" (partial match, e.g., "SERVER ACK: HELLO #1")
    echo "$HTTP_RESPONSE" | grep -qiE "SERVER ACK: HELLO"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ TEST PASSED: HTTP request succeeded as expected (got SERVER ACK: HELLO)${NC}"
        exit 0
    fi

    # Also check for 200 OK status as fallback
    echo "$HTTP_RESPONSE" | grep -q "HTTP/1.1 200\|HTTP/1.0 200\|200 OK"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ TEST PASSED: HTTP request succeeded as expected (200 OK)${NC}"
        exit 0
    fi

    echo "$HTTP_RESPONSE" | grep -qi "Geo Claim Missing"
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}⚠ TEST FAILED: Expected success (SERVER ACK: HELLO) but got 'Geo Claim Missing'${NC}"
        exit 1
    fi

    echo -e "${YELLOW}⚠ TEST FAILED: Expected success (SERVER ACK: HELLO) but got different response${NC}"
    exit 1
else
    # Expect "Geo Claim Missing" (typically 403 Forbidden)
    echo "$HTTP_RESPONSE" | grep -qi "Geo Claim Missing"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ TEST PASSED: Got 'Geo Claim Missing' as expected${NC}"
        exit 0
    fi

    # Also check for 403 status code
    echo "$HTTP_RESPONSE" | grep -q "HTTP/1.1 403\|HTTP/1.0 403\|403 Forbidden"
    if [ $? -eq 0 ]; then
        # Check if response body contains Geo Claim Missing (might be in body)
        if echo "$HTTP_RESPONSE" | grep -qi "Geo Claim Missing"; then
            echo -e "${GREEN}✓ TEST PASSED: Got 403 with 'Geo Claim Missing' as expected${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠ TEST PARTIAL: Got 403 but 'Geo Claim Missing' text not found in response${NC}"
            exit 1
        fi
    fi

    # Check if we got SERVER ACK: HELLO (success) when we expected failure
    echo "$HTTP_RESPONSE" | grep -qiE "SERVER ACK: HELLO"
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}⚠ TEST FAILED: Expected 'Geo Claim Missing' but request succeeded (got SERVER ACK: HELLO)${NC}"
        exit 1
    fi

    echo "$HTTP_RESPONSE" | grep -q "HTTP/1.1 200\|HTTP/1.0 200\|200 OK"
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}⚠ TEST FAILED: Expected 'Geo Claim Missing' but request succeeded (200 OK)${NC}"
        exit 1
    fi

    echo -e "${YELLOW}⚠ TEST FAILED: Expected 'Geo Claim Missing' but got different response${NC}"
    exit 1
fi
set -e
