#!/bin/bash
# Watch mobile sensor service logs in real-time with key event highlighting
# Usage: ./watch-mobile-sensor-logs.sh

LOG_FILE="/tmp/mobile-sensor.log"

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
echo "Watching Mobile Sensor Service Logs"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo "Key events highlighted:"
echo "  ${GREEN}✓${NC} Verification completed (success)"
echo "  ${RED}✗${NC} Verification errors"
echo "  ${CYAN}📞${NC} CAMARA API calls"
echo "  ${BLUE}🔍${NC} Verification requests"
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
CAMARA_CALL_COUNT=0

# Count existing events
if [ -f "$LOG_FILE" ]; then
    VERIFICATION_SUCCESS_COUNT=$(grep -c 'Verification completed.*result=True' "$LOG_FILE" 2>/dev/null || echo "0")
    VERIFICATION_FAIL_COUNT=$(grep -cE 'Verification completed.*result=False|ERROR.*verification|ERROR.*CAMARA' "$LOG_FILE" 2>/dev/null || echo "0")
    CAMARA_CALL_COUNT=$(grep -c 'CAMARA.*API' "$LOG_FILE" 2>/dev/null || echo "0")
fi

echo -e "${CYAN}Current counts:${NC}"
echo -e "  ${GREEN}Verification successes: ${BOLD}$VERIFICATION_SUCCESS_COUNT${NC}"
echo -e "  ${RED}Verification failures: ${BOLD}$VERIFICATION_FAIL_COUNT${NC}"
echo -e "  ${CYAN}CAMARA API calls: ${BOLD}$CAMARA_CALL_COUNT${NC}"
echo "=========================================="
echo ""

# Watch log file and highlight key events
tail -f "$LOG_FILE" | while IFS= read -r line; do
    # Check for key events and highlight them
    if echo "$line" | grep -q 'Verification completed.*result=True'; then
        VERIFICATION_SUCCESS_COUNT=$((VERIFICATION_SUCCESS_COUNT + 1))
        echo ""
        echo -e "${GREEN}${BOLD}>>> [Verification Success #$VERIFICATION_SUCCESS_COUNT]${NC} ${GREEN}$line${NC}"
        echo ""
    elif echo "$line" | grep -qE 'Verification completed.*result=False|ERROR.*verification|ERROR.*CAMARA'; then
        VERIFICATION_FAIL_COUNT=$((VERIFICATION_FAIL_COUNT + 1))
        echo ""
        echo -e "${RED}${BOLD}>>> [Verification Failure #$VERIFICATION_FAIL_COUNT]${NC} ${RED}$line${NC}"
        echo ""
    elif echo "$line" | grep -qE 'CAMARA.*API|CAMARA authorize|CAMARA verify_location|CAMARA token'; then
        CAMARA_CALL_COUNT=$((CAMARA_CALL_COUNT + 1))
        echo ""
        echo -e "${CYAN}${BOLD}>>> [CAMARA API Call #$CAMARA_CALL_COUNT]${NC} ${CYAN}$line${NC}"
        echo ""
    elif echo "$line" | grep -q 'Received verification request for sensor_id'; then
        echo ""
        echo -e "${BLUE}${BOLD}>>> [Verification Request]${NC} ${BLUE}$line${NC}"
        echo ""
    elif echo "$line" | grep -q 'CAMARA_BYPASS enabled'; then
        echo -e "${YELLOW}$line${NC}"
    else
        echo "$line"
    fi
done

