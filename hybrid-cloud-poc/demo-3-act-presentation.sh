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
        # Execute locally - no SSH needed
        eval "$@"
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

# Check if services are already running
echo "Checking if control plane services are already running on ${SOVEREIGN_HOST}..."
SPIRE_RUNNING=$(run_on_sovereign "pgrep -f 'spire-server' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
VERIFIER_RUNNING=$(run_on_sovereign "pgrep -f 'keylime.*verifier|keylime\.cmd\.verifier' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
REGISTRAR_RUNNING=$(run_on_sovereign "pgrep -f 'keylime.*registrar|keylime\.cmd\.registrar' > /dev/null" 2>/dev/null && echo "yes" || echo "no")

if [ "${SPIRE_RUNNING}" = "yes" ] && [ "${VERIFIER_RUNNING}" = "yes" ] && [ "${REGISTRAR_RUNNING}" = "yes" ]; then
    echo -e "${GREEN}✓ SPIRE Server, Keylime Verifier, and Keylime Registrar are already running${NC}"
    echo "  Skipping control plane startup (services already running)"
else
    echo -e "${YELLOW}⚠ Starting control plane services...${NC}"
    [ "${SPIRE_RUNNING}" = "yes" ] && echo -e "  ${GREEN}✓${NC} SPIRE Server (already running)" || echo -e "  ${YELLOW}→${NC} Starting SPIRE Server"
    [ "${VERIFIER_RUNNING}" = "yes" ] && echo -e "  ${GREEN}✓${NC} Keylime Verifier (already running)" || echo -e "  ${YELLOW}→${NC} Starting Keylime Verifier"
    [ "${REGISTRAR_RUNNING}" = "yes" ] && echo -e "  ${GREEN}✓${NC} Keylime Registrar (already running)" || echo -e "  ${YELLOW}→${NC} Starting Keylime Registrar"
    echo ""
    echo "  Running test_complete_control_plane.sh --no-pause..."
    echo "  (This may take a minute to start all services...)"
    
    # Run test_complete_control_plane.sh
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
fi

echo ""
echo "Checking services on ${ONPREM_HOST}..."
# Check if services are already running
ONPREM_SERVICES_RUNNING=$(ssh ${SSH_OPTS} mw@${ONPREM_HOST} "sudo netstat -tlnp | grep -E ':(8080|5000|9443)' > /dev/null" 2>/dev/null && echo "yes" || echo "no")

if [ "${ONPREM_SERVICES_RUNNING}" = "yes" ]; then
    echo -e "${GREEN}✓ Envoy, Mobile Location Service, and mTLS Server are already running${NC}"
    echo "  Skipping onprem services startup (services already running)"
else
    echo -e "${YELLOW}⚠ Starting onprem services...${NC}"
    echo "  Running test_onprem.sh on ${ONPREM_HOST}..."
    echo "  (This may take a minute to start all services...)"
    
    # Run test_onprem.sh on the onprem host
    ssh ${SSH_OPTS} mw@${ONPREM_HOST} "cd ~/AegisEdgeAI/hybrid-cloud-poc/enterprise-private-cloud && ./test_onprem.sh"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Onprem services started successfully${NC}"
    else
        echo -e "${RED}✗ Failed to start onprem services${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}You can see the Keylime Verifier loading the 'Golden State' policies${NC}"
echo -e "${GREEN}for our hardware.${NC}"
echo ""
read -p "Press Enter to continue to Act 2: Happy Path..."

# ============================================================================
# ACT 2: The Happy Path (Proof of Residency)
# ============================================================================
echo ""
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}ACT 2: The Happy Path (Proof of Residency)${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Now, let's authorize a workload. In a standard Zero Trust environment,"
echo "the workload just asks for an ID. In our Phase II solution, it's different."
echo ""
echo -e "${BOLD}The SPIRE Agent${NC} is now part of the flow. It connects to the"
echo "Keylime Plugin, verifies the GNSS sensor, and fetches a Unified SVID."
echo ""
echo -e "${BOLD}Step 9 in the flow:${NC} The Agent fetches a Unified SVID."
echo "This isn't just a software certificate. It includes:"
echo ""
echo "  1. ${GREEN}Workload Attestation${NC} (Software identity)"
echo "  2. ${GREEN}Host Attestation${NC} (TPM proof)"
echo "  3. ${GREEN}Geolocation Proof${NC} (From the Keylime Agent Plugin)"
echo ""
echo -e "${YELLOW}Action: Starting SPIRE Agent, Keylime Agent, and TPM Plugin...${NC}"
echo ""

# Start agents using test_complete.sh (control plane already running from Act 1)
echo "  Starting agents (rust-keylime Agent, TPM Plugin, SPIRE Agent)..."
echo "    Using test_complete.sh --no-pause (control plane services already running)"
echo "    (This may take a minute to start all agents...)"

# Run the command in background and capture output
run_on_sovereign "cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete.sh --no-pause > /tmp/agents-startup.log 2>&1" &
AGENTS_STARTUP_PID=$!

# Wait a bit for agents to start, then check status
sleep 10

# Check if agents are starting/running
echo "    Checking agent status..."
KEYLIME_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'keylime_agent' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
TPM_PLUGIN_RUNNING=$(run_on_sovereign "test -S /tmp/spire-data/tpm-plugin/tpm-plugin.sock" 2>/dev/null && echo "yes" || echo "no")
SPIRE_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'spire-agent' > /dev/null" 2>/dev/null && echo "yes" || echo "no")

# Show status
if [ "${KEYLIME_AGENT_RUNNING}" = "yes" ]; then
    echo -e "    ${GREEN}✓ rust-keylime Agent is running${NC}"
else
    echo -e "    ${YELLOW}⚠ rust-keylime Agent starting...${NC}"
fi

if [ "${TPM_PLUGIN_RUNNING}" = "yes" ]; then
    echo -e "    ${GREEN}✓ TPM Plugin Server is running${NC}"
else
    echo -e "    ${YELLOW}⚠ TPM Plugin Server starting...${NC}"
fi

if [ "${SPIRE_AGENT_RUNNING}" = "yes" ]; then
    echo -e "    ${GREEN}✓ SPIRE Agent is running${NC}"
else
    echo -e "    ${YELLOW}⚠ SPIRE Agent starting...${NC}"
fi

# Wait a bit more for all agents to fully start
echo "    Waiting for all agents to be ready..."
for i in {1..30}; do
    KEYLIME_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'keylime_agent' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
    TPM_PLUGIN_RUNNING=$(run_on_sovereign "test -S /tmp/spire-data/tpm-plugin/tpm-plugin.sock" 2>/dev/null && echo "yes" || echo "no")
    SPIRE_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'spire-agent' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
    
    if [ "${KEYLIME_AGENT_RUNNING}" = "yes" ] && [ "${TPM_PLUGIN_RUNNING}" = "yes" ] && [ "${SPIRE_AGENT_RUNNING}" = "yes" ]; then
        echo -e "  ${GREEN}✓ All agents are running${NC}"
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "    Still waiting... (${i}/30 seconds)"
    fi
    sleep 1
done

# Final status check
KEYLIME_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'keylime_agent' > /dev/null" 2>/dev/null && echo "yes" || echo "no")
TPM_PLUGIN_RUNNING=$(run_on_sovereign "test -S /tmp/spire-data/tpm-plugin/tpm-plugin.sock" 2>/dev/null && echo "yes" || echo "no")
SPIRE_AGENT_RUNNING=$(run_on_sovereign "pgrep -f 'spire-agent' > /dev/null" 2>/dev/null && echo "yes" || echo "no")

if [ "${KEYLIME_AGENT_RUNNING}" = "yes" ] && [ "${TPM_PLUGIN_RUNNING}" = "yes" ] && [ "${SPIRE_AGENT_RUNNING}" = "yes" ]; then
    echo -e "  ${GREEN}✓ All agents started successfully${NC}"
else
    echo -e "  ${YELLOW}⚠ Some agents may still be starting${NC}"
    [ "${KEYLIME_AGENT_RUNNING}" = "yes" ] && echo -e "    ${GREEN}✓${NC} rust-keylime Agent" || echo -e "    ${RED}✗${NC} rust-keylime Agent"
    [ "${TPM_PLUGIN_RUNNING}" = "yes" ] && echo -e "    ${GREEN}✓${NC} TPM Plugin" || echo -e "    ${RED}✗${NC} TPM Plugin"
    [ "${SPIRE_AGENT_RUNNING}" = "yes" ] && echo -e "    ${GREEN}✓${NC} SPIRE Agent" || echo -e "    ${RED}✗${NC} SPIRE Agent"
    echo "    Check logs: /tmp/agents-startup.log"
fi

echo ""
echo -e "${YELLOW}Action: The SPIRE Agent is connecting to the Keylime Plugin...${NC}"
echo "Watch the logs. It is verifying the GNSS sensor... and now it receives the SVID."
echo ""

# Show SPIRE Agent attestation logs
echo "Fetching latest SPIRE Agent attestation logs..."

# Check if SPIRE Agent is running (use the status we already checked)
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
    echo -e "  ${YELLOW}⚠ SPIRE Agent is not running${NC}"
    echo "  (In --control-plane-only mode, SPIRE Agent is not started)"
    echo "  To start SPIRE Agent, run:"
    if [ "${ON_SOVEREIGN_HOST}" = "true" ]; then
        echo "    cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete.sh --no-pause"
    else
        echo "    ssh ${SSH_OPTS} mw@${SOVEREIGN_HOST} 'cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete.sh --no-pause'"
    fi
fi

echo ""
echo -e "${BOLD}The Visual Proof:${NC}"
echo "I'm going to decode this SVID. You can see right here—the"
echo -e "${GREEN}Proof of Residency (PoR)${NC} is embedded directly in the certificate extensions."
echo ""

# Decode and display SVID (with timeout to prevent hanging)
echo "Fetching and decoding SVID..."

# Check if SPIRE Agent is running (required for SVID fetch)
if [ "${SPIRE_AGENT_RUNNING}" = "yes" ]; then
    # Try to fetch SVID
    SVID_OUTPUT=$(run_on_sovereign "timeout 10 bash -c 'cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo && python3 fetch-sovereign-svid-grpc.py > /dev/null 2>&1 && ../scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem 2>/dev/null | head -30'" 2>/dev/null || echo "")
    if [ -n "$SVID_OUTPUT" ] && [ ${#SVID_OUTPUT} -gt 0 ]; then
        echo "$SVID_OUTPUT" | sed 's/^/  /'
    else
        echo "  (Attempting to fetch SVID...)"
        # Try to show if SVID file exists
        if run_on_sovereign "test -f /tmp/svid-dump/svid.pem" 2>/dev/null; then
            echo "  (SVID file exists, decoding...)"
            SVID_DECODE=$(run_on_sovereign "timeout 3 bash -c 'cd ~/AegisEdgeAI/hybrid-cloud-poc && scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem 2>/dev/null | head -20'" 2>/dev/null || echo "")
            if [ -n "$SVID_DECODE" ] && [ ${#SVID_DECODE} -gt 0 ]; then
                echo "$SVID_DECODE" | sed 's/^/  /'
            else
                echo "  (SVID file found but decode failed - may need agent to be running)"
            fi
        else
            echo "  (SVID not yet available - SPIRE Agent may still be initializing)"
            echo "  (Note: SVID fetch requires SPIRE Agent to be running)"
        fi
    fi
else
    echo -e "  ${YELLOW}⚠ Cannot fetch SVID: SPIRE Agent is not running${NC}"
    echo "  (SVID fetch requires SPIRE Agent to be running)"
    echo "  To start SPIRE Agent, run:"
    if [ "${ON_SOVEREIGN_HOST}" = "true" ]; then
        echo "    cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete.sh --no-pause"
    else
        echo "    ssh ${SSH_OPTS} mw@${SOVEREIGN_HOST} 'cd ~/AegisEdgeAI/hybrid-cloud-poc && ./test_complete.sh --no-pause'"
    fi
fi

echo ""
echo -e "${YELLOW}Action: The Client App now calls the Server.${NC}"
echo ""
echo "As the request hits the Envoy Proxy in the On-Prem cloud, the WASM Plugin"
echo "verifies two things:"
echo "  1. The Cryptographic Signature"
echo "  2. The Proof of Geofencing (PoG)"
echo ""

# Start client in background and show logs
echo "Starting mTLS client..."
run_on_sovereign "cd ~/AegisEdgeAI/hybrid-cloud-poc && pkill -f mtls-client-app.py 2>/dev/null; sleep 1; rm -f ${CLIENT_LOG} && nohup python3 python-app-demo/mtls-client-app.py > ${CLIENT_LOG} 2>&1 &" 2>/dev/null

echo "  (Waiting for client to connect...)"
sleep 4

echo ""
echo -e "${GREEN}Log Check: Envoy reports '200 OK'. The location is verified as compliant.${NC}"
echo ""
echo "Client logs (first few messages):"
CLIENT_LOGS=$(run_on_sovereign "timeout 2 tail -15 ${CLIENT_LOG} 2>/dev/null | grep -E '(Connected|Sending|Received|ACK|HELLO)' | head -5" 2>/dev/null || echo "")
if [ -n "$CLIENT_LOGS" ] && [ ${#CLIENT_LOGS} -gt 0 ]; then
    echo "$CLIENT_LOGS" | sed 's/^/  /'
else
    echo "  (Client starting or checking connection...)"
    # Show any available client logs
    CLIENT_ANY=$(run_on_sovereign "timeout 2 tail -5 ${CLIENT_LOG} 2>/dev/null" 2>/dev/null || echo "")
    if [ -n "$CLIENT_ANY" ] && [ ${#CLIENT_ANY} -gt 0 ]; then
        echo "$CLIENT_ANY" | sed 's/^/  /'
    fi
fi

echo ""
echo "Envoy logs (verification):"
ENVOY_LOGS=$(ssh ${SSH_OPTS} mw@${ONPREM_HOST} "timeout 2 sudo tail -30 /opt/envoy/logs/envoy.log 2>/dev/null | grep -E '(sensor|verification|Extracted|200 OK)' | tail -3" 2>/dev/null || echo "")
if [ -n "$ENVOY_LOGS" ] && [ ${#ENVOY_LOGS} -gt 0 ]; then
    echo "$ENVOY_LOGS" | sed 's/^/  /'
else
    echo "  (Envoy logs not accessible or verification not yet logged)"
fi

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

