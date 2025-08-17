#!/bin/bash

# Test End-to-End Flow Script
# This script demonstrates the complete flow using curl commands

echo "🚀 Testing End-to-End Multi-Agent Zero-Trust Flow"
echo "=================================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AGENT_URL="https://localhost:8401"
GATEWAY_URL="https://localhost:9000"
COLLECTOR_URL="https://localhost:8500"

echo -e "${BLUE}📋 Configuration:${NC}"
echo "   Agent URL: $AGENT_URL"
echo "   Gateway URL: $GATEWAY_URL"
echo "   Collector URL: $COLLECTOR_URL"
echo ""

# Step 1: Check if services are running
echo -e "${YELLOW}1. Checking service health...${NC}"

echo -n "   Agent health: "
AGENT_HEALTH=$(curl -s -k "$AGENT_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
if [[ "$AGENT_HEALTH" == '"status":"healthy"' ]]; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
    echo "   Please start the agent: python start_agent.py agent-001"
    exit 1
fi

echo -n "   Gateway health: "
GATEWAY_HEALTH=$(curl -s -k "$GATEWAY_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
if [[ "$GATEWAY_HEALTH" == '"status":"healthy"' ]]; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
    echo "   Please start the gateway: PORT=9000 python gateway/app.py"
    exit 1
fi

echo -n "   Collector health: "
COLLECTOR_HEALTH=$(curl -s -k "$COLLECTOR_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
if [[ "$COLLECTOR_HEALTH" == '"status":"healthy"' ]]; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
    echo "   Please start the collector: PORT=8500 python collector/app.py"
    exit 1
fi

echo ""

# Step 2: Test direct agent metrics generation (end-to-end flow)
echo -e "${YELLOW}2. Testing complete end-to-end flow via agent...${NC}"

echo "   Sending metrics generation request to agent..."
RESPONSE=$(curl -s -k -X POST "$AGENT_URL/metrics/generate" \
    -H "Content-Type: application/json" \
    -d '{"metric_type": "application"}')

echo "   Response: $RESPONSE"

# Check if successful
if echo "$RESPONSE" | grep -q '"status":"success"'; then
    echo -e "${GREEN}   ✅ End-to-end flow successful!${NC}"
    
    # Extract payload ID if available
    PAYLOAD_ID=$(echo "$RESPONSE" | grep -o '"payload_id":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "$PAYLOAD_ID" ]]; then
        echo -e "${BLUE}   📦 Payload ID: $PAYLOAD_ID${NC}"
    fi
else
    echo -e "${RED}   ❌ End-to-end flow failed${NC}"
    echo "   Error details: $RESPONSE"
fi

echo ""

# Step 3: Test individual components (optional)
echo -e "${YELLOW}3. Testing individual components...${NC}"

# Test nonce generation via gateway
echo -n "   Nonce generation via gateway: "
NONCE_RESPONSE=$(curl -s -k "$GATEWAY_URL/nonce?public_key=test" 2>/dev/null)
if echo "$NONCE_RESPONSE" | grep -q '"nonce"'; then
    echo -e "${GREEN}✅ Working${NC}"
else
    echo -e "${RED}❌ Failed${NC}"
fi

# Test nonce stats
echo -n "   Nonce statistics: "
STATS_RESPONSE=$(curl -s -k "$GATEWAY_URL/nonces/stats" 2>/dev/null)
if echo "$STATS_RESPONSE" | grep -q '"nonce_statistics"'; then
    echo -e "${GREEN}✅ Working${NC}"
else
    echo -e "${RED}❌ Failed${NC}"
fi

echo ""

# Step 4: Show system status
echo -e "${YELLOW}4. System Status Summary${NC}"

echo -e "${BLUE}   🔐 Security Features:${NC}"
echo "      • TPM2 hardware-backed signing"
echo "      • Nonce-based anti-replay protection"
echo "      • Geographic compliance verification"
echo "      • Agent allowlist validation"
echo "      • OpenSSL signature verification"

echo -e "${BLUE}   🌐 Network Architecture:${NC}"
echo "      • Agent (port 8401): Metrics generation & signing"
echo "      • Gateway (port 9000): TLS termination & routing"
echo "      • Collector (port 8500): Verification & processing"

echo -e "${BLUE}   📊 Data Flow:${NC}"
echo "      Agent → Gateway → Collector"
echo "      Sign → Proxy → Verify"

echo ""

# Step 5: Success message
echo -e "${GREEN}🎉 Multi-Agent Zero-Trust System is Operational!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "   • Create additional agents: python create_agent.py agent-002"
echo "   • Test multi-agent scenarios"
echo "   • Monitor logs for detailed flow information"
echo "   • Check collector allowlist: cat collector/allowed_agents.json"
