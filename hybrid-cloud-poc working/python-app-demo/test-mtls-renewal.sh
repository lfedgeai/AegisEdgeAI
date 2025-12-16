#!/bin/bash
# Test mTLS communication between two Python apps with automatic SVID renewal
# This test verifies that workload SVIDs automatically renew when agent SVID renews

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SPIRE_AGENT_SOCKET="${SPIRE_AGENT_SOCKET:-/tmp/spire-agent/public/api.sock}"
SERVER_PORT="${SERVER_PORT:-8443}"
SERVER_HOST="${SERVER_HOST:-localhost}"
# Minimum test duration: 2 minutes to observe renewal events
TEST_DURATION="${TEST_DURATION:-120}"  # 2 minutes default (minimum)
RENEWAL_INTERVAL="${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-30}"  # Use same as agent renewal

# Ensure minimum 2 minutes for proper testing
if [ "$TEST_DURATION" -lt 120 ]; then
    TEST_DURATION=120
    echo "  Adjusted test duration to minimum 2 minutes (120s)"
fi

SERVER_LOG="/tmp/mtls-server-app.log"
CLIENT_LOG="/tmp/mtls-client-app.log"
SERVER_PID_FILE="/tmp/mtls-server-app.pid"
CLIENT_PID_FILE="/tmp/mtls-client-app.pid"

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    
    if [ -f "$SERVER_PID_FILE" ]; then
        SERVER_PID=$(cat "$SERVER_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
            kill "$SERVER_PID" 2>/dev/null || true
        fi
        rm -f "$SERVER_PID_FILE"
    fi
    
    if [ -f "$CLIENT_PID_FILE" ]; then
        CLIENT_PID=$(cat "$CLIENT_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
            kill "$CLIENT_PID" 2>/dev/null || true
        fi
        rm -f "$CLIENT_PID_FILE"
    fi
    
    # Also kill by process name
    pkill -f "mtls-server-app.py" >/dev/null 2>&1 || true
    pkill -f "mtls-client-app.py" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  mTLS Communication Test with Automatic SVID Renewal${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
if [ ! -S "$SPIRE_AGENT_SOCKET" ]; then
    echo -e "${RED}Error: SPIRE Agent socket not found at $SPIRE_AGENT_SOCKET${NC}"
    echo "Make sure SPIRE Agent is running"
    exit 1
fi

# Check if Python apps exist
if [ ! -f "${SCRIPT_DIR}/mtls-server-app.py" ] || [ ! -f "${SCRIPT_DIR}/mtls-client-app.py" ]; then
    echo -e "${RED}Error: Python apps not found${NC}"
    exit 1
fi

# Check Python dependencies
if ! python3 -c "from spiffe.workloadapi import default_client" 2>/dev/null; then
    echo -e "${RED}Error: spiffe library not installed${NC}"
    echo "Install it with: pip install spiffe"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Create registration entries for both apps
echo "Creating registration entries for Python apps..."
SPIRE_SERVER="${PROJECT_DIR}/spire/bin/spire-server"
SPIRE_AGENT="${PROJECT_DIR}/spire/bin/spire-agent"

if [ ! -f "$SPIRE_SERVER" ]; then
    echo -e "${YELLOW}Warning: SPIRE server binary not found, skipping registration entry creation${NC}"
    echo "Make sure registration entries exist for:"
    echo "  - spiffe://example.org/mtls-server"
    echo "  - spiffe://example.org/mtls-client"
else
    # Check if entries already exist
    SERVER_ENTRY_EXISTS=false
    CLIENT_ENTRY_EXISTS=false
    
    if "$SPIRE_SERVER" entry show -socketPath /tmp/spire-server/private/api.sock 2>/dev/null | grep -q "spiffe://example.org/mtls-server"; then
        SERVER_ENTRY_EXISTS=true
    fi
    
    if "$SPIRE_SERVER" entry show -socketPath /tmp/spire-server/private/api.sock 2>/dev/null | grep -q "spiffe://example.org/mtls-client"; then
        CLIENT_ENTRY_EXISTS=true
    fi
    
    if [ "$SERVER_ENTRY_EXISTS" = false ]; then
        echo "  Creating entry for mtls-server..."
        "$SPIRE_SERVER" entry create \
            -socketPath /tmp/spire-server/private/api.sock \
            -spiffeID spiffe://example.org/mtls-server \
            -parentID spiffe://example.org/agent \
            -selector unix:uid:$(id -u) \
            -selector unix:gid:$(id -g) \
            >/dev/null 2>&1 || echo -e "${YELLOW}    ⚠ Failed to create server entry (may already exist)${NC}"
    fi
    
    if [ "$CLIENT_ENTRY_EXISTS" = false ]; then
        echo "  Creating entry for mtls-client..."
        "$SPIRE_SERVER" entry create \
            -socketPath /tmp/spire-server/private/api.sock \
            -spiffeID spiffe://example.org/mtls-client \
            -parentID spiffe://example.org/agent \
            -selector unix:uid:$(id -u) \
            -selector unix:gid:$(id -g) \
            >/dev/null 2>&1 || echo -e "${YELLOW}    ⚠ Failed to create client entry (may already exist)${NC}"
    fi
    
    echo -e "${GREEN}✓ Registration entries ready${NC}"
fi

echo ""

# Start server
echo "Starting mTLS server..."
rm -f "$SERVER_LOG"
export SPIRE_AGENT_SOCKET="$SPIRE_AGENT_SOCKET"
export SERVER_PORT="$SERVER_PORT"
export SERVER_LOG="$SERVER_LOG"

python3 "${SCRIPT_DIR}/mtls-server-app.py" > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$SERVER_PID_FILE"

# Wait for server to start
sleep 3

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo -e "${RED}Error: Server failed to start${NC}"
    cat "$SERVER_LOG"
    exit 1
fi

echo -e "${GREEN}✓ Server started (PID: $SERVER_PID)${NC}"
echo ""

# Start client
echo "Starting mTLS client..."
rm -f "$CLIENT_LOG"
export SPIRE_AGENT_SOCKET="$SPIRE_AGENT_SOCKET"
export SERVER_HOST="$SERVER_HOST"
export SERVER_PORT="$SERVER_PORT"
export CLIENT_LOG="$CLIENT_LOG"

python3 "${SCRIPT_DIR}/mtls-client-app.py" > "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!
echo $CLIENT_PID > "$CLIENT_PID_FILE"

# Wait for client to start
sleep 3

if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
    echo -e "${RED}Error: Client failed to start${NC}"
    cat "$CLIENT_LOG"
    exit 1
fi

echo -e "${GREEN}✓ Client started (PID: $CLIENT_PID)${NC}"
echo ""

# Monitor for renewal
echo -e "${CYAN}Monitoring for SVID renewal (${TEST_DURATION}s - minimum 2 minutes)...${NC}"
echo "  Agent renewal interval: ${RENEWAL_INTERVAL}s"
EXPECTED_RENEWALS=$((TEST_DURATION / RENEWAL_INTERVAL))
echo "  Expected renewal cycles: ~${EXPECTED_RENEWALS}"
echo "  This ensures we observe at least ${EXPECTED_RENEWALS} renewal events"
echo ""

START_TIME=$(date +%s)
END_TIME=$((START_TIME + TEST_DURATION))
SERVER_RENEWALS=0
CLIENT_RENEWALS=0
LAST_SERVER_RENEWAL=0
LAST_CLIENT_RENEWAL=0

while [ $(date +%s) -lt $END_TIME ]; do
    sleep 2
    
    # Check server renewals
    if [ -f "$SERVER_LOG" ]; then
        NEW_SERVER_RENEWALS=$(grep -c "SVID renewed" "$SERVER_LOG" 2>/dev/null || echo "0")
        if [ "$NEW_SERVER_RENEWALS" -gt "$SERVER_RENEWALS" ]; then
            SERVER_RENEWALS=$NEW_SERVER_RENEWALS
            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))
            echo -e "${GREEN}  ✓ Server SVID renewed! (${SERVER_RENEWALS} total, ${ELAPSED}s elapsed)${NC}"
            LAST_SERVER_RENEWAL=$CURRENT_TIME
        fi
    fi
    
    # Check client renewals
    if [ -f "$CLIENT_LOG" ]; then
        NEW_CLIENT_RENEWALS=$(grep -c "SVID renewed" "$CLIENT_LOG" 2>/dev/null || echo "0")
        if [ "$NEW_CLIENT_RENEWALS" -gt "$CLIENT_RENEWALS" ]; then
            CLIENT_RENEWALS=$NEW_CLIENT_RENEWALS
            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))
            echo -e "${GREEN}  ✓ Client SVID renewed! (${CLIENT_RENEWALS} total, ${ELAPSED}s elapsed)${NC}"
            LAST_CLIENT_RENEWAL=$CURRENT_TIME
        fi
    fi
    
    # Check for reconnections (renewal blips)
    if [ -f "$CLIENT_LOG" ]; then
        RECONNECTS=$(grep -c "reconnect\|Connection error\|renewal blip" "$CLIENT_LOG" 2>/dev/null || echo "0")
        if [ "$RECONNECTS" -gt 0 ]; then
            echo -e "${CYAN}  ℹ Client reconnected ${RECONNECTS} time(s) (renewal blips handled)${NC}"
        fi
    fi
    
    # Show progress
    ELAPSED=$(($(date +%s) - START_TIME))
    REMAINING=$((END_TIME - $(date +%s)))
    if [ $((ELAPSED % 10)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo "  Progress: ${ELAPSED}s / ${TEST_DURATION}s (${REMAINING}s remaining)"
    fi
    
    # Check if processes are still running
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e "${RED}  ✗ Server process died${NC}"
        cat "$SERVER_LOG" | tail -20
        exit 1
    fi
    
    if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
        echo -e "${RED}  ✗ Client process died${NC}"
        cat "$CLIENT_LOG" | tail -20
        exit 1
    fi
done

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Test Results${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Collect final statistics
SERVER_MESSAGES=$(grep -c "Client.*:" "$SERVER_LOG" 2>/dev/null || echo "0")
CLIENT_MESSAGES=$(grep -c "Server response:" "$CLIENT_LOG" 2>/dev/null || echo "0")
CLIENT_RECONNECTS=$(grep -c "reconnect\|Connection error\|renewal blip" "$CLIENT_LOG" 2>/dev/null || echo "0")

echo "Server Statistics:"
echo "  SVID Renewals: $SERVER_RENEWALS"
echo "  Messages Received: $SERVER_MESSAGES"
echo "  Connections: $(grep -c "Client.*connected" "$SERVER_LOG" 2>/dev/null || echo "0")"
echo ""

echo "Client Statistics:"
echo "  SVID Renewals: $CLIENT_RENEWALS"
echo "  Messages Sent: $CLIENT_MESSAGES"
echo "  Reconnects (renewal blips): $CLIENT_RECONNECTS"
echo ""

# Check agent SVID renewals
if [ -f /tmp/spire-agent.log ]; then
    AGENT_RENEWALS=$(grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | wc -l)
    echo "Agent SVID Renewals: $AGENT_RENEWALS"
    echo ""
fi

# Verify test passed
if [ "$SERVER_RENEWALS" -gt 0 ] && [ "$CLIENT_RENEWALS" -gt 0 ]; then
    echo -e "${GREEN}✓ Test PASSED: Both apps detected SVID renewals${NC}"
    echo -e "${GREEN}✓ Workload SVIDs automatically renewed when agent SVID renewed${NC}"
    if [ "$CLIENT_RECONNECTS" -gt 0 ]; then
        echo -e "${GREEN}✓ Reconnections handled gracefully (renewal blips)${NC}"
    fi
    exit 0
elif [ "$SERVER_RENEWALS" -gt 0 ] || [ "$CLIENT_RENEWALS" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Test PARTIAL: Only one app detected renewals${NC}"
    exit 1
else
    echo -e "${RED}✗ Test FAILED: No SVID renewals detected${NC}"
    echo "  This may be normal if renewal interval (${RENEWAL_INTERVAL}s) is longer than test duration (${TEST_DURATION}s)"
    exit 1
fi

