#!/bin/bash
# Watch Envoy logs in real-time with key event highlighting
# Usage: ./watch-envoy-logs.sh

LOG_FILE="/opt/envoy/logs/envoy.log"

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
echo "Watching Envoy Logs (WASM Filter Events Highlighted)"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo "Key events highlighted:"
echo "  ${GREEN}✓${NC} Sensor verification successful"
echo "  ${RED}✗${NC} Sensor verification failed"
echo "  ${CYAN}⚡${NC} Cache hit/expiry events"
echo "  ${BLUE}🔍${NC} Sensor ID extraction"
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
VERIFICATION_SUCCESS_COUNT=0
VERIFICATION_FAIL_COUNT=0
CACHE_HIT_COUNT=0

# Count existing events (only recent ones to avoid counting old logs)
if [ -f "$LOG_FILE" ]; then
    # Get file size and only count from last 1000 lines to avoid processing huge old logs
    VERIFICATION_SUCCESS_COUNT=$(tail -1000 "$LOG_FILE" 2>/dev/null | grep -c 'Sensor verification successful' 2>/dev/null || echo "0")
    VERIFICATION_FAIL_COUNT=$(tail -1000 "$LOG_FILE" 2>/dev/null | grep -c 'Sensor verification failed' 2>/dev/null || echo "0")
    CACHE_HIT_COUNT=$(tail -1000 "$LOG_FILE" 2>/dev/null | grep -c 'Using cached verification' 2>/dev/null || echo "0")
    # Ensure all counts are numeric (handle empty strings and strip whitespace)
    VERIFICATION_SUCCESS_COUNT=$(echo "${VERIFICATION_SUCCESS_COUNT:-0}" | tr -d '[:space:]')
    VERIFICATION_FAIL_COUNT=$(echo "${VERIFICATION_FAIL_COUNT:-0}" | tr -d '[:space:]')
    CACHE_HIT_COUNT=$(echo "${CACHE_HIT_COUNT:-0}" | tr -d '[:space:]')
    # Default to 0 if still empty or non-numeric
    [ -z "$VERIFICATION_SUCCESS_COUNT" ] && VERIFICATION_SUCCESS_COUNT=0
    [ -z "$VERIFICATION_FAIL_COUNT" ] && VERIFICATION_FAIL_COUNT=0
    [ -z "$CACHE_HIT_COUNT" ] && CACHE_HIT_COUNT=0
fi

echo -e "${CYAN}Current counts:${NC}"
echo -e "  ${GREEN}Verification successes: ${BOLD}$VERIFICATION_SUCCESS_COUNT${NC}"
echo -e "  ${RED}Verification failures: ${BOLD}$VERIFICATION_FAIL_COUNT${NC}"
echo -e "  ${CYAN}Cache hits: ${BOLD}$CACHE_HIT_COUNT${NC}"
echo "=========================================="
echo ""

# Watch log file and highlight key events
# Use stdbuf to ensure line-buffered output for faster refresh
stdbuf -oL -eL tail -f "$LOG_FILE" | while IFS= read -r line; do
    # Check for key events and highlight them
    if echo "$line" | grep -q 'Sensor verification successful'; then
        VERIFICATION_SUCCESS_COUNT=$((VERIFICATION_SUCCESS_COUNT + 1))
        echo ""
        echo -e "${GREEN}${BOLD}>>> [Verification Success #$VERIFICATION_SUCCESS_COUNT]${NC} ${GREEN}$line${NC}"
        echo ""
    elif echo "$line" | grep -q 'Sensor verification failed'; then
        VERIFICATION_FAIL_COUNT=$((VERIFICATION_FAIL_COUNT + 1))
        echo ""
        echo -e "${RED}${BOLD}>>> [Verification Failure #$VERIFICATION_FAIL_COUNT]${NC} ${RED}$line${NC}"
        echo ""
    elif echo "$line" | grep -q 'Using cached verification'; then
        CACHE_HIT_COUNT=$((CACHE_HIT_COUNT + 1))
        echo ""
        echo -e "${CYAN}${BOLD}>>> [Cache Hit #$CACHE_HIT_COUNT]${NC} ${CYAN}$line${NC}"
        echo ""
    elif echo "$line" | grep -q 'Cache expired\|No cache for sensor_id\|Dispatched blocking verification'; then
        echo ""
        echo -e "${BLUE}${BOLD}>>> [Cache/Verification Event]${NC} ${BLUE}$line${NC}"
        echo ""
    elif echo "$line" | grep -q 'Extracted sensor_id\|sensor_id:'; then
        echo -e "${YELLOW}$line${NC}"
    else
        echo "$line"
    fi
done

