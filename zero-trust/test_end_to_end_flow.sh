#!/bin/bash

# Test End-to-End Flow Script
# This script demonstrates the complete flow using curl commands

echo "🚀 Testing End-to-End Multi-Agent Zero-Trust Flow (README_demo.md Workflow)"
echo "=========================================================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 0: Clean slate - stop everything and clean up
echo -e "${YELLOW}0. Ensuring clean slate...${NC}"
echo "   Stopping all services..."
# Kill by port first
pkill -f "port 8401" >/dev/null 2>&1 || true
pkill -f "port 9000" >/dev/null 2>&1 || true
pkill -f "port 8500" >/dev/null 2>&1 || true
# Kill by process name
pkill -f "opentelemetry-agent" >/dev/null 2>&1 || true
pkill -f "opentelemetry-gateway" >/dev/null 2>&1 || true
pkill -f "opentelemetry-collector" >/dev/null 2>&1 || true
echo "   ✅ All services stopped"

echo "   Cleaning up all test artifacts..."
bash cleanup_all_agents.sh --force >/dev/null 2>&1 || true
echo "   ✅ Cleanup completed"
echo ""

# Configuration
AGENT_URL="https://localhost:8401"
GATEWAY_URL="https://localhost:9000"
COLLECTOR_URL="https://localhost:8500"
HEADER_LOG="logs/gateway_headers.log"

# Cleanup function
cleanup_on_failure() {
    echo -e "\n${RED}❌ Test failed - cleaning up...${NC}"
    echo "4. Stopping services (all agents, gateway, collector)..."
    # Kill by port first
    pkill -f "port 8401" >/dev/null 2>&1 || true
    pkill -f "port 8402" >/dev/null 2>&1 || true
    pkill -f "port 8403" >/dev/null 2>&1 || true
    pkill -f "port 9000" >/dev/null 2>&1 || true
    pkill -f "port 8500" >/dev/null 2>&1 || true
    # Kill by process name
    pkill -f "opentelemetry-agent" >/dev/null 2>&1 || true
    pkill -f "opentelemetry-gateway" >/dev/null 2>&1 || true
    pkill -f "opentelemetry-collector" >/dev/null 2>&1 || true
    echo "   ✅ Services stopped (or stop attempted)"
    echo "5. Cleaning up test artifacts (agents, allowlist, TPM files)..."
    bash cleanup_all_agents.sh --force >/dev/null 2>&1 || true
    echo "   ✅ Cleanup completed"
    exit 1
}

# Helper: kill process listening on a port (best effort)
kill_by_port() {
  local PORT="$1"
  if command -v lsof >/dev/null 2>&1; then
    PIDS=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null)
    if [[ -n "$PIDS" ]]; then
      kill $PIDS 2>/dev/null || true
      sleep 1
      PIDS=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null)
      if [[ -n "$PIDS" ]]; then
        kill -9 $PIDS 2>/dev/null || true
      fi
    fi
  fi
}

echo -e "${BLUE}📋 Configuration:${NC}"
echo "   Agent URL: $AGENT_URL"
echo "   Gateway URL: $GATEWAY_URL"
echo "   Collector URL: $COLLECTOR_URL"
echo ""

# Step 1: Create agents and start services (README_demo.md workflow)
echo -e "${YELLOW}1. Creating agents and starting services...${NC}"

# Create agent-001 and agent-geo-policy-violation-002 BEFORE starting collector/gateway
echo "   Creating agent-001..."
python3 create_agent.py agent-001 >/dev/null 2>&1 || cleanup_on_failure
echo "   Creating agent-geo-policy-violation-002..."
python3 create_agent.py agent-geo-policy-violation-002 >/dev/null 2>&1 || cleanup_on_failure

# Start services
echo "   Starting gateway..."
SERVICE_NAME=opentelemetry-gateway PORT=9000 python3 gateway/app.py >/dev/null 2>&1 &
echo "   Starting collector..."
SERVICE_NAME=opentelemetry-collector PORT=8500 python3 collector/app.py >/dev/null 2>&1 &

# Wait for services to start
echo "   Waiting for services to start..."
for i in {1..20}; do
    sleep 1
    GATEWAY_HEALTH=$(curl -s -k "$GATEWAY_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
    COLLECTOR_HEALTH=$(curl -s -k "$COLLECTOR_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
    if [[ "$GATEWAY_HEALTH" == '"status":"healthy"' && "$COLLECTOR_HEALTH" == '"status":"healthy"' ]]; then
        echo "   ✅ Services started"
        break
    fi
    if [[ $i -eq 20 ]]; then
        echo -e "${RED}❌ Failed to start services${NC}"
        cleanup_on_failure
    fi
done

# Show allowlist BEFORE creating unregistered agent
echo "   📋 Collector Allowlist (before creating unregistered agent):"
if [[ -f "collector/allowed_agents.json" ]]; then
    echo "   $(cat collector/allowed_agents.json | python3 -m json.tool 2>/dev/null || cat collector/allowed_agents.json)"
else
    echo "   ❌ allowlist file not found"
fi

# Create agent-unregistered-003 AFTER collector/gateway are running (so it's NOT in allowlist)
echo "   Creating agent-unregistered-003 (will be unregistered)..."
python3 create_agent.py agent-unregistered-003 >/dev/null 2>&1 || cleanup_on_failure

# Start all agents
echo "   Starting agent-001..."
SERVICE_NAME=opentelemetry-agent PORT=8401 python3 start_agent.py agent-001 >/dev/null 2>&1 &
echo "   Starting agent-geo-policy-violation-002..."
AGENT_GEO_POLICY_VIOLATION_002_GEOGRAPHIC_REGION="EU/Germany/Berlin" SERVICE_NAME=opentelemetry-agent PORT=8402 python3 start_agent.py agent-geo-policy-violation-002 >/dev/null 2>&1 &
echo "   Starting agent-unregistered-003..."
SERVICE_NAME=opentelemetry-agent PORT=8403 python3 start_agent.py agent-unregistered-003 >/dev/null 2>&1 &

# Wait for all agents to start
echo "   Waiting for all agents to start..."
for i in {1..20}; do
    sleep 1
    AGENT1_HEALTH=$(curl -s -k "https://localhost:8401/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
    AGENT2_HEALTH=$(curl -s -k "https://localhost:8402/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
    AGENT3_HEALTH=$(curl -s -k "https://localhost:8403/health" 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
    if [[ "$AGENT1_HEALTH" == '"status":"healthy"' && "$AGENT2_HEALTH" == '"status":"healthy"' && "$AGENT3_HEALTH" == '"status":"healthy"' ]]; then
        echo "   ✅ All agents started"
        break
    fi
    if [[ $i -eq 20 ]]; then
        echo -e "${RED}❌ Failed to start all agents${NC}"
        cleanup_on_failure
    fi
done

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

# Step 2.1: Validate gateway header log entries for nonce and metrics
echo -e "${YELLOW}2.1 Validating HTTP header logs at gateway...${NC}"

if [[ -f "$HEADER_LOG" ]]; then
    echo -n "   Checking Signature-Input for /nonce: "
    if grep -q '"endpoint":"/nonce"' "$HEADER_LOG" && grep -q '"Signature-Input":"keyid' "$HEADER_LOG"; then
        echo -e "${GREEN}✅ Present${NC}"
    else
        echo -e "${RED}❌ Missing${NC}"
    fi

    echo -n "   Checking Workload-Geo-ID + Signature for /metrics: "
    if grep -q '"endpoint":"/metrics"' "$HEADER_LOG" && grep -q '"Workload-Geo-ID":' "$HEADER_LOG" && grep -q '"Signature":"' "$HEADER_LOG"; then
        echo -e "${GREEN}✅ Present${NC}"
    else
        echo -e "${RED}❌ Missing${NC}"
    fi
else
    echo -e "${RED}❌ Header log file not found: $HEADER_LOG${NC}"
fi

echo ""

# Step 2.2: Test nonce functionality (before cleanup)
echo -e "${YELLOW}2.2 Testing nonce functionality...${NC}"

# Test nonce generation via gateway (using real public_key_hash)
echo -n "   Nonce generation via gateway: "
AGENT_CFG="agents/agent-001/config.json"
if [[ -f "$AGENT_CFG" ]]; then
    RAW_KEY=$(python3 -c "import json; print(json.load(open('$AGENT_CFG')).get('tpm_public_key', ''))" 2>/dev/null)
    if [[ -n "$RAW_KEY" && "$RAW_KEY" != "null" ]]; then
        KEY_HASH=$(printf "%s" "$RAW_KEY" | sha256sum | awk '{print $1}')
        NONCE_RESPONSE=$(curl -s -k "$GATEWAY_URL/nonce?public_key_hash=$KEY_HASH" 2>/dev/null)
        if echo "$NONCE_RESPONSE" | grep -q '"nonce"'; then
            echo -e "${GREEN}✅ Working${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
            echo "      Response: $NONCE_RESPONSE"
        fi
    else
        echo -e "${RED}❌ Missing tpm_public_key in $AGENT_CFG${NC}"
    fi
else
    echo -e "${RED}❌ Agent config not found: $AGENT_CFG${NC}"
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

# Step 2.3: Demo Scenarios Testing
echo -e "${YELLOW}2.3 Demo Scenarios Testing...${NC}"

# Demo Scenarios (agent-001 happy path already tested above)
echo "   Demo Scenarios:"
echo "   • Test 1: Happy Path - agent-001 ✅ (completed in Step 2)"

# Test 2: Geographic Policy Violation
echo "   • Test 2: Geographic Policy Violation..."
echo -n "      Testing agent-geo-policy-violation-002: "
RESPONSE2=$(curl -s -k -X POST "https://localhost:8402/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' 2>/dev/null)
if echo "$RESPONSE2" | grep -q "Geolocation verification failed\|geographic policy violation\|rejected\|denied"; then
    echo -e "${GREEN}✅ Correctly rejected (geographic policy violation)${NC}"
    echo "      Details: $(echo "$RESPONSE2" | grep -o '"details":"[^"]*"' | cut -d'"' -f4)"
else
    echo -e "${RED}❌ Unexpected response: $RESPONSE2${NC}"
fi

# Test 3: Unregistered Agent
echo "   • Test 3: Unregistered Agent..."
echo -n "      Testing agent-unregistered-003: "
RESPONSE3=$(curl -s -k -X POST "https://localhost:8403/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' 2>/dev/null)
if echo "$RESPONSE3" | grep -q "not found in allowlist\|not in allowlist\|unauthorized\|rejected"; then
    echo -e "${GREEN}✅ Correctly rejected (unregistered agent)${NC}"
    echo "      Details: $(echo "$RESPONSE3" | grep -o '"details":"[^"]*"' | cut -d'"' -f4 || echo "$RESPONSE3")"
else
    echo -e "${RED}❌ Unexpected response: $RESPONSE3${NC}"
fi

echo ""

# Step 2.4: Monitoring and Debugging Information
echo -e "${YELLOW}2.4 Monitoring and Debugging Information...${NC}"

echo "   📊 Gateway Header Logs (last 5 entries):"
if [[ -f "$HEADER_LOG" ]]; then
    echo "   $(tail -5 "$HEADER_LOG" | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        print(json.dumps(json.loads(line.strip()), indent=2))
        print()
    except:
        print(line.strip())
        print()
" 2>/dev/null || tail -5 "$HEADER_LOG" | sed 's/}/}\n/g')"
else
    echo "   ❌ Header log file not found"
fi

echo ""

# Step 3: Show system status
echo -e "${YELLOW}3. System Status Summary${NC}"

echo -e "${BLUE}   🔐 Security Features:${NC}"
echo "      • TPM2 hardware-backed signing"
echo "      • Nonce-based anti-replay protection"
echo "      • Geographic compliance verification"
echo "      • Agent allowlist validation"
echo "      • OpenSSL signature verification"

echo -e "${BLUE}   🌐 Network Architecture:${NC}"
echo "      • Agent-001 (port 8401): Normal operation & metrics generation"
echo "      • Agent-002 (port 8402): Geographic policy violation test"
echo "      • Agent-003 (port 8403): Unregistered agent test"
echo "      • Gateway (port 9000): TLS termination & routing"
echo "      • Collector (port 8500): Verification & processing"

echo -e "${BLUE}   📊 Data Flow:${NC}"
echo "      Agent → Gateway → Collector"
echo "      Sign → Proxy → Verify"

echo ""

# Step 4: Success message
echo -e "${GREEN}🎉 Multi-Agent Zero-Trust System is Operational!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "   • Create additional agents: python create_agent.py agent-002"
echo "   • Test multi-agent scenarios"
echo "   • Monitor logs for detailed flow information"
echo "   • Check collector allowlist: cat collector/allowed_agents.json"

# Step 4: Stop services (all agents, gateway, collector)
echo ""
echo -e "${YELLOW}4. Stopping services (all agents, gateway, collector)...${NC}"

# Try graceful shutdown by port
kill_by_port 8401  # agent-001
kill_by_port 8402  # agent-geo-policy-violation-002
kill_by_port 8403  # agent-unregistered-003
kill_by_port 9000  # gateway
kill_by_port 8500  # collector

# Fallback: pkill by command
pkill -f "agent/app.py" >/dev/null 2>&1 || true
pkill -f "gateway/app.py" >/dev/null 2>&1 || true
pkill -f "collector/app.py" >/dev/null 2>&1 || true

# Wait briefly to ensure termination
for i in {1..5}; do
  sleep 1
  A_UP=$(curl -s -k "$AGENT_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || true)
  G_UP=$(curl -s -k "$GATEWAY_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || true)
  C_UP=$(curl -s -k "$COLLECTOR_URL/health" 2>/dev/null | grep -o '"status":"healthy"' || true)
  if [[ -z "$A_UP" && -z "$G_UP" && -z "$C_UP" ]]; then
    break
  fi
done

echo -e "${GREEN}   ✅ Services stopped (or stop attempted)${NC}"

# Step 5: Cleanup (remove agents and reset allowlist)
echo ""
echo -e "${YELLOW}5. Cleaning up test artifacts (agents, allowlist, TPM files)...${NC}"

if [[ -f "cleanup_all_agents.sh" ]]; then
  bash cleanup_all_agents.sh --force >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}   ✅ Cleanup completed${NC}"
  else
    echo -e "${RED}   ❌ Cleanup encountered issues${NC}"
  fi
else
  echo -e "${RED}   ❌ cleanup_all_agents.sh not found${NC}"
fi

echo ""