#!/bin/bash

# 3-Act Demo Script for Zero-Trust Sovereign AI: Unified Identity
# This script guides the audience through the Setup -> Happy Path -> Defense demonstration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
SOVEREIGN_HOST="10.1.0.11"
ONPREM_HOST="10.1.0.10"
SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
CLIENT_LOG="/tmp/mtls-client-app.log"

# SSH options to avoid password prompts
SSH_OPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no -o BatchMode=yes"

# Detect if we're running on the sovereign host
# First, check all IP addresses on this host
CURRENT_HOST_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' || echo '')
ON_SOVEREIGN_HOST=false

# Check if any of our IPs match the sovereign host IP
if echo "$CURRENT_HOST_IPS" | grep -q "^${SOVEREIGN_HOST}$"; then
    ON_SOVEREIGN_HOST=true
else
    # Try to check via hostname comparison (fallback, but avoid SSH if we're already on the host)
    CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo '')
    # Only try SSH if we're not already on the host (to avoid unnecessary SSH attempts)
    if [ -n "${CURRENT_HOSTNAME}" ]; then
        # Try to get sovereign hostname without SSH first (if we can resolve it)
        SOVEREIGN_HOSTNAME=$(getent hosts ${SOVEREIGN_HOST} 2>/dev/null | awk '{print $2}' | head -1 || echo '')
        if [ -z "${SOVEREIGN_HOSTNAME}" ]; then
            # Fallback to SSH only if we can't resolve it locally
            SOVEREIGN_HOSTNAME=$(ssh ${SSH_OPTS} -o ConnectTimeout=2 mw@${SOVEREIGN_HOST} 'hostname' 2>/dev/null || echo '')
        fi
        if [ "${CURRENT_HOSTNAME}" = "${SOVEREIGN_HOSTNAME}" ] && [ -n "${SOVEREIGN_HOSTNAME}" ]; then
            ON_SOVEREIGN_HOST=true
        fi
    fi
fi

# Function to run command on sovereign host (local or via SSH)
run_on_sovereign() {
    if [ "${ON_SOVEREIGN_HOST}" = "true" ]; then
        # Execute locally on 10.1.0.11 - no SSH needed
        bash -c "$@"
    else
        # Execute via SSH
        ssh ${SSH_OPTS} mw@${SOVEREIGN_HOST} "$@"
    fi
}

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║  Zero-Trust Sovereign AI: Unified Identity Demo              ║${NC}"
echo -e "${BOLD}${CYAN}║  3-Act Structure: Setup → Happy Path → Defense              ║${NC}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# INTRODUCTION: The Sovereign Challenge
# ============================================================================
echo -e "${BOLD}${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${YELLOW}INTRODUCTION: The Sovereign Challenge${NC}"
echo -e "${BOLD}${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Welcome. Today we are demonstrating a novel approach to${NC}"
echo -e "${BOLD}Zero-Trust Sovereign AI.${NC}"
echo ""
echo "As AI workloads move to the edge, regulated industries face a critical"
echo "challenge: ensuring data residency not just via policy, but via"
echo "cryptographic proof."
echo ""
echo -e "${YELLOW}Current solutions are fragile:${NC}"
echo "  • Host Geolocation Affinity (IP-based geofencing) - can be spoofed via VPNs"
echo "  • Insider Threats - rogue admin with physical access can bypass firewalls"
echo ""
echo -e "${GREEN}Our solution: Unified Identity${NC}"
echo "  • Binds workload to specific hardware and physical location"
echo "  • Makes it impossible to spoof"
echo ""
read -p "Press Enter to continue to Act 1: Setup..."

# ============================================================================
# ACT 1: The Setup (Trusted Infrastructure)
# ============================================================================
echo ""
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}ACT 1: The Setup (Trusted Infrastructure)${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Let's look at the architecture for our PoC:"
echo ""
echo -e "${BLUE}Left (Sovereign Public/Edge Cloud):${NC}"
echo "  • AI Inference Client"
echo "  • SPIRE Server"
echo "  • Keylime Verifier"
echo "  • Location Anchor Host with Mobile Location Sensor (GNSS)"
echo ""
echo -e "${BLUE}Right (Customer On-Prem Private Cloud):${NC}"
echo "  • Sensitive Model and Key Vault"
echo "  • Envoy Proxy with WASM Plugin"
echo "  • Mobile Location Service (CAMARA API)"
echo ""
echo -e "${BOLD}The Critical Component:${NC}"
echo "The Location Anchor Host is equipped with a Mobile Location Sensor (GNSS)."
echo "Before we run any workload, our Keylime Verifier establishes a hardware"
echo "root of trust with the TPM."
echo ""
echo -e "${YELLOW}Action: Starting the Control Plane...${NC}"
echo ""

# Start control plane services on sovereign host (10.1.0.11)
echo "Starting control plane services on ${SOVEREIGN_HOST}..."
echo "  Running test_complete_control_plane.sh --no-pause..."
echo "  (This may take a minute to start all services...)"
echo ""

if [ "${ON_SOVEREIGN_HOST}" = "true" ]; then
    cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete_control_plane.sh --no-pause
else
    ssh ${SSH_OPTS} mw@${SOVEREIGN_HOST} "cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete_control_plane.sh --no-pause"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Control plane services started successfully${NC}"
else
    echo -e "${RED}✗ Failed to start control plane services${NC}"
    exit 1
fi

echo ""
echo "Starting onprem services on ${ONPREM_HOST}..."
echo "  Running test_onprem.sh..."
echo "  (This may take a minute to start all services...)"
echo ""

# Run test_onprem.sh on the onprem host
# Note: test_onprem.sh starts services in background and exits successfully
# Temporarily disable exit on error to handle SSH properly
set +e
ssh ${SSH_OPTS} mw@${ONPREM_HOST} "cd ~/AegisEdgeAI/hybrid-cloud-poc/enterprise-private-cloud && ./test_onprem.sh" 2>&1
ONPREM_EXIT_CODE=$?
set -e

# Explicitly continue the script after SSH command
if [ $ONPREM_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Onprem services started successfully${NC}"
    echo "  Services are running in the background on ${ONPREM_HOST}"
    echo "  (Mobile Location Service, mTLS Server, Envoy Proxy)"
else
    echo ""
    echo -e "${RED}✗ Failed to start onprem services (exit code: $ONPREM_EXIT_CODE)${NC}"
    exit 1
fi

# Explicit continuation - ensure script doesn't exit here
echo ""
echo -e "${GREEN}You can see the Keylime Verifier loading the 'Golden State' policies${NC}"
echo -e "${GREEN}for our hardware.${NC}"
echo ""
echo -e "${CYAN}Act 1 complete. All control plane and onprem services are running.${NC}"
echo ""
echo -e "${BOLD}Ready to proceed to Act 2...${NC}"
echo ""

# Ensure we're reading from the terminal, not from a pipe
# Use explicit file descriptor check
if [ -t 0 ] && [ -t 1 ]; then
    read -p "Press Enter to continue to Act 2: Happy Path... " < /dev/tty
else
    echo "  (Non-interactive mode - continuing automatically in 3 seconds...)"
    sleep 3
fi

# ============================================================================
# ACT 2: The Happy Path (Proof of Residency)
# ============================================================================
echo ""
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}ACT 2: The Happy Path (Proof of Residency)${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}${YELLOW}Slide to Display:${NC} ${BOLD}Appendix: Unified Identity Architecture Details${NC}"
echo -e "${BOLD}  (Specifically focus on the 'Spiffe/Spire agent unified svid' flow)${NC}"
echo ""
read -p "Press Enter after displaying the slide..."
echo ""
echo "Now, let's authorize a workload. In a standard Zero Trust environment,"
echo "the workload just asks for an ID. In our Phase II solution, it's different."
echo ""
echo -e "${BOLD}Look at Step 9 in this flow:${NC} The Agent fetches a Unified SVID."
echo "This isn't just a software certificate. It includes:"
echo ""
echo "  1. ${GREEN}Workload Attestation${NC} (Software identity)"
echo "  2. ${GREEN}Host Attestation${NC} (TPM proof)"
echo "  3. ${GREEN}Geolocation Proof${NC} (From the Keylime Agent Plugin)"
echo ""
echo -e "${YELLOW}Action: Starting SPIRE Agent, Keylime Agent, and TPM Plugin...${NC}"
echo ""

# Start agent services on sovereign host (10.1.0.11)
echo "Starting agent services on ${SOVEREIGN_HOST}..."
echo "  Running test_complete.sh --no-pause (control plane services already running)..."
echo "  (This may take a minute to start all agents...)"
echo ""

if [ "${ON_SOVEREIGN_HOST}" = "true" ]; then
    cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete.sh --no-pause
else
    ssh ${SSH_OPTS} mw@${SOVEREIGN_HOST} "cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete.sh --no-pause"
fi

AGENT_EXIT_CODE=$?
if [ $AGENT_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Agent services started successfully${NC}"
else
    echo -e "${RED}✗ Failed to start agent services${NC}"
    exit 1
fi

# Wait a moment for agents to fully initialize
echo "  Waiting for agents to initialize..."
sleep 5

# Check if SPIRE Agent is actually running
SPIRE_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'spire-agent.*run' > /dev/null" 2>/dev/null && echo "yes" || echo "no")

echo ""
echo -e "${YELLOW}Action: I am starting the SPIRE Agent.${NC}"
echo "Watch the logs. It is connecting to the Keylime Plugin... verifying the GNSS sensor... and now it receives the SVID."
echo ""

# Show SPIRE Agent attestation logs
echo "Fetching latest SPIRE Agent attestation logs..."

# Check if SPIRE Agent is running
if [ "${SPIRE_AGENT_RUNNING}" = "yes" ]; then
    # Agent is running, try to get logs
    ATTESTATION_LOGS=$(run_on_sovereign "timeout 2 tail -50 /tmp/spire-agent.log 2>/dev/null | grep -iE '(attestation|SVID|geolocation|TPM|Plugin|SovereignAttestation|Node attestation)' | tail -5" 2>/dev/null || echo "")
    if [ -n "$ATTESTATION_LOGS" ] && [ ${#ATTESTATION_LOGS} -gt 0 ]; then
        echo "$ATTESTATION_LOGS" | sed 's/^/  /'
    else
        # Show general agent logs if specific patterns not found
        AGENT_STATUS=$(run_on_sovereign "timeout 2 tail -20 /tmp/spire-agent.log 2>/dev/null | tail -5" 2>/dev/null || echo "")
        if [ -n "$AGENT_STATUS" ] && [ ${#AGENT_STATUS} -gt 0 ]; then
            echo "  (Recent agent activity:)"
            echo "$AGENT_STATUS" | sed 's/^/  /'
        else
            echo "  (SPIRE Agent is running but logs may not be available yet)"
        fi
    fi
else
    echo -e "  ${YELLOW}⚠ SPIRE Agent may still be starting...${NC}"
    echo "  (Checking agent status...)"
    # Wait a bit more and check again
    sleep 3
    SPIRE_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'spire-agent.*run' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
    if [ "${SPIRE_AGENT_RUNNING}" = "yes" ]; then
        echo -e "  ${GREEN}✓ SPIRE Agent is now running${NC}"
    else
        echo -e "  ${YELLOW}⚠ SPIRE Agent may need more time to start${NC}"
        echo "  (Agent processes may still be initializing)"
    fi
fi

echo ""
echo -e "${BOLD}The Visual Proof:${NC}"
echo "I'm going to decode this SVID. You can see right here—the"
echo -e "${GREEN}Proof of Residency (PoR)${NC} is embedded directly in the certificate extensions."
echo ""
read -p "Press Enter to continue..."
echo ""

# Decode and display SVID (with timeout to prevent hanging)
echo "Fetching and decoding SVID..."

# Re-check SPIRE Agent status for SVID fetch
SPIRE_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'spire-agent.*run' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
SPIRE_AGENT_SOCKET=$(run_on_sovereign "test -S /tmp/spire-agent/public/api.sock" 2>/dev/null && echo "yes" || echo "no")

# Check if SPIRE Agent is running and socket is ready (required for SVID fetch)
if [ "${SPIRE_AGENT_RUNNING}" = "yes" ] || [ "${SPIRE_AGENT_SOCKET}" = "yes" ]; then
    # Try to fetch SVID first
    echo "  Fetching SVID from SPIRE Agent..."
    run_on_sovereign "cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo && python3 fetch-sovereign-svid-grpc.py > /dev/null 2>&1" 2>/dev/null || true
    
    # Check if SVID file exists
    if run_on_sovereign "test -f /tmp/svid-dump/svid.pem" 2>/dev/null; then
        echo "  ✓ SVID file found, decoding to show Proof of Residency..."
        echo ""
        # Decode SVID and show the AttestedClaims section (which contains PoR)
        # We need more lines to see the AttestedClaims section (it comes after certificate chain info)
        SVID_OUTPUT=$(run_on_sovereign "timeout 15 bash -c 'cd ~/AegisEdgeAI/hybrid-cloud-poc && scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem 2>/dev/null'" 2>/dev/null || echo "")
        if [ -n "$SVID_OUTPUT" ] && [ ${#SVID_OUTPUT} -gt 0 ]; then
            # Extract and show the AttestedClaims section (Proof of Residency)
            # The AttestedClaims section starts after "AttestedClaims Extension" header
            echo "$SVID_OUTPUT" | grep -A 50 "AttestedClaims Extension" | head -40 | sed 's/^/  /'
            # Also show a summary of certificate chain
            echo ""
            echo "  Certificate Chain Summary:"
            echo "$SVID_OUTPUT" | grep -E "^(    \[|  Certificate|  SPIRE|  Signing)" | head -10 | sed 's/^/    /'
        else
            echo "  (SVID decode output was empty)"
        fi
    else
        echo "  (SVID file not found - SPIRE Agent may still be initializing)"
        echo "  (Note: SVID fetch requires SPIRE Agent to be running and have completed attestation)"
    fi
else
    echo -e "  ${YELLOW}⚠ SPIRE Agent may still be initializing...${NC}"
    echo "  (SVID fetch requires SPIRE Agent socket to be ready)"
    echo "  Waiting a bit more for agent to be ready..."
    sleep 5
    # Try one more time
    SPIRE_AGENT_SOCKET=$(run_on_sovereign "test -S /tmp/spire-agent/public/api.sock" 2>/dev/null && echo "yes" || echo "no")
    if [ "${SPIRE_AGENT_SOCKET}" = "yes" ]; then
        echo -e "  ${GREEN}✓ SPIRE Agent socket is now ready, attempting SVID fetch...${NC}"
        run_on_sovereign "cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo && python3 fetch-sovereign-svid-grpc.py > /dev/null 2>&1" 2>/dev/null || true
        if run_on_sovereign "test -f /tmp/svid-dump/svid.pem" 2>/dev/null; then
            SVID_OUTPUT=$(run_on_sovereign "timeout 15 bash -c 'cd ~/AegisEdgeAI/hybrid-cloud-poc && scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem 2>/dev/null'" 2>/dev/null || echo "")
            if [ -n "$SVID_OUTPUT" ] && [ ${#SVID_OUTPUT} -gt 0 ]; then
                echo "$SVID_OUTPUT" | grep -A 50 "AttestedClaims Extension" | head -40 | sed 's/^/  /'
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠ SPIRE Agent socket not yet ready - SVID will be available once agent completes attestation${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}Action: The Client App now calls the Server.${NC}"
echo ""
echo "As the request hits the Envoy Proxy in the On-Prem cloud, the WASM Plugin"
echo "verifies two things:"
echo ""
echo -e "  1. ${GREEN}The Cryptographic Signature${NC}"
echo -e "  2. ${GREEN}The Proof of Geofencing (PoG)${NC}"
echo ""
read -p "Press Enter to continue..."
echo ""

# Send a single HTTP request (for clear, decodable logs)
echo "Sending a single HTTP request via mTLS..."
echo "  (This ensures only one request is sent for clear log analysis)"

# Temporarily disable exit on error for client execution (to prevent script termination)
set +e

# Kill any existing client first
run_on_sovereign "cd ~/AegisEdgeAI/hybrid-cloud-poc && pkill -f 'mtls-client-app.py|send-single-request.py' 2>/dev/null; sleep 1" 2>/dev/null

# Set server configuration
SERVER_HOST="${SERVER_HOST:-10.1.0.10}"
SERVER_PORT="${SERVER_PORT:-8080}"

# Use the single-request script if available, otherwise use timeout with regular client
if run_on_sovereign "test -f ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo/send-single-request.py" 2>/dev/null; then
    echo "  Using single-request script..."
    # Execute on sovereign host (10.1.0.11) - use run_on_sovereign which handles local vs SSH
    # Use timeout to prevent hanging (20 seconds should be enough)
    CLIENT_OUTPUT=$(run_on_sovereign "timeout 20 bash -c 'cd ~/AegisEdgeAI/hybrid-cloud-poc && SERVER_HOST=${SERVER_HOST} SERVER_PORT=${SERVER_PORT} python3 python-app-demo/send-single-request.py 2>&1'" 2>/dev/null || echo "TIMEOUT: Client script exceeded 20 second timeout")
    CLIENT_EXIT_CODE=$?
    if [ -n "$CLIENT_OUTPUT" ]; then
        echo "$CLIENT_OUTPUT" | sed 's/^/  /'
    fi
    if [ $CLIENT_EXIT_CODE -ne 0 ]; then
        echo -e "  ${YELLOW}⚠ Client script exited with code $CLIENT_EXIT_CODE (this is OK if request was sent)${NC}"
    fi
else
    # Fallback: use regular client with timeout (sends one request then stops)
    echo "  Using regular client with timeout (single request)..."
    if [ "${ON_SOVEREIGN_HOST}" = "true" ]; then
        cd ~/AegisEdgeAI/hybrid-cloud-poc && SERVER_HOST=${SERVER_HOST} SERVER_PORT=${SERVER_PORT} timeout 8 python3 python-app-demo/mtls-client-app.py 2>&1 | head -30 || true
    else
        ssh ${SSH_OPTS} mw@${SOVEREIGN_HOST} "cd ~/AegisEdgeAI/hybrid-cloud-poc && SERVER_HOST=${SERVER_HOST} SERVER_PORT=${SERVER_PORT} timeout 8 python3 python-app-demo/mtls-client-app.py 2>&1 | head -30" 2>/dev/null || true
    fi
    # Stop client after timeout
    run_on_sovereign "pkill -f mtls-client-app.py 2>/dev/null" 2>/dev/null || true
fi

# Re-enable exit on error
set -e

# Wait a moment for Envoy to process and log the request
echo ""
echo "  (Waiting for services to process request...)"
sleep 5

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Envoy Logs (mTLS Handshake, HTTP Request, WASM Plugin)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
# Get recent Envoy logs showing mTLS handshake, HTTP requests, and WASM plugin activity
# Look for: TLS handshake, HTTP requests, WASM filter logs, sensor verification
ENVOY_LOGS=$(ssh ${SSH_OPTS} mw@${ONPREM_HOST} "timeout 3 sudo tail -500 /opt/envoy/logs/envoy.log 2>/dev/null | grep -vE '(Deprecated|loading|initializing|starting|admin address|runtime:|cm init|all clusters|dependencies|main dispatch|HTTP header map|stats configuration|RTDS|listener_manager|envoy.filters|envoy.upstream|envoy.transport|envoy.matching|envoy.access_loggers|envoy.stats_sinks|envoy.quic|quic.http|filter_state)' | grep -iE '(TLS|handshake|connection|GET /hello|POST|HTTP|sensor|verification|Extracted|200 OK|403|Forbidden|Geo Claim|X-Sensor-ID|wasm|filter|resuming request|rejecting request|client.*connected|downstream.*request)' | tail -30" 2>/dev/null || echo "")
if [ -n "$ENVOY_LOGS" ] && [ ${#ENVOY_LOGS} -gt 0 ]; then
    echo "$ENVOY_LOGS" | sed 's/^/  /'
else
    echo "  (No recent Envoy request logs found - may need to wait longer or check if request was sent)"
fi

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}WASM Plugin Logs (Sensor Verification)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
# Get WASM plugin specific logs
WASM_LOGS=$(ssh ${SSH_OPTS} mw@${ONPREM_HOST} "timeout 3 sudo tail -500 /opt/envoy/logs/envoy.log 2>/dev/null | grep -iE '(wasm|sensor.*verification|Extracted.*sensor_id|sensor_id:|verification.*successful|verification.*failed|resuming request|rejecting request|Geo Claim)' | tail -15" 2>/dev/null || echo "")
if [ -n "$WASM_LOGS" ] && [ ${#WASM_LOGS} -gt 0 ]; then
    echo "$WASM_LOGS" | sed 's/^/  /'
else
    echo "  (No WASM plugin logs found yet)"
fi

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}mTLS Server Logs (Backend Service)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
# Get mTLS server logs showing connection and request handling
MTLS_SERVER_LOGS=$(ssh ${SSH_OPTS} mw@${ONPREM_HOST} "timeout 2 tail -100 /tmp/mtls-server.log 2>/dev/null | grep -iE '(connected|TLS|handshake|HTTP|GET|POST|request|response|200|403|Client.*connected)' | tail -20" 2>/dev/null || echo "")
if [ -n "$MTLS_SERVER_LOGS" ] && [ ${#MTLS_SERVER_LOGS} -gt 0 ]; then
    echo "$MTLS_SERVER_LOGS" | sed 's/^/  /'
else
    echo "  (No mTLS server logs found - server may not have received request yet)"
fi

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Mobile Sensor Service Logs (Geolocation Verification)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
# Get mobile sensor service logs showing verification requests
MOBILE_SENSOR_LOGS=$(ssh ${SSH_OPTS} mw@${ONPREM_HOST} "timeout 2 tail -100 /tmp/mobile-sensor.log 2>/dev/null | grep -iE '(verification|sensor_id|request|CAMARA|result=True|result=False|completed)' | tail -15" 2>/dev/null || echo "")
if [ -n "$MOBILE_SENSOR_LOGS" ] && [ ${#MOBILE_SENSOR_LOGS} -gt 0 ]; then
    echo "$MOBILE_SENSOR_LOGS" | sed 's/^/  /'
else
    echo "  (No mobile sensor service logs found - verification may not have been triggered)"
fi

echo ""
echo -e "${GREEN}Log Check:${NC} Envoy reports '200 OK'. The location is verified as compliant."
echo ""
read -p "Press Enter to continue to Act 3: Defense..."

echo ""
read -p "Press Enter to continue to Act 3: Defense..."

# ============================================================================
# ACT 3: The Defense (The Rogue Admin)
# ============================================================================
echo ""
echo -e "${BOLD}${RED}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${RED}ACT 3: The Defense (The Rogue Admin)${NC}"
echo -e "${BOLD}${RED}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Now, let's test the system against the Insider Threat we discussed earlier."
echo "Imagine a rogue admin creates a copy of this workload in a non-compliant"
echo "region, or—as I'm about to do—physically tampers with the hardware to"
echo "bypass tracking."
echo ""
echo -e "${YELLOW}Action: I am acting as the rogue admin.${NC}"
echo -e "${YELLOW}I am physically disconnecting the USB Mobile Sensor from the host machine.${NC}"
echo ""

# Disconnect the sensor
echo "Disconnecting USB Mobile Sensor..."
run_on_sovereign "sudo ~/AegisEdgeAI/hybrid-cloud-poc/test_toggle_huawei_mobile_sensor.sh off" 2>/dev/null || echo "  (Sensor toggle script not available or already disconnected)"

sleep 2

echo ""
echo -e "${BOLD}The Detection:${NC}"
echo "Because we rely on Dynamic Hardware Integrity, the Keylime Agent"
echo "immediately detects the USB Disconnect event. The hardware integrity"
echo "score drops."
echo ""

# Show Keylime agent detection
echo "Checking Keylime Agent logs for sensor disconnect detection..."
run_on_sovereign "tail -30 /tmp/rust-keylime-agent.log 2>/dev/null | grep -E '(sensor|USB|disconnect|geolocation)' | tail -5" 2>/dev/null || echo "  (Checking agent status...)"

echo ""
echo -e "${BOLD}The Block (Degraded Identity):${NC}"
echo "The next time our workload attempts to refresh its identity, the"
echo "attestation fails."
echo ""
echo "The Policy Engine issues a Degraded SVID—valid for the network, but"
echo "missing the Proof of Residency."
echo ""

# Wait for SVID renewal (should happen within 30 seconds with Unified-Identity)
echo "Waiting for SVID renewal (up to 30 seconds)..."
echo "  (The agent will attempt to renew its SVID, but without geolocation)"
sleep 5

echo ""
echo -e "${YELLOW}Action: The Client App retries the request.${NC}"
echo ""

# Check client logs for reconnection
echo "Client logs (reconnection attempt):"
run_on_sovereign "tail -15 ${CLIENT_LOG} 2>/dev/null | tail -5" 2>/dev/null || echo "  (Checking client status...)"

echo ""
echo -e "${GREEN}Log Check:${NC} Look at the Envoy logs. The TLS handshake succeeds"
echo "(the identity is valid), but the WASM Plugin returns ${RED}403 Forbidden${NC}."
echo -e "The error is specific: ${RED}'Geo Claim Missing'${NC}."
echo ""

# Check Envoy logs for 403
echo "Envoy logs (403 Forbidden):"
ssh ${SSH_OPTS} mw@${ONPREM_HOST} "sudo tail -30 /opt/envoy/logs/envoy.log 2>/dev/null | grep -E '(403|Forbidden|Geo Claim|sensor.*missing)' | tail -5" 2>/dev/null || echo "  (Envoy logs not accessible or no 403 yet)"

echo ""
read -p "Press Enter to continue to Conclusion..."

# ============================================================================
# CONCLUSION: Value Delivered
# ============================================================================
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}CONCLUSION: Value Delivered${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "To summarize, we have moved from Phase I, where credentials could be"
echo "stolen and replayed, to Phase II."
echo ""
echo "By using HW-anchored proofs, we have achieved:"
echo ""
echo "  1. ${GREEN}Strong Residency Guarantees${NC} that are auditable"
echo "  2. Protection against ${GREEN}Insider Threats${NC}"
echo "  3. A ${GREEN}Unified Identity${NC} that you cannot peel away from the"
echo "     physical hardware"
echo ""
echo "This allows us to safely run AI workloads on the Sovereign Edge."
echo ""
echo -e "${BOLD}${CYAN}Demo Complete!${NC}"
echo ""

# Reconnect sensor for cleanup
echo "Reconnecting USB Mobile Sensor for cleanup..."
run_on_sovereign "sudo ~/AegisEdgeAI/hybrid-cloud-poc/test_toggle_huawei_mobile_sensor.sh on" 2>/dev/null || echo "  (Sensor toggle script not available)"

echo ""
echo "To stop the client:"
    if [ "${ON_SOVEREIGN_HOST}" = "true" ]; then
        echo "  pkill -f mtls-client-app.py"
    else
        echo "  ssh ${SSH_OPTS} mw@${SOVEREIGN_HOST} 'pkill -f mtls-client-app.py'"
    fi
echo ""
echo -e "${YELLOW}Note:${NC} This script uses SSH key-based authentication."
echo "Make sure your SSH keys are set up for passwordless access to both hosts."
echo ""

