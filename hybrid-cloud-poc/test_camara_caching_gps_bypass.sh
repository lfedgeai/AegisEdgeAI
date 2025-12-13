#!/bin/bash
# Standalone test for CAMARA caching and GPS bypass features
# Can be run independently once services are up

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    NC=""
fi

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  CAMARA Caching and GPS Bypass Integration Test               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if mobile location service is running
echo -e "${CYAN}Checking if mobile location service is running...${NC}"
if ! curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d '{}' http://localhost:5000/verify | grep -qE '200|404'; then
    echo -e "${RED}✗ Mobile location service is not running on port 5000${NC}"
    echo -e "${YELLOW}  Please start it first:${NC}"
    echo "    cd $REPO_ROOT/mobile-sensor-microservice"
    echo "    source .venv/bin/activate"
    echo "    export CAMARA_BYPASS=true  # or set CAMARA_BASIC_AUTH"
    echo "    python3 service.py --port 5000 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &"
    exit 1
fi
echo -e "${GREEN}✓ Mobile location service is running${NC}"
echo ""

# Clear log file for clean test
if [ -f /tmp/mobile-sensor.log ]; then
    echo "" > /tmp/mobile-sensor.log
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Test 1: CAMARA API Caching (First Call - Should Call API)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Making first verification request..."
FIRST_RESPONSE=$(curl -s -X POST http://localhost:5000/verify \
    -H "Content-Type: application/json" \
    -d '{"sensor_id": "12d1:1433"}' 2>&1)

if [ -n "$FIRST_RESPONSE" ]; then
    echo -e "${GREEN}✓ First call completed${NC}"
    echo "Response: $FIRST_RESPONSE"
    
    # Check logs for API call or cache miss
    echo ""
    echo "Checking logs for API call or cache miss..."
    sleep 1
    API_CALL_LOG=$(grep -E '\[API CALL\]|\[CACHE MISS\]|\[CACHE HIT\]|\[CACHING DISABLED\]' /tmp/mobile-sensor.log 2>/dev/null | tail -5 || echo "")
    if echo "$API_CALL_LOG" | grep -q "\[API CALL\]\|\[CACHE MISS\]"; then
        echo -e "${GREEN}✓ First call made API request (cache miss expected)${NC}"
        echo "$API_CALL_LOG" | sed 's/^/  /'
    elif echo "$API_CALL_LOG" | grep -q "\[CACHING DISABLED\]"; then
        echo -e "${YELLOW}⚠ Caching is disabled (CAMARA_BYPASS=true or TTL=0)${NC}"
        echo "$API_CALL_LOG" | sed 's/^/  /'
    else
        echo -e "${YELLOW}⚠ Could not verify API call in logs${NC}"
        if [ -n "$API_CALL_LOG" ]; then
            echo "$API_CALL_LOG" | sed 's/^/  /'
        fi
    fi
else
    echo -e "${RED}✗ First call failed${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Test 2: CAMARA API Caching (Second Call - Should Use Cache)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Waiting 2 seconds, then making second verification request..."
sleep 2

SECOND_RESPONSE=$(curl -s -X POST http://localhost:5000/verify \
    -H "Content-Type: application/json" \
    -d '{"sensor_id": "12d1:1433"}' 2>&1)

if [ -n "$SECOND_RESPONSE" ]; then
    echo -e "${GREEN}✓ Second call completed${NC}"
    echo "Response: $SECOND_RESPONSE"
    
    # Check logs for cache hit
    echo ""
    echo "Checking logs for cache hit..."
    sleep 1
    CACHE_HIT_LOG=$(grep -E '\[CACHE HIT\]|\[API CALL\]|\[CACHE EXPIRED\]' /tmp/mobile-sensor.log 2>/dev/null | tail -5 || echo "")
    if echo "$CACHE_HIT_LOG" | grep -q "\[CACHE HIT\]"; then
        echo -e "${GREEN}✓ Second call used cache (cache hit confirmed)${NC}"
        echo "$CACHE_HIT_LOG" | sed 's/^/  /'
    elif echo "$CACHE_HIT_LOG" | grep -q "\[API CALL\]"; then
        echo -e "${YELLOW}⚠ Second call still made API request (cache may not be working or expired)${NC}"
        echo "$CACHE_HIT_LOG" | sed 's/^/  /'
    else
        echo -e "${YELLOW}⚠ Could not verify cache behavior in logs${NC}"
        if [ -n "$CACHE_HIT_LOG" ]; then
            echo "$CACHE_HIT_LOG" | sed 's/^/  /'
        fi
    fi
else
    echo -e "${RED}✗ Second call failed${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Test 3: Location Verify Logging${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Checking for location verify logging..."
LOCATION_VERIFY_LOG=$(grep -E '\[LOCATION VERIFY\]' /tmp/mobile-sensor.log 2>/dev/null | tail -5 || echo "")
if [ -n "$LOCATION_VERIFY_LOG" ]; then
    echo -e "${GREEN}✓ Location verify logging present${NC}"
    echo "$LOCATION_VERIFY_LOG" | sed 's/^/  /'
else
    echo -e "${YELLOW}⚠ Could not find location verify logs${NC}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Test 4: Cache Configuration${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Checking cache TTL configuration..."
CACHE_CONFIG_LOG=$(grep -E 'CAMARA verify_location caching' /tmp/mobile-sensor.log 2>/dev/null | head -1 || echo "")
if [ -n "$CACHE_CONFIG_LOG" ]; then
    echo -e "${GREEN}✓ Cache configuration logged${NC}"
    echo "$CACHE_CONFIG_LOG" | sed 's/^/  /'
else
    echo -e "${YELLOW}⚠ Could not find cache configuration in logs (service may need restart)${NC}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Test 5: Cache Status in Logs${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Recent cache-related log entries:"
CACHE_LOGS=$(grep -E '\[CACHE|\[API|CAMARA verify_location' /tmp/mobile-sensor.log 2>/dev/null | tail -10 || echo "")
if [ -n "$CACHE_LOGS" ]; then
    echo "$CACHE_LOGS" | sed 's/^/  /'
else
    echo -e "${YELLOW}  No cache-related logs found${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Test Summary${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Tests completed. Check the results above."
echo ""
echo "To view full logs:"
echo "  tail -f /tmp/mobile-sensor.log"
echo ""
echo "To test GPS bypass (requires Envoy with WASM filter running):"
echo "  Check Envoy logs for GPS sensor bypass messages"
echo "  sudo tail -f /opt/envoy/logs/envoy.log | grep -i gps"
echo ""

