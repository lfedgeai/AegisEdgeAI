#!/bin/bash
# Monitor SPIRE Agent and Python app logs for SVID renewal and blips

AGENT_LOG="/tmp/spire-agent.log"
SERVER_LOG="/tmp/mtls-server-app.log"
CLIENT_LOG="/tmp/mtls-client-app.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Monitoring SVID Renewal and Blips${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Monitoring:"
echo "  1. SPIRE Agent:    $AGENT_LOG"
echo "  2. Server workload: $SERVER_LOG"
echo "  3. Client workload: $CLIENT_LOG"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Track counts
AGENT_RENEWALS=0
SERVER_RENEWALS=0
CLIENT_RENEWALS=0
SERVER_BLIPS=0
CLIENT_BLIPS=0
CLIENT_RECONNECTS=0
START_TIME=$(date +%s)

# Function to check and display new events
check_logs() {
    # Check agent renewals
    if [ -f "$AGENT_LOG" ]; then
        NEW_AGENT=$(grep -c "Unified-Identity: Agent Unified SVID renewed\|Successfully rotated agent SVID" "$AGENT_LOG" 2>/dev/null || echo "0")
        NEW_AGENT=${NEW_AGENT:-0}
        if (( NEW_AGENT > AGENT_RENEWALS )); then
            AGENT_RENEWALS=$NEW_AGENT
            ELAPSED=$(($(date +%s) - START_TIME))
            echo -e "${GREEN}[$(date +%H:%M:%S)] Agent SVID Renewed! (Total: $AGENT_RENEWALS, ${ELAPSED}s elapsed)${NC}"
            grep "Unified-Identity: Agent Unified SVID renewed\|Successfully rotated agent SVID" "$AGENT_LOG" 2>/dev/null | tail -1 | sed 's/^/  /'
        fi
    fi
    
    # Check server renewals
    if [ -f "$SERVER_LOG" ]; then
        NEW_SERVER=$(grep -c "SVID RENEWAL DETECTED\|SVID renewed" "$SERVER_LOG" 2>/dev/null || echo "0")
        NEW_SERVER=${NEW_SERVER:-0}
        if (( NEW_SERVER > SERVER_RENEWALS )); then
            SERVER_RENEWALS=$NEW_SERVER
            ELAPSED=$(($(date +%s) - START_TIME))
            echo -e "${GREEN}[$(date +%H:%M:%S)] Server SVID Renewed! (Total: $SERVER_RENEWALS, ${ELAPSED}s elapsed)${NC}"
        fi
        
        # Check server blips
        NEW_SERVER_BLIPS=$(grep -c "RENEWAL BLIP\|renewal blip" "$SERVER_LOG" 2>/dev/null || echo "0")
        NEW_SERVER_BLIPS=${NEW_SERVER_BLIPS:-0}
        if (( NEW_SERVER_BLIPS > SERVER_BLIPS )); then
            SERVER_BLIPS=$NEW_SERVER_BLIPS
            ELAPSED=$(($(date +%s) - START_TIME))
            echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠ Server Renewal Blip Detected! (Total: $SERVER_BLIPS, ${ELAPSED}s elapsed)${NC}"
            grep "RENEWAL BLIP\|renewal blip" "$SERVER_LOG" 2>/dev/null | tail -1 | sed 's/^/  /'
        fi
    fi
    
    # Check client renewals
    if [ -f "$CLIENT_LOG" ]; then
        NEW_CLIENT=$(grep -c "SVID RENEWAL DETECTED\|SVID renewed" "$CLIENT_LOG" 2>/dev/null || echo "0")
        NEW_CLIENT=${NEW_CLIENT:-0}
        if (( NEW_CLIENT > CLIENT_RENEWALS )); then
            CLIENT_RENEWALS=$NEW_CLIENT
            ELAPSED=$(($(date +%s) - START_TIME))
            echo -e "${GREEN}[$(date +%H:%M:%S)] Client SVID Renewed! (Total: $CLIENT_RENEWALS, ${ELAPSED}s elapsed)${NC}"
        fi
        
        # Check client blips
        NEW_CLIENT_BLIPS=$(grep -c "RENEWAL BLIP\|renewal blip\|Connection error.*renewal" "$CLIENT_LOG" 2>/dev/null || echo "0")
        NEW_CLIENT_BLIPS=${NEW_CLIENT_BLIPS:-0}
        if (( NEW_CLIENT_BLIPS > CLIENT_BLIPS )); then
            CLIENT_BLIPS=$NEW_CLIENT_BLIPS
            ELAPSED=$(($(date +%s) - START_TIME))
            echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠ Client Renewal Blip Detected! (Total: $CLIENT_BLIPS, ${ELAPSED}s elapsed)${NC}"
            grep "RENEWAL BLIP\|renewal blip\|Connection error.*renewal" "$CLIENT_LOG" 2>/dev/null | tail -1 | sed 's/^/  /'
        fi
        
        # Check client reconnects (recovery)
        NEW_RECONNECTS=$(grep -c "Reconnected\|reconnect.*success\|Connection restored" "$CLIENT_LOG" 2>/dev/null || echo "0")
        NEW_RECONNECTS=${NEW_RECONNECTS:-0}
        if (( NEW_RECONNECTS > CLIENT_RECONNECTS )); then
            CLIENT_RECONNECTS=$NEW_RECONNECTS
            ELAPSED=$(($(date +%s) - START_TIME))
            echo -e "${GREEN}[$(date +%H:%M:%S)] ✓ Client Reconnected! (Total: $CLIENT_RECONNECTS, ${ELAPSED}s elapsed)${NC}"
            grep "Reconnected\|reconnect.*success\|Connection restored" "$CLIENT_LOG" 2>/dev/null | tail -1 | sed 's/^/  /'
        fi
    fi
}

# Main monitoring loop
while true; do
    check_logs
    sleep 2
    
    # Show summary every 30 seconds
    ELAPSED=$(($(date +%s) - START_TIME))
    if (( ELAPSED > 0 && ELAPSED % 30 == 0 )); then
        echo ""
        echo -e "${CYAN}[$(date +%H:%M:%S)] Summary (${ELAPSED}s elapsed):${NC}"
        echo "  Agent renewals: $AGENT_RENEWALS"
        echo "  Server renewals: $SERVER_RENEWALS | Blips: $SERVER_BLIPS"
        echo "  Client renewals: $CLIENT_RENEWALS | Blips: $CLIENT_BLIPS | Reconnects: $CLIENT_RECONNECTS"
        echo ""
    fi
done

