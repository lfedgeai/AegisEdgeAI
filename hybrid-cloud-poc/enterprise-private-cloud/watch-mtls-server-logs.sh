#!/bin/bash
# Watch mTLS server logs in real-time with key event highlighting
# Usage: ./watch-mtls-server-logs.sh

LOG_FILE="/tmp/mtls-server.log"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Disable colors if output is not a terminal
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    BLUE=""
    BOLD=""
    NC=""
fi

echo "=========================================="
echo "Watching mTLS Server Logs"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo "Key events highlighted:"
echo "  ${GREEN}✓${NC} Successful responses"
echo "  ${CYAN}🔌${NC} New client connections"
echo "  ${BLUE}📨${NC} HTTP requests"
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "Warning: Log file not found: $LOG_FILE"
    echo "Waiting for log file to be created..."
    while [ ! -f "$LOG_FILE" ]; do
        sleep 1
    done
    echo "Log file created, starting to watch..."
fi

# Initialize counters
REQUEST_COUNT=0
RESPONSE_COUNT=0
CONNECTION_COUNT=0

# Count existing events (only recent ones to avoid counting old logs)
if [ -f "$LOG_FILE" ]; then
    # Get file size and only count from last 1000 lines to avoid processing huge old logs
    REQUEST_COUNT=$(tail -1000 "$LOG_FILE" 2>/dev/null | grep -c 'HTTP GET\|HTTP POST' || echo "0")
    RESPONSE_COUNT=$(tail -1000 "$LOG_FILE" 2>/dev/null | grep -c 'Responded to client.*HTTP 200' || echo "0")
    CONNECTION_COUNT=$(tail -1000 "$LOG_FILE" 2>/dev/null | grep -c 'New TLS client connected\|Client.*connected from' || echo "0")
fi

echo -e "${CYAN}Current counts (from recent logs):${NC}"
echo -e "  ${BLUE}HTTP Requests: ${BOLD}$REQUEST_COUNT${NC}"
echo -e "  ${GREEN}Successful Responses: ${BOLD}$RESPONSE_COUNT${NC}"
echo -e "  ${CYAN}Client Connections: ${BOLD}$CONNECTION_COUNT${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}Starting from end of log file (showing new entries only)...${NC}"
echo ""

# Start from end of file and watch for new entries only (skip old logs)
tail -n 0 -f "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
    # Check for key events and highlight them
    if echo "$line" | grep -q 'Responded to client.*HTTP 200'; then
        RESPONSE_COUNT=$((RESPONSE_COUNT + 1))
        echo -e "${GREEN}${BOLD}>>> [Response #$RESPONSE_COUNT]${NC} ${GREEN}$line${NC}"
    elif echo "$line" | grep -qE 'New TLS client connected|Client.*connected from'; then
        CONNECTION_COUNT=$((CONNECTION_COUNT + 1))
        echo ""
        echo -e "${CYAN}${BOLD}>>> [New Connection #$CONNECTION_COUNT]${NC} ${CYAN}$line${NC}"
        echo ""
    elif echo "$line" | grep -qE 'HTTP GET|HTTP POST'; then
        REQUEST_COUNT=$((REQUEST_COUNT + 1))
        echo -e "${BLUE}${BOLD}>>> [Request #$REQUEST_COUNT]${NC} ${BLUE}$line${NC}"
    elif echo "$line" | grep -qE 'HTTP [45][0-9][0-9]|ERROR|error|failed'; then
        echo ""
        echo -e "${RED}${BOLD}>>> [Error]${NC} ${RED}$line${NC}"
        echo ""
    else
        echo "$line"
    fi
done

