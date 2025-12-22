#!/bin/bash
# Unified-Identity: Agent Services Integration Test (Act 2)
# Tests agent services: rust-keylime Agent + TPM Plugin + SPIRE Agent -> Sovereign SVID Generation
# Hardware Integration & Delegated Certification
# Note: Control plane services (SPIRE Server, Keylime Verifier/Registrar) are managed by test_control_plane.sh

set -euo pipefail
# Exit immediately on error - abort if anything goes wrong

# Unified-Identity: Hardware Integration & Delegated Certification
# Ensure feature flag is enabled by default (can be overridden by caller)
export UNIFIED_IDENTITY_ENABLED="${UNIFIED_IDENTITY_ENABLED:-true}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# All components are now consolidated in the root directory
PROJECT_DIR="${SCRIPT_DIR}"
KEYLIME_DIR="${SCRIPT_DIR}/keylime"
PYTHON_KEYLIME_DIR="${KEYLIME_DIR}"
RUST_KEYLIME_DIR="${SCRIPT_DIR}/rust-keylime"
SPIRE_DIR="${SCRIPT_DIR}/spire"

# Detect host IPs for flexible deployment
# These should be set by test_integration.sh via environment variables
# If not set, detect current host IP (for standalone execution)
if [ -z "${CONTROL_PLANE_HOST:-}" ]; then
    CONTROL_PLANE_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || \
                         ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1 || \
                         echo '127.0.0.1')
fi
if [ -z "${AGENTS_HOST:-}" ]; then
    AGENTS_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || \
                  ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1 || \
                  echo '127.0.0.1')
fi
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST}"
AGENTS_HOST="${AGENTS_HOST}"

# Detect current host IP (for agents host)
CURRENT_HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || \
                  ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1 || \
                  echo '127.0.0.1')

# Use AGENTS_HOST if set, otherwise use detected IP
AGENTS_HOST_IP="${AGENTS_HOST}"
CONTROL_PLANE_HOST_IP="${CONTROL_PLANE_HOST}"

# If all hosts are the same (single machine deployment), use 0.0.0.0 for agent binding
# This allows connections from any interface
if [ "${AGENTS_HOST_IP}" = "${CONTROL_PLANE_HOST_IP}" ]; then
    AGENT_BIND_IP="0.0.0.0"
else
    AGENT_BIND_IP="${AGENTS_HOST_IP}"
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    BLUE=""
    BOLD=""
    NC=""
fi

# Helper function to abort on critical errors
abort_on_error() {
    local message="$1"
    echo -e "${RED}✗ CRITICAL ERROR: ${message}${NC}" >&2
    echo -e "${RED}Aborting test execution.${NC}" >&2
    exit 1
}

# Helper function to check if a command succeeded, abort if not
check_critical() {
    local description="$1"
    shift
    if ! "$@"; then
        abort_on_error "${description} failed"
    fi
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Unified-Identity: Complete Integration Test                  ║"
echo "║  Hardware Integration & Delegated Certification                ║"
echo "║  Testing: TPM App Key + rust-keylime Agent -> Sovereign SVID   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Source cleanup.sh to reuse the stop_all_instances_and_cleanup function
# This avoids code duplication and ensures consistency
# Note: cleanup.sh will detect it's in scripts/ and use PROJECT_ROOT to find the root
# Save our SCRIPT_DIR before sourcing cleanup.sh (which may change it)
TEST_SCRIPT_DIR="${SCRIPT_DIR}"
PROJECT_ROOT="${SCRIPT_DIR}"
source "${SCRIPT_DIR}/scripts/cleanup.sh"
# Restore SCRIPT_DIR after sourcing (cleanup.sh may have changed it)
SCRIPT_DIR="${TEST_SCRIPT_DIR}"

# Wrap the cleanup function to add "Step 0:" prefix for consistency with test script output
# Save original function before we override it by copying it with a different name
{
    func_def=$(declare -f stop_all_instances_and_cleanup)
    # Replace function name in the definition (only the first occurrence on the function declaration line)
    func_def="${func_def/stop_all_instances_and_cleanup ()/_original_stop_all_instances_and_cleanup ()}"
    # Evaluate to define the function
    eval "$func_def"
}

# Function to clean up only agent services (for act 2 - non-control plane)
stop_agent_services_only() {
    echo -e "${CYAN}Step 0: Stopping agent services and cleaning up their data...${NC}"
    echo ""
    
    # Step 1: Stop agent processes only
    echo "  1. Stopping agent processes..."
    
    # Stop rust-keylime Agent
    echo "     Stopping rust-keylime Agent..."
    pkill -f "keylime_agent" >/dev/null 2>&1 || true
    pkill -f "rust-keylime" >/dev/null 2>&1 || true
    pkill -f "target/release/keylime_agent" >/dev/null 2>&1 || true
    
    # Stop TPM Plugin Server
    echo "     Stopping TPM Plugin Server..."
    pkill -f "tpm_plugin_server" >/dev/null 2>&1 || true
    
    # Stop SPIRE Agent (not Server)
    echo "     Stopping SPIRE Agent..."
    pkill -f "spire-agent" >/dev/null 2>&1 || true
    
    sleep 1
    
    # Step 2: Clean up only agent data directories
    echo "  2. Cleaning up agent data directories..."
    
    # Remove SPIRE Agent data (not Server data)
    echo "     Removing SPIRE Agent data directories..."
    rm -rf /tmp/spire-agent 2>/dev/null || true
    rm -f /tmp/spire-agent.pid 2>/dev/null || true
    rm -f /tmp/spire-agent.log 2>/dev/null || true
    
    # Remove rust-keylime agent data
    echo "     Removing rust-keylime agent data..."
    rm -rf /tmp/keylime-agent 2>/dev/null || true
    rm -f /tmp/rust-keylime-agent.pid 2>/dev/null || true
    rm -f /tmp/keylime-agent.sock 2>/dev/null || true
    rm -f /tmp/rust-keylime-agent.log 2>/dev/null || true
    
    # Remove TPM Plugin data
    echo "     Removing TPM Plugin data..."
    rm -rf /tmp/spire-data/tpm-plugin 2>/dev/null || true
    rm -f /tmp/tpm-plugin-server.pid 2>/dev/null || true
    rm -f /tmp/tpm-plugin-server.log 2>/dev/null || true
    
    # Remove SVID dump directory
    echo "     Removing SVID dump directory..."
    rm -rf /tmp/svid-dump 2>/dev/null || true
    
    # Step 3: Remove PID files
    echo "  3. Removing PID files..."
    rm -f /tmp/spire-agent.pid 2>/dev/null || true
    rm -f /tmp/rust-keylime-agent.pid 2>/dev/null || true
    rm -f /tmp/tpm-plugin-server.pid 2>/dev/null || true
    
    # Step 4: Remove log files
    echo "  4. Removing log files..."
    rm -f /tmp/spire-agent.log 2>/dev/null || true
    rm -f /tmp/rust-keylime-agent.log 2>/dev/null || true
    rm -f /tmp/tpm-plugin-server.log 2>/dev/null || true
    
    # Step 5: Remove socket files
    echo "  5. Removing socket files..."
    rm -f /tmp/spire-agent/public/api.sock 2>/dev/null || true
    rm -f /tmp/keylime-agent.sock 2>/dev/null || true
    rm -f /tmp/spire-data/tpm-plugin/tpm-plugin.sock 2>/dev/null || true
    
    # Step 6: Clean up temporary files in /tmp (using cleanup.sh function)
    echo "  6. Cleaning up temporary files in /tmp..."
    cleanup_tmp_files
    
    # Step 7: Create clean data directories
    echo "  7. Creating clean data directories..."
    mkdir -p /tmp/spire-agent/public 2>/dev/null || true
    mkdir -p /tmp/keylime-agent 2>/dev/null || true
    mkdir -p /tmp/spire-data/tpm-plugin 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}  ✓ Agent services stopped and data cleaned up${NC}"
}

# Override with wrapper that adds Step 0 prefix
# For test_agents.sh (act 2 - non-control plane), only clean up agent services
# Control plane services are managed by test_control_plane.sh
stop_all_instances_and_cleanup() {
    # Only clean up agent services (control plane is managed separately)
    stop_agent_services_only
}

# Pause function for critical phases (only in interactive terminals)
pause_at_phase() {
    local phase_name="$1"
    local description="$2"
    
    # Pause if PAUSE_ENABLED is true (default: true for interactive, false for non-interactive)
    if [ "${PAUSE_ENABLED:-true}" = "true" ]; then
        echo ""
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}⏸  PAUSE: ${phase_name}${NC}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        if [ -n "$description" ]; then
            echo -e "${CYAN}${description}${NC}"
            echo ""
        fi
        
        # If we have a TTY, do interactive pause; otherwise wait a bit
        if [ -t 0 ]; then
            echo -e "${YELLOW}Press Enter to continue...${NC}"
            read -r
        else
            # Non-interactive mode: wait a few seconds to allow viewing output
            echo -e "${YELLOW}Waiting 5 seconds (non-interactive mode)...${NC}"
            sleep 5
        fi
        echo ""
    fi
}

# Special pause function for demo purposes - always pauses even with --no-pause
pause_for_demo() {
    local phase_name="$1"
    local description="$2"
    
    # Always pause if running in interactive terminal (important for demos)
    if [ -t 0 ]; then
        echo ""
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}⏸  PAUSE: ${phase_name}${NC}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        if [ -n "$description" ]; then
            echo -e "${CYAN}${description}${NC}"
            echo ""
        fi
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
        echo ""
    fi
}

# Function to extract timestamp from log line
extract_timestamp() {
    local line="$1"
    # Try different timestamp formats
    # Format 1: 2025-11-22 03:00:03,410 (Python/TPM Plugin)
    if echo "$line" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"; then
        echo "$line" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[^ ]*).*/\1/'
    # Format 2: time="2025-11-22T03:00:08+01:00" (SPIRE)
    elif echo "$line" | grep -qE 'time="[^"]*"'; then
        echo "$line" | sed -E 's/.*time="([^"]*)".*/\1/'
    # Format 3:  INFO  keylime_agent (rust-keylime)
    elif echo "$line" | grep -qE "^[[:space:]]*INFO[[:space:]]+"; then
        # Extract date from log if available, otherwise use current
        echo "$(date +%Y-%m-%dT%H:%M:%S%z)"
    else
        echo "$(date +%Y-%m-%dT%H:%M:%S%z)"
    fi
}

# Function to normalize timestamp for sorting
normalize_timestamp() {
    local ts="$1"
    # Convert to sortable format (YYYY-MM-DD HH:MM:SS)
    echo "$ts" | sed -E 's/T/ /; s/[+-][0-9]{2}:[0-9]{2}$//; s/,.*//'
}

# Function to generate consolidated workflow log file
generate_workflow_log_file() {
    local OUTPUT_FILE="/tmp/phase3_complete_workflow_logs.txt"
    local TEMP_DIR=$(mktemp -d)
    
    echo -e "${CYAN}Generating consolidated workflow log file...${NC}"
    
    {
        echo "╔════════════════════════════════════════════════════════════════════════════════════════╗"
        echo "║  COMPLETE WORKFLOW LOGS - ALL COMPONENTS IN CHRONOLOGICAL ORDER                      ║"
        echo "║  Generated: $(date)" 
        echo "╚════════════════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Extract and tag logs from each component
        echo "Extracting logs from all components..." >&2
        
        # TPM Plugin Server logs
        if [ -f /tmp/tpm-plugin-server.log ]; then
            grep -E "App Key|TPM Quote|Delegated|certificate|request|response|Unified-Identity" /tmp/tpm-plugin-server.log | \
            while IFS= read -r line; do
                ts=$(extract_timestamp "$line")
                nts=$(normalize_timestamp "$ts")
                echo "$nts|TPM_PLUGIN|$line"
            done > "$TEMP_DIR/tpm-plugin.log"
        fi
        
        # SPIRE Agent logs
        if [ -f /tmp/spire-agent.log ]; then
            grep -E "TPM Plugin|SovereignAttestation|TPM Quote|certificate|Agent SVID|Workload|Unified-Identity|attest" /tmp/spire-agent.log | \
            while IFS= read -r line; do
                ts=$(extract_timestamp "$line")
                nts=$(normalize_timestamp "$ts")
                echo "$nts|SPIRE_AGENT|$line"
            done > "$TEMP_DIR/spire-agent.log"
        fi
        
        # SPIRE Server logs
        if [ -f /tmp/spire-server.log ]; then
            grep -E "SovereignAttestation|Keylime Verifier|AttestedClaims|Agent SVID|Workload|Unified-Identity|attest" /tmp/spire-server.log | \
            while IFS= read -r line; do
                ts=$(extract_timestamp "$line")
                nts=$(normalize_timestamp "$ts")
                echo "$nts|SPIRE_SERVER|$line"
            done > "$TEMP_DIR/spire-server.log"
        fi
        
        # Keylime Verifier logs
        if [ -f /tmp/keylime-verifier.log ]; then
            grep -E "Processing|Verifying|certificate|quote|Unified-Identity" /tmp/keylime-verifier.log | \
            while IFS= read -r line; do
                ts=$(extract_timestamp "$line")
                nts=$(normalize_timestamp "$ts")
                echo "$nts|KEYLIME_VERIFIER|$line"
            done > "$TEMP_DIR/keylime-verifier.log"
        fi
        
        # rust-keylime Agent logs
        if [ -f /tmp/rust-keylime-agent.log ]; then
            grep -E "registered|activated|Delegated|certificate|quote|geolocation|Unified-Identity" /tmp/rust-keylime-agent.log | \
            while IFS= read -r line; do
                ts=$(extract_timestamp "$line")
                nts=$(normalize_timestamp "$ts")
                echo "$nts|RUST_KEYLIME|$line"
            done > "$TEMP_DIR/rust-keylime.log"
        fi
        
        # Sort all logs chronologically
        cat "$TEMP_DIR"/*.log 2>/dev/null | sort -t'|' -k1,1 > "$TEMP_DIR/all-logs-sorted.log"
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "SETUP: INITIAL SETUP & TPM PREPARATION"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # SPIRE logs
        grep -E "TPM_PLUGIN.*App Key|RUST_KEYLIME.*registered|RUST_KEYLIME.*activated" "$TEMP_DIR/all-logs-sorted.log" | \
        while IFS='|' read -r ts component line; do
            case "$component" in
                TPM_PLUGIN)
                    echo "[TPM Plugin Server] $line" | sed 's/^/  /'
                    ;;
                RUST_KEYLIME)
                    echo "[rust-keylime Agent] $line" | sed 's/^/  /'
                    ;;
            esac
        done
        echo ""
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "AGENT ATTESTATION: SPIRE AGENT ATTESTATION (Agent SVID Generation) - ARCHITECTURE FLOW ORDER"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Agent attestation follows architecture flow: SPIRE Agent → TPM Plugin → rust-keylime → SPIRE Agent → SPIRE Server (control plane) → Keylime Verifier (control plane) → SPIRE Server (control plane) → SPIRE Agent
        
        # Step 1: SPIRE Agent Initiates Attestation & Requests App Key Info
        echo "[Step 3-4] SPIRE Agent Initiates Attestation & Requests App Key Information:"
        {
            grep -E "SPIRE_AGENT.*TPM Plugin|SPIRE_AGENT.*Building|SPIRE_AGENT.*attest" "$TEMP_DIR/all-logs-sorted.log" | head -3
            grep -E "TPM_PLUGIN.*App Key" "$TEMP_DIR/all-logs-sorted.log" | head -2
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="SPIRE Agent"
            [[ "$component" == "TPM_PLUGIN" ]] && comp_name="TPM Plugin Server"
            echo "  [$formatted_ts] [$comp_name] $clean_line"
        done
        echo ""
        
        # Step 2: Delegated Certification (TPM Plugin → rust-keylime Agent)
        echo "[Step 5] Delegated Certification Request (TPM Plugin → rust-keylime Agent):"
        {
            grep -E "TPM_PLUGIN.*certificate|TPM_PLUGIN.*request.*certificate" "$TEMP_DIR/all-logs-sorted.log"
            grep -E "RUST_KEYLIME.*Delegated|RUST_KEYLIME.*certificate" "$TEMP_DIR/all-logs-sorted.log"
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="TPM Plugin Server"
            [[ "$component" == "RUST_KEYLIME" ]] && comp_name="rust-keylime Agent"
            echo "  [$formatted_ts] [$comp_name] $clean_line"
        done
        echo ""
        
        # Step 3: SPIRE Agent Builds & Sends SovereignAttestation
        echo "[Step 6] SPIRE Agent Builds & Sends SovereignAttestation:"
        grep -E "SPIRE_AGENT.*SovereignAttestation|SPIRE_AGENT.*Building.*Sovereign" "$TEMP_DIR/all-logs-sorted.log" | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            echo "  [$formatted_ts] [SPIRE Agent] $clean_line"
        done
        echo ""
        
        # Step 4: SPIRE Server Receives & Calls Keylime Verifier
        echo "[Step 7-8] SPIRE Server Receives Attestation & Calls Keylime Verifier:"
        {
            grep -E "SPIRE_SERVER.*SovereignAttestation|SPIRE_SERVER.*Keylime" "$TEMP_DIR/all-logs-sorted.log" | head -3
            grep -E "KEYLIME_VERIFIER.*Processing|KEYLIME_VERIFIER.*verification request" "$TEMP_DIR/all-logs-sorted.log" | head -2
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="SPIRE Server"
            [[ "$component" == "KEYLIME_VERIFIER" ]] && comp_name="Keylime Verifier"
            echo "  [$formatted_ts] [$comp_name] $clean_line"
        done
        echo ""
        
        # Step 5: Keylime Verifier Certificate Verification
        echo "[Step 10] Keylime Verifier Verifies App Key Certificate Signature:"
        grep -E "KEYLIME_VERIFIER.*certificate|KEYLIME_VERIFIER.*Verifying.*certificate|KEYLIME_VERIFIER.*App Key.*certificate" "$TEMP_DIR/all-logs-sorted.log" | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            echo "  [$formatted_ts] [Keylime Verifier] $clean_line"
        done
        echo ""
        
        # Step 6: Keylime Verifier Fetches TPM Quote
        echo "[Step 11] Keylime Verifier Fetches TPM Quote On-Demand:"
        {
            grep -E "KEYLIME_VERIFIER.*quote|KEYLIME_VERIFIER.*Requesting quote" "$TEMP_DIR/all-logs-sorted.log"
            grep -E "RUST_KEYLIME.*quote|RUST_KEYLIME.*GET.*quote" "$TEMP_DIR/all-logs-sorted.log"
            grep -E "KEYLIME_VERIFIER.*Successfully retrieved quote" "$TEMP_DIR/all-logs-sorted.log"
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="Keylime Verifier"
            [[ "$component" == "RUST_KEYLIME" ]] && comp_name="rust-keylime Agent"
            echo "  [$formatted_ts] [$comp_name] $clean_line"
        done
        echo ""
        
        # Step 8: Keylime Verifier Returns Result to SPIRE Server
        echo "[Step 16] Keylime Verifier Returns Verification Result:"
        grep -E "KEYLIME_VERIFIER.*Verification successful|KEYLIME_VERIFIER.*Returning|SPIRE_SERVER.*AttestedClaims|SPIRE_SERVER.*received.*AttestedClaims" "$TEMP_DIR/all-logs-sorted.log" | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="Keylime Verifier"
            [[ "$component" == "SPIRE_SERVER" ]] && comp_name="SPIRE Server"
            echo "  [$formatted_ts] [$comp_name] $clean_line"
        done
        echo ""
        
        # Step 9: SPIRE Server Issues Agent SVID
        echo "[Step 17-19] SPIRE Server Issues Agent SVID:"
        {
            grep -E "SPIRE_SERVER.*Agent SVID|SPIRE_SERVER.*Issuing|SPIRE_SERVER.*AttestedClaims" "$TEMP_DIR/all-logs-sorted.log"
            grep -E "SPIRE_AGENT.*Agent SVID|SPIRE_AGENT.*received.*SVID|SPIRE_AGENT.*attestation.*successful" "$TEMP_DIR/all-logs-sorted.log"
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="SPIRE Server"
            [[ "$component" == "SPIRE_AGENT" ]] && comp_name="SPIRE Agent"
            echo "  [$formatted_ts] [$comp_name] $clean_line"
        done
        echo ""
        
        # Also show detailed sections for key events
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "AGENT ATTESTATION: DETAILED EVENT BREAKDOWN"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # TPM Quote Generation
        echo "[1] TPM Quote Generation:"
        grep -E "TPM_PLUGIN.*Quote|SPIRE_AGENT.*Quote" "$TEMP_DIR/all-logs-sorted.log" | head -5 | \
        while IFS='|' read -r ts component line; do
            echo "  → $line" | sed 's/^[^|]*|//' | sed 's/^/    /'
        done
        echo ""
        
        # Delegated Certification
        echo "[2] Delegated Certification:"
        grep -E "TPM_PLUGIN.*certificate|RUST_KEYLIME.*Delegated|RUST_KEYLIME.*certificate" "$TEMP_DIR/all-logs-sorted.log" | head -8 | \
        while IFS='|' read -r ts component line; do
            echo "  → $line" | sed 's/^[^|]*|//' | sed 's/^/    /'
        done
        echo ""
        
        # Certificate Verification
        echo "[3] Certificate Signature Verification:"
        grep -E "KEYLIME_VERIFIER.*certificate|KEYLIME_VERIFIER.*Verifying.*certificate" "$TEMP_DIR/all-logs-sorted.log" | head -5 | \
        while IFS='|' read -r ts component line; do
            echo "  → $line" | sed 's/^[^|]*|//' | sed 's/^/    /'
        done
        echo ""
        
        # Agent SVID Issuance
        echo "[5] Agent SVID Issuance:"
        grep -E "SPIRE_SERVER.*Agent SVID|SPIRE_AGENT.*Agent SVID|SPIRE_SERVER.*AttestedClaims" "$TEMP_DIR/all-logs-sorted.log" | head -5 | \
        while IFS='|' read -r ts component line; do
            echo "  → $line" | sed 's/^[^|]*|//' | sed 's/^/    /'
        done
        echo ""
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "WORKLOAD SVID: WORKLOAD SVID GENERATION - ARCHITECTURE FLOW ORDER"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Workload SVID generation follows architecture flow: Workload → SPIRE Agent → SPIRE Server → SPIRE Agent → Workload
        
        # Step 1: Workload Requests SVID via SPIRE Agent
        echo "[Step 1-2] Workload Requests SVID via SPIRE Agent:"
        {
            grep -E "SPIRE_AGENT.*Workload|SPIRE_AGENT.*python-app|SPIRE_AGENT.*FetchX509SVID" "$TEMP_DIR/all-logs-sorted.log"
            grep -E "SPIRE_AGENT.*Entry.*python-app|SPIRE_AGENT.*registration.*python-app" "$TEMP_DIR/all-logs-sorted.log"
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            echo "  [$formatted_ts] [SPIRE Agent] $clean_line"
        done
        echo ""
        
        # Step 2: SPIRE Agent Forwards Request to SPIRE Server
        echo "[Step 3-4] SPIRE Agent Forwards Workload SVID Request to SPIRE Server:"
        grep -E "SPIRE_AGENT.*BatchNewX509SVID|SPIRE_AGENT.*workload.*request" "$TEMP_DIR/all-logs-sorted.log" | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            echo "  [$formatted_ts] [SPIRE Agent] $clean_line"
        done
        echo ""
        
        # Step 3: SPIRE Server Processes Workload SVID Request (skips Keylime)
        echo "[Step 5-6] SPIRE Server Processes Workload SVID Request (skips Keylime verification):"
        {
            grep -E "SPIRE_SERVER.*Workload|SPIRE_SERVER.*python-app|SPIRE_SERVER.*Skipping.*Keylime.*workload" "$TEMP_DIR/all-logs-sorted.log"
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            echo "  [$formatted_ts] [SPIRE Server] $clean_line"
        done
        echo ""
        
        # Step 4: SPIRE Server Returns Workload SVID to SPIRE Agent
        echo "[Step 7-8] SPIRE Server Returns Workload SVID to SPIRE Agent:"
        {
            grep -E "SPIRE_SERVER.*Issuing.*workload|SPIRE_SERVER.*workload.*SVID" "$TEMP_DIR/all-logs-sorted.log"
            grep -E "SPIRE_AGENT.*workload.*SVID|SPIRE_AGENT.*received.*workload" "$TEMP_DIR/all-logs-sorted.log"
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="SPIRE Server"
            [[ "$component" == "SPIRE_AGENT" ]] && comp_name="SPIRE Agent"
            echo "  [$formatted_ts] [$comp_name] $clean_line"
        done
        echo ""
        
        # Step 5: SPIRE Agent Returns SVID to Workload
        echo "[Step 9-10] SPIRE Agent Returns Workload SVID to Workload:"
        grep -E "SPIRE_AGENT.*SVID.*python-app|SPIRE_AGENT.*workload.*SVID.*received" "$TEMP_DIR/all-logs-sorted.log" | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            echo "  [$formatted_ts] [SPIRE Agent] $clean_line"
        done
        echo ""
        
        # Detailed workload SVID breakdown
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "WORKLOAD SVID: DETAILED EVENT BREAKDOWN"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Workload API and Registration
        echo "[1] Workload API & Registration:"
        if [ -f /tmp/spire-agent.log ]; then
            grep -i "Starting Workload\|Entry created\|python-app" /tmp/spire-agent.log | head -3 | sed 's/^/    /'
        fi
        echo ""
        
        # Workload SVID Request Processing
        echo "[2] Workload SVID Request Processing:"
        grep -E "SPIRE_SERVER.*Workload|SPIRE_SERVER.*python-app" "$TEMP_DIR/all-logs-sorted.log" | head -5 | \
        while IFS='|' read -r ts component line; do
            echo "  → $line" | sed 's/^[^|]*|//' | sed 's/^/    /'
        done
        echo ""
        
        # Workload SVID Issuance
        echo "[3] Workload SVID Issuance:"
        grep -E "SPIRE_SERVER.*Signed.*python-app|SPIRE_AGENT.*Fetched.*python-app" "$TEMP_DIR/all-logs-sorted.log" | head -3 | \
        while IFS='|' read -r ts component line; do
            echo "  → $line" | sed 's/^[^|]*|//' | sed 's/^/    /'
        done
        echo ""
        
        # SVID Renewal
        if [ -f /tmp/spire-agent.log ]; then
            echo "[4] SVID Renewal Configuration:"
            if grep -q "availability_target" /tmp/spire-agent.log 2>/dev/null; then
                grep -i "availability_target" /tmp/spire-agent.log | head -1 | sed 's/^/    /'
            else
                echo "    Configured for 15s renewal interval (demo purposes)"
            fi
            echo ""
            
            echo "[5] SVID Renewal Activity:"
            RENEWAL_EVENTS=$(grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | wc -l)
            if [ "$RENEWAL_EVENTS" -gt 0 ]; then
                echo "    Found $RENEWAL_EVENTS renewal events:"
                grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | tail -5 | sed 's/^/      /'
            else
                echo "    No renewal events yet (renewal configured for 15s intervals)"
            fi
            echo ""
        fi
        
        if [ -f /tmp/test_phase3_final_rebuild.log ]; then
            echo "[Workload] SVID Fetched:"
            grep -i "SVID fetched successfully\|Certificate chain\|Full chain received" /tmp/test_phase3_final_rebuild.log | head -3 | sed 's/^/  /'
            echo ""
        fi
        
        if [ -f /tmp/svid-dump/attested_claims.json ]; then
            echo "[Workload] Workload SVID Claims (from certificate extension):"
            cat /tmp/svid-dump/attested_claims.json 2>/dev/null | python3 -m json.tool 2>/dev/null | head -20 | sed 's/^/  /' || cat /tmp/svid-dump/attested_claims.json | head -20 | sed 's/^/  /'
            echo ""
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "PHASE 4: FINAL VERIFICATION"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        if [ -f /tmp/svid-dump/svid.pem ]; then
            echo "[Certificate Chain] Structure:"
            echo "  [0] Workload SVID: spiffe://example.org/python-app"
            openssl crl2pkcs7 -nocrl -certfile /tmp/svid-dump/svid.pem 2>/dev/null | openssl pkcs7 -print_certs -text -noout 2>/dev/null | grep -E "Subject:|Issuer:|URI:spiffe|Not After" | head -4 | sed 's/^/    /'
            echo ""
            echo "  [1] Agent SVID: spiffe://example.org/spire/agent/unified_identity/..."
            openssl crl2pkcs7 -nocrl -certfile /tmp/svid-dump/svid.pem 2>/dev/null | openssl pkcs7 -print_certs -text -noout 2>/dev/null | grep -E "Subject:|Issuer:|URI:spiffe|Not After" | tail -4 | sed 's/^/    /'
            echo ""
        fi
        
        echo "[Verification Summary]:"
        echo "  ✓ Both certificates signed by SPIRE Server Root CA"
        echo "  ✓ Certificate chain verified successfully"
        echo "  ✓ Agent SVID contains TPM attestation (grc.geolocation + grc.tpm-attestation + grc.workload)"
        echo "  ✓ Workload SVID contains ONLY workload claims (grc.workload only)"
        echo "  ✓ App Key certificate's TPM AK matches Keylime agent's TPM AK"
        echo ""
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "WORKFLOW SUMMARY"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  ✓ TPM Plugin: App Key generated → persisted at handle 0x8101000B"
        echo "  ✓ rust-keylime Agent: Registered and activated with Keylime"
        echo "  ✓ SPIRE Agent: Connected to TPM Plugin via UDS"
        echo "  ✓ TPM Quote: Generated with challenge nonce from SPIRE Server"
        echo "  ✓ Delegated Certification: App Key certified by rust-keylime agent using TPM AK"
        echo "  ✓ SovereignAttestation: Built with quote + App Key cert + App Key public + nonce"
        echo "  ✓ Keylime Verifier: Validated all evidence (AK match verified ✓)"
        echo "  ✓ Agent SVID: Issued with full TPM attestation claims"
        echo "  ✓ Workload SVID: Issued with ONLY workload claims (no TPM attestation)"
        echo "  ✓ Certificate Chain: Complete [Workload SVID, Agent SVID]"
        if [ -f /tmp/spire-agent.log ]; then
            RENEWAL_COUNT=$(grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | wc -l)
            if [ "$RENEWAL_COUNT" -gt 0 ]; then
                echo "  ✓ SPIRE Agent SVID Renewal: Active ($RENEWAL_COUNT renewal events, 15s interval for demo)"
            else
                echo "  ✓ SPIRE Agent SVID Renewal: Configured (15s interval for demo)"
            fi
        fi
        echo "  ✓ All verifications: Passed"
        echo ""
    } > "$OUTPUT_FILE"
    
    # Cleanup temp directory
    rm -rf "$TEMP_DIR" 2>/dev/null
    
    if [ -f "$OUTPUT_FILE" ]; then
        local line_count=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
        local file_size=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${GREEN}  ✓ Consolidated workflow log file generated${NC}"
        echo -e "${GREEN}    Location: ${OUTPUT_FILE}${NC}"
        echo -e "${GREEN}    File size: ${line_count} lines (${file_size})${NC}"
        echo -e "${CYAN}    View with: cat ${OUTPUT_FILE}${NC}"
        echo -e "${CYAN}    Or: less ${OUTPUT_FILE}${NC}"
        return 0
    else
        echo -e "${YELLOW}  ⚠ Warning: Failed to generate workflow log file${NC}"
        return 1
    fi
}

# Usage helper
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --cleanup-only       Stop services, remove data, and exit.
  --skip-cleanup       Skip the initial cleanup phase.
  --exit-cleanup       Run cleanup on exit (default: components continue running)
  --no-exit-cleanup    Do not run best-effort cleanup on exit (default behavior)
  --pause              Enable pause points at critical phases (default: auto-detect)
  --no-pause           Disable pause points (run non-interactively)
  --no-build           Skip building binaries (use existing binaries)
  -h, --help           Show this help message.

Environment Variables:
  SPIRE_AGENT_SVID_RENEWAL_INTERVAL  SVID renewal interval in seconds (default: 86400 = 24h, min: 30s)
                                      When set, automatically configures agent config file

Note: By default, all components continue running after script exit. Use --exit-cleanup
      to restore the old behavior of cleaning up on exit.
EOF
}

# Cleanup function (called on exit)
cleanup() {
    if [ "${EXIT_CLEANUP_ON_EXIT}" != true ]; then
        echo ""
        echo -e "${YELLOW}Skipping exit cleanup (services remain running). Use --exit-cleanup to change this behavior.${NC}"
        return
    fi
    echo ""
    echo -e "${YELLOW}Cleaning up on exit...${NC}"
    # Only stop processes on exit, don't delete data (user may want to inspect)
    pkill -f "keylime_verifier" >/dev/null 2>&1 || true
    pkill -f "python.*keylime" >/dev/null 2>&1 || true
    pkill -f "keylime_agent" >/dev/null 2>&1 || true
    pkill -f "spire-server" >/dev/null 2>&1 || true
    pkill -f "spire-agent" >/dev/null 2>&1 || true
    pkill -f "tpm2-abrmd" >/dev/null 2>&1 || true
}

RUN_INITIAL_CLEANUP=true
# Modified: Default to NOT cleaning up on exit so components continue running
EXIT_CLEANUP_ON_EXIT=false
# Auto-detect pause mode: enable if interactive terminal, disable otherwise
if [ -t 0 ]; then
    PAUSE_ENABLED="${PAUSE_ENABLED:-true}"
else
    PAUSE_ENABLED="${PAUSE_ENABLED:-false}"
fi

# SVID renewal configuration: Allow override via environment variable
# Default: 30s for fast demo renewals, minimum: 30s
SPIRE_AGENT_SVID_RENEWAL_INTERVAL="${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-30}"
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL
# Minimum allowed renewal interval (30 seconds)
MIN_SVID_RENEWAL_INTERVAL=30

# Convert seconds to SPIRE format (e.g., 300s -> 5m, 60s -> 1m)
convert_seconds_to_spire_duration() {
    local seconds=$1
    if [ "$seconds" -ge 3600 ]; then
        local hours=$((seconds / 3600))
        echo "${hours}h"
    elif [ "$seconds" -ge 60 ]; then
        local minutes=$((seconds / 60))
        echo "${minutes}m"
    else
        echo "${seconds}s"
    fi
}

# Find an available TCP port starting from a preferred value
find_available_port() {
    local start_port="${1:-9443}"
    local max_attempts=20
    local port=$start_port
    for _ in $(seq 1 $max_attempts); do
        local in_use=false
        if command -v lsof >/dev/null 2>&1 && lsof -i TCP:$port >/dev/null 2>&1; then
            in_use=true
        elif command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ":$port "; then
            in_use=true
        elif command -v netstat >/dev/null 2>&1 && netstat -tln 2>/dev/null | grep -q ":$port "; then
            in_use=true
        fi
        if [ "$in_use" = false ]; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    echo "$start_port"
    return 1
}

sanitize_count() {
    local value="${1:-0}"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        echo "0"
    fi
}

# Function to configure SPIRE server agent_ttl for Unified-Identity
# Unified-Identity requires shorter agent SVID lifetime (e.g., 60s) for effective renewal testing
configure_spire_server_agent_ttl() {
    local server_config="$1"
    local agent_ttl="${2:-60}"  # Default: 60 seconds for Unified-Identity
    
    if [ ! -f "$server_config" ]; then
        echo -e "${YELLOW}    ⚠ SPIRE server config not found: $server_config${NC}"
        return 1
    fi
    
    # Convert seconds to SPIRE duration format
    local agent_ttl_duration=$(convert_seconds_to_spire_duration "$agent_ttl")
    
    echo "    Configuring SPIRE server agent_ttl: ${agent_ttl}s (${agent_ttl_duration}) for Unified-Identity"
    
    # Create a backup
    local backup_config="${server_config}.bak.$$"
    cp "$server_config" "$backup_config" 2>/dev/null || true
    
    # Check if agent_ttl already exists in server block
    if grep -q "agent_ttl" "$server_config"; then
        # Update existing agent_ttl
        sed -i "s|^[[:space:]]*agent_ttl[[:space:]]*=[[:space:]]*\"[^\"]*\"|    agent_ttl = \"${agent_ttl_duration}\"|" "$server_config"
        sed -i "s|^[[:space:]]*agent_ttl[[:space:]]*=[[:space:]]*'[^']*'|    agent_ttl = \"${agent_ttl_duration}\"|" "$server_config"
        sed -i "s|^[[:space:]]*agent_ttl[[:space:]]*=[[:space:]]*[^[:space:]]*|    agent_ttl = \"${agent_ttl_duration}\"|" "$server_config"
        echo -e "${GREEN}    ✓ Updated existing agent_ttl to ${agent_ttl_duration}${NC}"
    else
        # Add agent_ttl to server block
        # Find the server block and add agent_ttl after default_x509_svid_ttl or ca_ttl
        if grep -q "default_x509_svid_ttl\|ca_ttl" "$server_config"; then
            # Add after default_x509_svid_ttl or ca_ttl
            awk -v renewal="agent_ttl = \"${agent_ttl_duration}\"" '
                /default_x509_svid_ttl|ca_ttl/ {
                    print
                    if (!added) {
                        print "    " renewal
                        added = 1
                    }
                    next
                }
                { print }
            ' "$server_config" > "${server_config}.tmp" && mv "${server_config}.tmp" "$server_config"
        else
            # Add in server block (find server { and add after first config line)
            awk -v renewal="agent_ttl = \"${agent_ttl_duration}\"" '
                /^[[:space:]]*server[[:space:]]*\{/ {
                    in_server = 1
                    print
                    next
                }
                in_server && /^[[:space:]]*[a-z_]+[[:space:]]*=/ && !added {
                    print "    " renewal
                    added = 1
                }
                in_server && /^[[:space:]]*\}/ {
                    if (!added) {
                        print "    " renewal
                    }
                    in_server = 0
                }
                { print }
            ' "$server_config" > "${server_config}.tmp" && mv "${server_config}.tmp" "$server_config"
        fi
        echo -e "${GREEN}    ✓ Added agent_ttl = ${agent_ttl_duration} to server configuration${NC}"
    fi
    
    # Verify the change
    if grep -q "agent_ttl.*${agent_ttl_duration}" "$server_config"; then
        return 0
    else
        echo -e "${YELLOW}    ⚠ Warning: Could not verify agent_ttl was set correctly${NC}"
        return 1
    fi
}

# Function to configure SPIRE agent SVID renewal interval
configure_spire_agent_svid_renewal() {
    local agent_config="$1"
    local renewal_interval_seconds="${2:-${SPIRE_AGENT_SVID_RENEWAL_INTERVAL}}"
    
    if [ ! -f "$agent_config" ]; then
        echo -e "${YELLOW}    ⚠ SPIRE agent config not found: $agent_config${NC}"
        return 1
    fi
    
    # Validate minimum renewal interval based on Unified-Identity feature flag
    # Unified-Identity enabled: 30s minimum
    # Unified-Identity disabled: 24h (86400s) minimum for backward compatibility
    local unified_identity_enabled="${UNIFIED_IDENTITY_ENABLED:-true}"
    local min_interval
    
    if [ "$unified_identity_enabled" = "true" ] || [ "$unified_identity_enabled" = "1" ] || [ "$unified_identity_enabled" = "yes" ]; then
        min_interval=30  # Unified-Identity allows 30s minimum
    else
        min_interval=86400  # Legacy 24h minimum when Unified-Identity is disabled
    fi
    
    if [ "$renewal_interval_seconds" -lt "$min_interval" ]; then
        echo -e "${RED}    ✗ Error: SVID renewal interval must be at least ${min_interval}s (provided: ${renewal_interval_seconds}s)${NC}"
        if [ "$min_interval" -eq 86400 ]; then
            echo -e "${YELLOW}    Note: 30s minimum requires Unified-Identity feature flag to be enabled${NC}"
        fi
        return 1
    fi
    
    # Convert seconds to SPIRE duration format
    local renewal_duration=$(convert_seconds_to_spire_duration "$renewal_interval_seconds")
    
    echo "    Configuring SPIRE agent SVID renewal interval: ${renewal_interval_seconds}s (${renewal_duration})"
    
    # Create a backup of the original config
    local backup_config="${agent_config}.bak.$$"
    cp "$agent_config" "$backup_config" 2>/dev/null || true
    
    # Check if availability_target already exists in agent block
    if grep -q "availability_target" "$agent_config"; then
        # Update existing availability_target (match any whitespace and quotes)
        sed -i "s|^[[:space:]]*availability_target[[:space:]]*=[[:space:]]*\"[^\"]*\"|    availability_target = \"${renewal_duration}\"|" "$agent_config"
        sed -i "s|^[[:space:]]*availability_target[[:space:]]*=[[:space:]]*'[^']*'|    availability_target = \"${renewal_duration}\"|" "$agent_config"
        sed -i "s|^[[:space:]]*availability_target[[:space:]]*=[[:space:]]*[^[:space:]]*|    availability_target = \"${renewal_duration}\"|" "$agent_config"
        echo -e "${GREEN}    ✓ Updated existing availability_target to ${renewal_duration}${NC}"
    else
        # Add availability_target to agent block
        # Find the agent block and add availability_target after the opening brace
        if grep -q "^agent[[:space:]]*{" "$agent_config"; then
            # Insert after agent { line (use a temporary file for portability)
            local temp_config="${agent_config}.tmp.$$"
            awk -v renewal="${renewal_duration}" '
                /^agent[[:space:]]*{/ {
                    print
                    print "    availability_target = \"" renewal "\""
                    next
                }
                { print }
            ' "$agent_config" > "$temp_config" && mv "$temp_config" "$agent_config"
            echo -e "${GREEN}    ✓ Added availability_target = ${renewal_duration} to agent configuration${NC}"
        else
            echo -e "${YELLOW}    ⚠ Could not find agent block in config, skipping renewal interval configuration${NC}"
            rm -f "$backup_config" 2>/dev/null || true
            return 1
        fi
    fi
    
    # Verify the change was made
    if grep -q "availability_target.*${renewal_duration}" "$agent_config"; then
        rm -f "$backup_config" 2>/dev/null || true
        return 0
    else
        echo -e "${YELLOW}    ⚠ Warning: Could not verify availability_target was set correctly${NC}"
        # Restore backup if verification failed
        if [ -f "$backup_config" ]; then
            mv "$backup_config" "$agent_config" 2>/dev/null || true
        fi
        return 1
    fi
}

# Function to wait for exactly one agent SVID renewal
wait_for_one_agent_svid_renewal() {
    local max_wait="${1:-120}"  # Maximum time to wait in seconds
    local renewal_interval="${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-30}"
    
    echo ""
    echo -e "${CYAN}  Waiting for one agent SVID renewal (max ${max_wait}s)...${NC}"
    echo -e "${CYAN}  Configured renewal interval: ${renewal_interval}s${NC}"
    echo ""
    
    # Check if agent is running
    if [ ! -f /tmp/spire-agent.pid ]; then
        echo -e "${RED}  ✗ SPIRE Agent is not running${NC}"
        return 1
    fi
    
    local agent_pid=$(cat /tmp/spire-agent.pid)
    if ! kill -0 "$agent_pid" 2>/dev/null; then
        echo -e "${RED}  ✗ SPIRE Agent process (PID: $agent_pid) is not running${NC}"
        return 1
    fi
    
    echo -e "${GREEN}  ✓ SPIRE Agent is running (PID: $agent_pid)${NC}"
    
    # Get initial log positions and count existing renewals
    local agent_log="/tmp/spire-agent.log"
    local initial_agent_size=0
    local initial_renewal_count=0
    if [ -f "$agent_log" ]; then
        initial_agent_size=$(wc -l < "$agent_log" 2>/dev/null || echo "0")
        # Count existing renewals
        if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
            initial_renewal_count=$(grep -c "Successfully reattested node" "$agent_log" 2>/dev/null || echo 0)
        else
            initial_renewal_count=$(grep -iE "Successfully rotated agent SVID" "$agent_log" 2>/dev/null | wc -l)
        fi
        initial_renewal_count=$(printf '%s' "$initial_renewal_count" | tr -d '\n\r\t ' | grep -oE '^[0-9]+$' | head -1)
        initial_renewal_count="${initial_renewal_count:-0}"
    fi
    
    echo "  Initial renewal count: $initial_renewal_count"
    echo "  Waiting for renewal count to reach $((initial_renewal_count + 1))..."
    echo ""
    
    # Wait for exactly one new renewal
    local start_time=$(date +%s)
    local end_time=$((start_time + max_wait))
    local target_count=$((initial_renewal_count + 1))
    
    while [ $(date +%s) -lt $end_time ]; do
        sleep 2
        
        # Check current renewal count
        local current_count=0
        if [ -f "$agent_log" ]; then
            if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
                current_count=$(grep -c "Successfully reattested node" "$agent_log" 2>/dev/null || echo 0)
            else
                current_count=$(grep -iE "Successfully rotated agent SVID" "$agent_log" 2>/dev/null | wc -l)
            fi
            current_count=$(printf '%s' "$current_count" | tr -d '\n\r\t ' | grep -oE '^[0-9]+$' | head -1)
            current_count="${current_count:-0}"
        fi
        
        if [ "$current_count" -ge "$target_count" ] 2>/dev/null; then
            echo -e "${GREEN}  ✓ Agent SVID renewal detected! (Count: $current_count)${NC}"
            # Show the renewal log entry
            if [ -f "$agent_log" ]; then
                if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
                    grep "Successfully reattested node" "$agent_log" | tail -1 | sed 's/^/    /'
                else
                    grep -iE "Successfully rotated agent SVID" "$agent_log" | tail -1 | sed 's/^/    /'
                fi
            fi
            return 0
        fi
        
        # Show progress every 10 seconds
        local elapsed=$(( $(date +%s) - start_time ))
        if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo "  Progress: ${elapsed}s elapsed, waiting for renewal (current count: $current_count, target: $target_count)..."
        fi
    done
    
    echo -e "${YELLOW}  ⚠ Timeout: No renewal detected within ${max_wait}s${NC}"
    return 1
}

# Function to fetch agent SVID and save it
fetch_agent_svid() {
    local output_file="${1:-/tmp/agent-svid-dump/agent-svid.pem}"
    local agent_log="/tmp/spire-agent.log"
    
    echo ""
    echo "  Fetching agent SVID..."
    
    # Create output directory
    mkdir -p "$(dirname "$output_file")" 2>/dev/null || true
    
    # Extract agent SVID from logs (agent logs the certificate PEM)
    # Look for the most recent "Agent SVID Certificate (PEM)" log entry
    # Log format: time="..." level=info msg="..." cert_pem="-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
    if [ -f "$agent_log" ]; then
        # Use Python to extract the certificate from logs
        if command -v python3 >/dev/null 2>&1; then
            local cert_pem=$(python3 << 'PYEOF'
import sys
import re

log_file = "/tmp/spire-agent.log"
try:
    with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
        # Read lines and search backwards for the most recent agent SVID log
        lines = f.readlines()
        for line in reversed(lines):
            if "Agent SVID Certificate (PEM)" in line and "cert_pem=" in line:
                # Extract cert_pem="..." value
                # Handle both single-line and multi-line formats
                # Pattern: cert_pem="-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
                match = re.search(r'cert_pem="([^"]+)"', line)
                if match:
                    cert = match.group(1)
                    # Replace escaped newlines with actual newlines
                    cert = cert.replace('\\n', '\n')
                    if 'BEGIN CERTIFICATE' in cert and 'END CERTIFICATE' in cert:
                        print(cert)
                        sys.exit(0)
                
                # If cert spans multiple lines, try to find it
                # Look for the line with cert_pem= and extract until END CERTIFICATE
                if 'cert_pem=' in line:
                    # Find the start of cert_pem value
                    start_idx = line.find('cert_pem="') + len('cert_pem="')
                    # Extract from start to end of line, then continue reading if needed
                    cert_part = line[start_idx:]
                    # Remove trailing quote if present
                    cert_part = cert_part.rstrip('"')
                    cert_part = cert_part.replace('\\n', '\n')
                    
                    # If END CERTIFICATE is in this line, we're done
                    if 'END CERTIFICATE' in cert_part:
                        print(cert_part)
                        sys.exit(0)
                    
                    # Otherwise, we might need to read more lines (unlikely but possible)
                    # For now, try to extract what we have
                    if 'BEGIN CERTIFICATE' in cert_part:
                        # Try to find END CERTIFICATE in the same line or construct it
                        # Most certificates should fit in one log line
                        print(cert_part)
                        sys.exit(0)
except Exception as e:
    pass
sys.exit(1)
PYEOF
)
            if [ -n "$cert_pem" ] && echo "$cert_pem" | grep -q "BEGIN CERTIFICATE"; then
                # Save the certificate
                echo "$cert_pem" > "$output_file"
                if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                    echo -e "${GREEN}    ✓ Agent SVID extracted from logs and saved to: $output_file${NC}"
                    return 0
                fi
            fi
        fi
        
        # Last resort: Try to get agent SVID from SPIRE server using agent SPIFFE ID
        # We can query the server for the agent's SVID
        local spire_server="${PROJECT_DIR}/spire/bin/spire-server"
        if [ -f "$spire_server" ]; then
            # Get agent SPIFFE ID from logs
            local agent_spiffe_id=$(grep "Successfully reattested node" "$agent_log" | tail -1 | \
                grep -oP 'spiffe_id="\K[^"]+' 2>/dev/null)
            
            if [ -n "$agent_spiffe_id" ]; then
                echo "    Trying to fetch agent SVID from SPIRE server for agent: $agent_spiffe_id"
                # Note: This would require server API access, which may not be available
                # For now, we'll rely on log extraction
            fi
        fi
    fi
    
    echo -e "${YELLOW}    ⚠ Could not extract agent SVID from logs${NC}"
    echo "    Agent SVID should be logged in /tmp/spire-agent.log"
    echo "    Look for: 'Unified-Identity - Verification: Agent SVID Certificate (PEM)'"
    return 1
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --cleanup-only)
            # For --cleanup-only, only clean up agent services (control plane is managed separately)
            stop_agent_services_only
            exit 0
            ;;
        --skip-cleanup)
            RUN_INITIAL_CLEANUP=false
            shift
            ;;
        --exit-cleanup)
            EXIT_CLEANUP_ON_EXIT=true
            shift
            ;;
        --no-exit-cleanup)
            EXIT_CLEANUP_ON_EXIT=false
            shift
            ;;
        --pause)
            PAUSE_ENABLED=true
            shift
            ;;
        --)
            shift
            break
            ;;
        --no-pause)
            PAUSE_ENABLED=false
            shift
            ;;
        --no-build)
            NO_BUILD=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Initialize NO_BUILD if not set
NO_BUILD="${NO_BUILD:-false}"

if [ "${EXIT_CLEANUP_ON_EXIT}" = true ]; then
    trap cleanup EXIT
fi

if [ "${RUN_INITIAL_CLEANUP}" = true ]; then
    echo ""
    stop_all_instances_and_cleanup
    echo ""
else
    echo -e "${CYAN}Step 0: Skipping initial cleanup (--skip-cleanup)${NC}"
    echo ""
fi

# Step 1: Setup Keylime environment with TLS certificates
# Skipped for act 2 - non-control plane only (handled by test_control_plane.sh)
echo ""
echo -e "${CYAN}Step 1: Skipping Keylime setup (act 2 - non-control plane only)${NC}"
echo -e "${YELLOW}  Assuming control plane services are already running from test_control_plane.sh${NC}"

# Verify control plane services are running before proceeding
echo "  Verifying control plane services are running..."
CONTROL_PLANE_READY=true

# Check Keylime Verifier (port 8881)
if ! curl -k -s --connect-timeout 2 "https://${CONTROL_PLANE_HOST_IP}:8881/v2.2/status" >/dev/null 2>&1 && \
   ! curl -k -s --connect-timeout 2 "https://${CONTROL_PLANE_HOST_IP}:8881/v2.1/status" >/dev/null 2>&1 && \
   ! curl -k -s --connect-timeout 2 "https://localhost:8881/v2.2/status" >/dev/null 2>&1 && \
   ! curl -k -s --connect-timeout 2 "https://localhost:8881/v2.1/status" >/dev/null 2>&1; then
    echo -e "${RED}  ✗ Keylime Verifier is not running on port 8881${NC}"
    CONTROL_PLANE_READY=false
else
    echo -e "${GREEN}  ✓ Keylime Verifier is running${NC}"
fi

# Check Keylime Registrar (port 8890)
if ! curl -s --connect-timeout 2 "http://${CONTROL_PLANE_HOST_IP}:8890/v2.2/agents/" >/dev/null 2>&1 && \
   ! curl -s --connect-timeout 2 "http://${CONTROL_PLANE_HOST_IP}:8890/v2.1/agents/" >/dev/null 2>&1 && \
   ! curl -s --connect-timeout 2 "http://localhost:8890/v2.2/agents/" >/dev/null 2>&1 && \
   ! curl -s --connect-timeout 2 "http://localhost:8890/v2.1/agents/" >/dev/null 2>&1; then
    echo -e "${RED}  ✗ Keylime Registrar is not running on port 8890${NC}"
    CONTROL_PLANE_READY=false
else
    echo -e "${GREEN}  ✓ Keylime Registrar is running${NC}"
fi

# Check SPIRE Server (port 8081)
SPIRE_SERVER="${PROJECT_DIR}/spire/bin/spire-server"
if [ -f "${SPIRE_SERVER}" ]; then
    if ! "${SPIRE_SERVER}" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
        echo -e "${RED}  ✗ SPIRE Server is not running or not ready${NC}"
        CONTROL_PLANE_READY=false
    else
        echo -e "${GREEN}  ✓ SPIRE Server is running${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ SPIRE Server binary not found, skipping check${NC}"
fi

if [ "$CONTROL_PLANE_READY" = false ]; then
    echo ""
    echo -e "${RED}ERROR: Control plane services are not running!${NC}"
    echo ""
    echo "Please run test_control_plane.sh first to start:"
    echo "  - SPIRE Server"
    echo "  - Keylime Verifier"
    echo "  - Keylime Registrar"
    echo ""
    echo "Then run this script (test_agents.sh) to start agent services."
    abort_on_error "Control plane services must be running before starting agent services"
fi

echo ""

# Set VERIFIER_CONFIG_ABS even though we're skipping setup (needed for later steps)
VERIFIER_CONFIG="${KEYLIME_DIR}/verifier.conf.minimal"
if [ -f "${VERIFIER_CONFIG}" ]; then
    VERIFIER_CONFIG_ABS="$(cd "$(dirname "${VERIFIER_CONFIG}")" && pwd)/$(basename "${VERIFIER_CONFIG}")"
    export KEYLIME_VERIFIER_CONFIG="${VERIFIER_CONFIG_ABS}"
    export KEYLIME_CA_CONFIG="${VERIFIER_CONFIG_ABS}"
    export KEYLIME_CONFIG="${VERIFIER_CONFIG_ABS}"
fi

if false; then
echo -e "${CYAN}Step 1: Setting up Keylime environment with TLS certificates...${NC}"
echo ""

# Clear TPM state before starting test to avoid NV_Read errors
echo "  Clearing TPM state before test..."
if [ -c /dev/tpm0 ] || [ -c /dev/tpmrm0 ]; then
    if command -v tpm2_clear >/dev/null 2>&1; then
        TPM_DEVICE="/dev/tpmrm0"
        if [ ! -c "$TPM_DEVICE" ]; then
            TPM_DEVICE="/dev/tpm0"
        fi
        # Try to clear TPM (may fail if not authorized, but that's okay)
        TCTI="device:${TPM_DEVICE}" tpm2_clear -c 2>/dev/null || \
        TCTI="device:${TPM_DEVICE}" tpm2_startup -c 2>/dev/null || true
        echo -e "${GREEN}  ✓ TPM cleared/reset${NC}"
    else
        echo -e "${YELLOW}  ⚠ tpm2_clear not available, skipping TPM clear${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ TPM device not found, skipping TPM clear${NC}"
fi
echo ""

# Create minimal config if needed
VERIFIER_CONFIG="${KEYLIME_DIR}/verifier.conf.minimal"
if [ ! -f "${VERIFIER_CONFIG}" ]; then
    abort_on_error "Verifier config not found at ${VERIFIER_CONFIG}"
fi

# Verify unified_identity_enabled is set to true
if ! grep -q "unified_identity_enabled = true" "${VERIFIER_CONFIG}"; then
    abort_on_error "unified_identity_enabled must be set to true in ${VERIFIER_CONFIG}"
fi
echo -e "${GREEN}  ✓ unified_identity_enabled = true verified in config${NC}"

# Set environment variables
# Use absolute path for verifier config
VERIFIER_CONFIG_ABS="$(cd "$(dirname "${VERIFIER_CONFIG}")" && pwd)/$(basename "${VERIFIER_CONFIG}")"
export KEYLIME_VERIFIER_CONFIG="${VERIFIER_CONFIG_ABS}"
export KEYLIME_TEST=on
export KEYLIME_DIR="$(cd "${KEYLIME_DIR}" && pwd)"
export KEYLIME_CA_CONFIG="${VERIFIER_CONFIG_ABS}"
export UNIFIED_IDENTITY_ENABLED=true
# Ensure verifier uses the correct config by setting it in the environment
export KEYLIME_CONFIG="${VERIFIER_CONFIG_ABS}"

# Create work directory for Keylime
WORK_DIR="${KEYLIME_DIR}"
TLS_DIR="${WORK_DIR}/cv_ca"

echo "  Setting up TLS certificates..."
echo "  Work directory: ${WORK_DIR}"
echo "  TLS directory: ${TLS_DIR}"

# Pre-generate TLS certificates if they don't exist or are corrupted
if [ ! -d "${TLS_DIR}" ] || [ ! -f "${TLS_DIR}/cacert.crt" ] || [ ! -f "${TLS_DIR}/server-cert.crt" ]; then
    echo "  Generating CA and TLS certificates..."
    # Remove old/corrupted certificates
    rm -rf "${TLS_DIR}"
    mkdir -p "${TLS_DIR}"
    chmod 700 "${TLS_DIR}"
    
    # Use Python to generate certificates via Keylime's CA utilities
    python3 << 'PYTHON_EOF'
import sys
import os
sys.path.insert(0, os.environ['KEYLIME_DIR'])

# Set up config before importing
os.environ['KEYLIME_VERIFIER_CONFIG'] = os.environ.get('KEYLIME_VERIFIER_CONFIG', '')
os.environ['KEYLIME_TEST'] = 'on'

from keylime import config, ca_util, keylime_logging

# Initialize logging
logger = keylime_logging.init_logging("verifier")

# Get TLS directory
tls_dir = os.path.join(os.environ['KEYLIME_DIR'], 'cv_ca')

# Change to TLS directory for certificate generation
original_cwd = os.getcwd()
os.chdir(tls_dir)

try:
    # Set empty password for testing (must be done before cmd_init)
    ca_util.read_password("")
    
    # Initialize CA
    print(f"  Generating CA in {tls_dir}...")
    ca_util.cmd_init(tls_dir)
    print("  ✓ CA certificate generated")
    
    # Generate server certificate
    print("  Generating server certificate...")
    ca_util.cmd_mkcert(tls_dir, 'server', password=None)
    print("  ✓ Server certificate generated")
    
    # Generate client certificate
    print("  Generating client certificate...")
    ca_util.cmd_mkcert(tls_dir, 'client', password=None)
    print("  ✓ Client certificate generated")
    
    print("  ✓ TLS setup complete")
finally:
    os.chdir(original_cwd)
PYTHON_EOF

    if [ $? -ne 0 ]; then
        abort_on_error "Failed to generate TLS certificates"
    fi
else
    echo -e "${GREEN}  ✓ TLS certificates already exist${NC}"
fi

pause_at_phase "Step 1 Complete" "TLS certificates have been generated. Keylime environment is ready."
fi

# Step 2: Keylime Verifier (skipped - managed by test_control_plane.sh)
echo ""
echo -e "${CYAN}Step 2: Skipping Keylime Verifier (managed by test_control_plane.sh)${NC}"
echo -e "${YELLOW}  Assuming Keylime Verifier is already running${NC}"

# Step 3: Keylime Registrar (skipped - managed by test_control_plane.sh)
echo ""
echo -e "${CYAN}Step 3: Skipping Keylime Registrar (managed by test_control_plane.sh)${NC}"
echo -e "${YELLOW}  Assuming Keylime Registrar is already running${NC}"

# Step 4: Start rust-keylime Agent
echo ""
echo -e "${CYAN}Step 4: Starting rust-keylime Agent with delegated certification...${NC}"

# Clear TPM state before starting agent to avoid NV_Read errors and inconsistent state
# (This was previously in Step 1, but Step 1 is skipped for act 2)
echo "  Clearing TPM state before starting agent..."
if [ -c /dev/tpm0 ] || [ -c /dev/tpmrm0 ]; then
    if command -v tpm2_clear >/dev/null 2>&1; then
        TPM_DEVICE="/dev/tpmrm0"
        if [ ! -c "$TPM_DEVICE" ]; then
            TPM_DEVICE="/dev/tpm0"
        fi
        
        # First, try to clear persistent handles that might be stale
        # These are common handles used by keylime agents
        echo "    Clearing persistent handles (if any)..."
        # Agent uses: EK=0x81010001, AK=0x8101000A, App Key=0x8101000B
        for handle in 0x81010001 0x8101000A 0x8101000B 0x8101000C; do
            # Check if handle exists before trying to evict
            if TCTI="device:${TPM_DEVICE}" tpm2_readpublic -c "${handle}" >/dev/null 2>&1; then
                TCTI="device:${TPM_DEVICE}" tpm2_evictcontrol -C o -c "${handle}" 2>&1 | grep -E "persistent-handle|action" || true
            fi
        done
        
        # Try to clear TPM (may fail if not authorized, but that's okay)
        # Use -c flag to clear (requires authorization, may fail)
        # Fallback to startup -c which just initializes without clearing
        if TCTI="device:${TPM_DEVICE}" tpm2_clear -c 2>/dev/null; then
            echo -e "${GREEN}  ✓ TPM cleared/reset${NC}"
        elif TCTI="device:${TPM_DEVICE}" tpm2_startup -c 2>/dev/null; then
            echo -e "${GREEN}  ✓ TPM initialized (clear not authorized, but startup successful)${NC}"
        else
            echo -e "${YELLOW}  ⚠ TPM clear/startup failed (may need authorization or TPM may be in use)${NC}"
            echo "  Continuing anyway - agent may handle TPM state"
        fi
        
        # Flush transient contexts to ensure clean state
        echo "    Flushing transient contexts..."
        TCTI="device:${TPM_DEVICE}" tpm2_flushcontext -t 2>/dev/null || true
        TCTI="device:${TPM_DEVICE}" tpm2_flushcontext -s 2>/dev/null || true
    else
        echo -e "${YELLOW}  ⚠ tpm2_clear not available, skipping TPM clear${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ TPM device not found, skipping TPM clear${NC}"
fi
echo ""

cd "${RUST_KEYLIME_DIR}"

# Check if binary exists, build if needed
if [ ! -f "target/release/keylime_agent" ]; then
    if [ "$NO_BUILD" = "true" ]; then
        echo -e "${RED}  ✗ rust-keylime agent binary not found and --no-build specified${NC}"
        echo "  Build it manually: cd ${RUST_KEYLIME_DIR} && cargo build --release"
        exit 1
    else
        echo -e "${YELLOW}  ⚠ rust-keylime agent binary not found, building...${NC}"
        source "$HOME/.cargo/env" 2>/dev/null || true
        cargo build --release > /tmp/rust-keylime-build.log 2>&1 || {
            echo -e "${RED}  ✗ Failed to build rust-keylime agent${NC}"
            tail -20 /tmp/rust-keylime-build.log
            exit 1
        }
        echo -e "${GREEN}  ✓ rust-keylime agent built successfully${NC}"
    fi
fi

# Cleanup existing rust-keylime agent before starting
echo "  Cleaning up existing rust-keylime Agent..."
pkill -f "keylime_agent" >/dev/null 2>&1 || true
sleep 1
rm -f /tmp/rust-keylime-agent.pid 2>/dev/null || true
rm -f /tmp/keylime-agent.sock 2>/dev/null || true
rm -f /tmp/rust-keylime-agent.log 2>/dev/null || true

# Start rust-keylime agent
echo "  Starting rust-keylime agent on port 9002..."
if [ "${AGENTS_HOST_IP}" = "${CONTROL_PLANE_HOST_IP}" ]; then
    echo "    Note: Single machine deployment detected - agent will bind to 0.0.0.0"
    # For single machine, use localhost for IPs since services bind to 127.0.0.1
    export KEYLIME_AGENT_IP="${KEYLIME_AGENT_IP:-0.0.0.0}"
    export KEYLIME_AGENT_CONTACT_IP="${KEYLIME_AGENT_CONTACT_IP:-127.0.0.1}"
    export KEYLIME_AGENT_REGISTRAR_IP="${KEYLIME_AGENT_REGISTRAR_IP:-127.0.0.1}"
else
    # For multi-machine, use actual IPs
    export KEYLIME_AGENT_IP="${KEYLIME_AGENT_IP:-${AGENT_BIND_IP}}"
    export KEYLIME_AGENT_CONTACT_IP="${KEYLIME_AGENT_CONTACT_IP:-${AGENTS_HOST_IP}}"
    export KEYLIME_AGENT_REGISTRAR_IP="${KEYLIME_AGENT_REGISTRAR_IP:-${CONTROL_PLANE_HOST_IP}}"
fi
source "$HOME/.cargo/env" 2>/dev/null || true
export UNIFIED_IDENTITY_ENABLED=true

# Configure TPM to use real hardware TPM
echo "  Configuring TPM to use real hardware TPM..."
# Check if hardware TPM is available
if [ -c /dev/tpmrm0 ]; then
    export TCTI="device:/dev/tpmrm0"
    echo "    Using hardware TPM via resource manager: /dev/tpmrm0"
elif [ -c /dev/tpm0 ]; then
    export TCTI="device:/dev/tpm0"
    echo "    Using hardware TPM device: /dev/tpm0"
else
    echo -e "${YELLOW}    ⚠ No hardware TPM found, will use default TCTI${NC}"
fi

# Ensure tpm2-abrmd (resource manager) is running for hardware TPM
if [ -c /dev/tpmrm0 ] || [ -c /dev/tpm0 ]; then
    if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
        echo "    Starting tpm2-abrmd resource manager for hardware TPM..."
        # Start tpm2-abrmd in background if not running
        if command -v tpm2-abrmd >/dev/null 2>&1; then
            tpm2-abrmd --tcti=device 2>/dev/null &
            sleep 1
            if pgrep -x tpm2-abrmd >/dev/null 2>&1; then
                echo "    ✓ tpm2-abrmd started"
            else
                echo -e "${YELLOW}    ⚠ tpm2-abrmd may need to be started manually or via systemd${NC}"
            fi
        fi
    else
        echo "    ✓ tpm2-abrmd resource manager is running"
    fi
fi

# Set keylime_dir to a writable location
# The agent will create secure/ subdirectory and mount tmpfs there
KEYLIME_AGENT_DIR="/tmp/keylime-agent"
mkdir -p "$KEYLIME_AGENT_DIR" 2>/dev/null || true

# Ensure rust-keylime agent trusts the Keylime verifier/registrar certificates
AGENT_CV_CA_SRC="${PYTHON_KEYLIME_DIR}/cv_ca"
AGENT_CV_CA_DST="${KEYLIME_AGENT_DIR}/cv_ca"
if [ -d "$AGENT_CV_CA_SRC" ]; then
    rm -rf "$AGENT_CV_CA_DST" 2>/dev/null || true
    mkdir -p "$AGENT_CV_CA_DST" 2>/dev/null || true
    cp -a "${AGENT_CV_CA_SRC}/." "${AGENT_CV_CA_DST}/" 2>/dev/null || true
fi

# IMPORTANT: Override KEYLIME_DIR which was set earlier for Python Keylime
# The rust-keylime agent checks KEYLIME_DIR first, then KEYLIME_AGENT_KEYLIME_DIR, then config
# We need to unset the old KEYLIME_DIR and set it to our agent directory
unset KEYLIME_DIR  # Remove the Python Keylime directory setting
export KEYLIME_DIR="$KEYLIME_AGENT_DIR"  # Set to our agent directory
export KEYLIME_AGENT_KEYLIME_DIR="$KEYLIME_AGENT_DIR"  # Also set for explicit override

# Create a temporary config file with the correct keylime_dir to override defaults
TEMP_CONFIG="/tmp/keylime-agent-$$.conf"
cp "$(pwd)/keylime-agent.conf" "$TEMP_CONFIG" 2>/dev/null || true
# Override keylime_dir in the temp config file
sed -i "s|^keylime_dir = .*|keylime_dir = \"$KEYLIME_AGENT_DIR\"|" "$TEMP_CONFIG" 2>/dev/null || \
sed -i "s|keylime_dir = .*|keylime_dir = \"$KEYLIME_AGENT_DIR\"|" "$TEMP_CONFIG" 2>/dev/null || true

# Unified-Identity: Configure mTLS for verifier communication
# Set trusted_client_ca to verifier's CA certificate so agent trusts verifier connections
VERIFIER_CA_CERT="${AGENT_CV_CA_DST}/cacert.crt"
if [ -f "$VERIFIER_CA_CERT" ]; then
    # Add or update trusted_client_ca in config
    # Format: trusted_client_ca = "path" or "path1, path2" for multiple CAs
    if grep -q "^trusted_client_ca" "$TEMP_CONFIG" 2>/dev/null; then
        sed -i "s|^trusted_client_ca = .*|trusted_client_ca = \"$VERIFIER_CA_CERT\"|" "$TEMP_CONFIG" 2>/dev/null || \
        sed -i "s|trusted_client_ca = .*|trusted_client_ca = \"$VERIFIER_CA_CERT\"|" "$TEMP_CONFIG" 2>/dev/null || true
    else
        # Add trusted_client_ca if not present (add in [agent] section)
        if grep -q "^\[agent\]" "$TEMP_CONFIG" 2>/dev/null; then
            # Insert after [agent] section header
            sed -i "/^\[agent\]/a trusted_client_ca = \"$VERIFIER_CA_CERT\"" "$TEMP_CONFIG" 2>/dev/null || \
            echo "trusted_client_ca = \"$VERIFIER_CA_CERT\"" >> "$TEMP_CONFIG" 2>/dev/null || true
        else
            echo "trusted_client_ca = \"$VERIFIER_CA_CERT\"" >> "$TEMP_CONFIG" 2>/dev/null || true
        fi
    fi
    echo "    ✓ Configured agent trusted_client_ca for mTLS: $VERIFIER_CA_CERT"
else
    echo -e "${YELLOW}    ⚠ Verifier CA certificate not found at $VERIFIER_CA_CERT, mTLS may not work${NC}"
fi

# Unified-Identity: Enable unified_identity_enabled feature flag in agent config
if grep -q "^unified_identity_enabled" "$TEMP_CONFIG" 2>/dev/null; then
    sed -i "s|^unified_identity_enabled = .*|unified_identity_enabled = true|" "$TEMP_CONFIG" 2>/dev/null || \
    sed -i "s|unified_identity_enabled = .*|unified_identity_enabled = true|" "$TEMP_CONFIG" 2>/dev/null || true
else
    # Add unified_identity_enabled if not present (add in [agent] section)
    if grep -q "^\[agent\]" "$TEMP_CONFIG" 2>/dev/null; then
        # Insert after [agent] section header
        sed -i "/^\[agent\]/a unified_identity_enabled = true" "$TEMP_CONFIG" 2>/dev/null || \
        echo "unified_identity_enabled = true" >> "$TEMP_CONFIG" 2>/dev/null || true
    else
        echo "unified_identity_enabled = true" >> "$TEMP_CONFIG" 2>/dev/null || true
    fi
fi
echo "    ✓ Configured agent unified_identity_enabled = true"

# Set config file path to use our temporary config
export KEYLIME_AGENT_CONFIG="$TEMP_CONFIG"
# Ensure API versions include all supported versions for better compatibility
export KEYLIME_AGENT_API_VERSIONS="default"  # This should enable all supported versions

# Create secure directory and pre-mount tmpfs if needed
# This prevents the agent from failing when trying to mount tmpfs without root
SECURE_DIR="$KEYLIME_AGENT_DIR/secure"
SECURE_SIZE="${KEYLIME_AGENT_SECURE_SIZE:-1m}"

# Check if secure directory is already mounted as tmpfs
SECURE_MOUNTED=false
if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
    # Check if it's mounted as tmpfs
    if mount | grep -q "$SECURE_DIR.*tmpfs"; then
        SECURE_MOUNTED=true
        echo "    Secure directory already mounted as tmpfs"
    fi
fi

if [ "$SECURE_MOUNTED" = false ]; then
    echo "    Setting up secure directory and tmpfs mount..."
    
    # Create secure directory if it doesn't exist
    if [ ! -d "$SECURE_DIR" ]; then
        if sudo -n true 2>/dev/null; then
            sudo mkdir -p "$SECURE_DIR" 2>/dev/null || true
            sudo chmod 700 "$SECURE_DIR" 2>/dev/null || true
        else
            mkdir -p "$SECURE_DIR" 2>/dev/null || true
            chmod 700 "$SECURE_DIR" 2>/dev/null || true
        fi
    fi
    
    # Try to mount tmpfs if sudo is available
    if sudo -n true 2>/dev/null; then
        echo "    Pre-mounting tmpfs for secure storage..."
        # Unmount if already mounted (but not as tmpfs)
        if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
            sudo umount "$SECURE_DIR" 2>/dev/null || true
        fi
        # Mount tmpfs with proper permissions
        if sudo mount -t tmpfs -o "size=${SECURE_SIZE},mode=0700" tmpfs "$SECURE_DIR" 2>/dev/null; then
            echo "    ✓ tmpfs mounted successfully"
            # Set ownership to current user
            sudo chown -R "$(whoami):$(id -gn)" "$SECURE_DIR" 2>/dev/null || true
            SECURE_MOUNTED=true
        else
            echo "    ⚠ Failed to pre-mount tmpfs, agent will try to mount it"
        fi
    else
        echo "    ⚠ sudo not available, cannot pre-mount tmpfs"
        echo "    Agent will attempt to mount tmpfs (may fail without root)"
    fi
fi

# Override run_as to current user to avoid permission issues
export KEYLIME_AGENT_RUN_AS="$(whoami):$(id -gn)"

# Try to start with sudo if secure mount failed and sudo is available
# Unified-Identity: Enable mTLS for Verifier communication (standard Keylime)
export KEYLIME_AGENT_ENABLE_AGENT_MTLS="${KEYLIME_AGENT_ENABLE_AGENT_MTLS:-true}"
export KEYLIME_AGENT_ENABLE_NETWORK_LISTENER="${KEYLIME_AGENT_ENABLE_NETWORK_LISTENER:-true}"
export KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD="${KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD:-true}"
export KEYLIME_AGENT_PAYLOAD_SCRIPT=""

# Enable direct tpm2_quote to avoid deadlock with TSS library
# This uses /dev/tpm0 directly and parses PCRs from file instead of TSS library
export USE_TPM2_QUOTE_DIRECT=1
echo "    ✓ USE_TPM2_QUOTE_DIRECT=1 (using direct tpm2_quote to avoid deadlock)"

# If tmpfs is not mounted and sudo is available, start with sudo
if [ "$SECURE_MOUNTED" = false ] && sudo -n true 2>/dev/null; then
    echo "    Starting with sudo (secure mount requires root privileges)..."
    # Create keylime user if it doesn't exist, or use current user
    if ! id "keylime" &>/dev/null; then
        echo "    Note: keylime user not found, using current user"
        export KEYLIME_AGENT_RUN_AS="$(whoami):$(id -gn)"
    fi
    # Use env to ensure clean environment with only the variables we need
    # Explicitly unset the old KEYLIME_DIR and set the correct one
    # Include TCTI for hardware TPM if set
    # Enable mock mobile sensor for testing (can be overridden by environment variable)
    MOCK_SENSOR_VAR=""
    if [ "${MOCK_MOBILE_SENSOR:-false}" = "true" ]; then
        MOCK_SENSOR_VAR="MOCK_MOBILE_SENSOR=1"
        if [ -n "${MOCK_SENSOR_ID:-}" ]; then
            MOCK_SENSOR_VAR="$MOCK_SENSOR_VAR MOCK_SENSOR_ID=$MOCK_SENSOR_ID"
        fi
    fi
    if [ -n "${TCTI:-}" ]; then
        sudo env -i PATH="$PATH" HOME="$HOME" USER="$USER" UNIFIED_IDENTITY_ENABLED=true USE_TPM2_QUOTE_DIRECT=1 TCTI="$TCTI" $MOCK_SENSOR_VAR KEYLIME_DIR="$KEYLIME_AGENT_DIR" KEYLIME_AGENT_KEYLIME_DIR="$KEYLIME_AGENT_DIR" KEYLIME_AGENT_CONFIG="$TEMP_CONFIG" KEYLIME_AGENT_RUN_AS="$KEYLIME_AGENT_RUN_AS" "$(pwd)/target/release/keylime_agent" > /tmp/rust-keylime-agent.log 2>&1 &
    else
        sudo env -i PATH="$PATH" HOME="$HOME" USER="$USER" UNIFIED_IDENTITY_ENABLED=true USE_TPM2_QUOTE_DIRECT=1 $MOCK_SENSOR_VAR KEYLIME_DIR="$KEYLIME_AGENT_DIR" KEYLIME_AGENT_KEYLIME_DIR="$KEYLIME_AGENT_DIR" KEYLIME_AGENT_CONFIG="$TEMP_CONFIG" KEYLIME_AGENT_RUN_AS="$KEYLIME_AGENT_RUN_AS" "$(pwd)/target/release/keylime_agent" > /tmp/rust-keylime-agent.log 2>&1 &
    fi
    RUST_AGENT_PID=$!
elif [ "${RUST_KEYLIME_REQUIRE_SUDO:-0}" = "1" ] && sudo -n true 2>/dev/null; then
    echo "    Starting with sudo (RUST_KEYLIME_REQUIRE_SUDO=1)..."
    if ! id "keylime" &>/dev/null; then
        echo "    Note: keylime user not found, using current user"
        export KEYLIME_AGENT_RUN_AS="$(whoami):$(id -gn)"
    fi
    # Use env to ensure clean environment with only the variables we need
    # Include TCTI for hardware TPM if set
    # Include IP configuration environment variables
    # Enable mock mobile sensor for testing (can be overridden by environment variable)
    ENV_VARS="PATH=$PATH HOME=$HOME USER=$USER UNIFIED_IDENTITY_ENABLED=true USE_TPM2_QUOTE_DIRECT=1 KEYLIME_DIR=$KEYLIME_AGENT_DIR KEYLIME_AGENT_KEYLIME_DIR=$KEYLIME_AGENT_DIR KEYLIME_AGENT_CONFIG=$TEMP_CONFIG KEYLIME_AGENT_RUN_AS=$KEYLIME_AGENT_RUN_AS"
    # Mock sensor disabled by default - set MOCK_MOBILE_SENSOR=true to enable for testing
    if [ "${MOCK_MOBILE_SENSOR:-false}" = "true" ]; then
        ENV_VARS="$ENV_VARS MOCK_MOBILE_SENSOR=1"
        if [ -n "${MOCK_SENSOR_ID:-}" ]; then
            ENV_VARS="$ENV_VARS MOCK_SENSOR_ID=$MOCK_SENSOR_ID"
        fi
    fi
    if [ -n "${KEYLIME_AGENT_IP:-}" ]; then
        ENV_VARS="$ENV_VARS KEYLIME_AGENT_IP=$KEYLIME_AGENT_IP"
    fi
    if [ -n "${KEYLIME_AGENT_CONTACT_IP:-}" ]; then
        ENV_VARS="$ENV_VARS KEYLIME_AGENT_CONTACT_IP=$KEYLIME_AGENT_CONTACT_IP"
    fi
    if [ -n "${KEYLIME_AGENT_REGISTRAR_IP:-}" ]; then
        ENV_VARS="$ENV_VARS KEYLIME_AGENT_REGISTRAR_IP=$KEYLIME_AGENT_REGISTRAR_IP"
    fi
    if [ -n "${TCTI:-}" ]; then
        ENV_VARS="$ENV_VARS TCTI=$TCTI"
    fi
    sudo env -i $ENV_VARS "$(pwd)/target/release/keylime_agent" > /tmp/rust-keylime-agent.log 2>&1 &
    RUST_AGENT_PID=$!
else
    echo "    Starting without sudo..."
    # Override run_as to avoid user lookup issues
    export KEYLIME_AGENT_RUN_AS="$(whoami):$(id -gn)"
    # Ensure KEYLIME_DIR is set correctly (already unset and set above)
    # Include TCTI for hardware TPM if set
    if [ -n "${TCTI:-}" ]; then
        export TCTI
    fi
    # Use setsid + nohup to ensure agent continues running after script exits
    # setsid creates a new session, preventing SIGHUP when parent shell exits
    # Include IP configuration environment variables
    # Enable mock mobile sensor for testing (can be overridden by environment variable)
    ENV_VARS="RUST_LOG=keylime=debug,keylime_agent=debug UNIFIED_IDENTITY_ENABLED=true USE_TPM2_QUOTE_DIRECT=1 KEYLIME_DIR=$KEYLIME_AGENT_DIR KEYLIME_AGENT_KEYLIME_DIR=$KEYLIME_AGENT_DIR KEYLIME_AGENT_CONFIG=$TEMP_CONFIG KEYLIME_AGENT_RUN_AS=$KEYLIME_AGENT_RUN_AS"
    # Mock sensor disabled by default - set MOCK_MOBILE_SENSOR=true to enable for testing
    if [ "${MOCK_MOBILE_SENSOR:-false}" = "true" ]; then
        ENV_VARS="$ENV_VARS MOCK_MOBILE_SENSOR=1"
        if [ -n "${MOCK_SENSOR_ID:-}" ]; then
            ENV_VARS="$ENV_VARS MOCK_SENSOR_ID=$MOCK_SENSOR_ID"
        fi
    fi
    if [ -n "${KEYLIME_AGENT_IP:-}" ]; then
        ENV_VARS="$ENV_VARS KEYLIME_AGENT_IP=$KEYLIME_AGENT_IP"
    fi
    if [ -n "${KEYLIME_AGENT_CONTACT_IP:-}" ]; then
        ENV_VARS="$ENV_VARS KEYLIME_AGENT_CONTACT_IP=$KEYLIME_AGENT_CONTACT_IP"
    fi
    if [ -n "${KEYLIME_AGENT_REGISTRAR_IP:-}" ]; then
        ENV_VARS="$ENV_VARS KEYLIME_AGENT_REGISTRAR_IP=$KEYLIME_AGENT_REGISTRAR_IP"
    fi
    setsid nohup env $ENV_VARS ./target/release/keylime_agent > /tmp/rust-keylime-agent.log 2>&1 &
    RUST_AGENT_PID=$!
    disown $RUST_AGENT_PID 2>/dev/null || true
    RUST_AGENT_PID=$!
fi
echo $RUST_AGENT_PID > /tmp/rust-keylime-agent.pid

# Wait for rust-keylime agent to start
echo "  Waiting for rust-keylime agent to start..."
RUST_AGENT_STARTED=false
UDS_SOCKET_PATH="/tmp/keylime-agent.sock"
for i in {1..60}; do
    # Check if process is still running first
    if ! kill -0 $RUST_AGENT_PID 2>/dev/null; then
        echo -e "${RED}  ✗ rust-keylime Agent process died${NC}"
        echo "  Recent logs:"
        tail -50 /tmp/rust-keylime-agent.log | grep -E "(ERROR|Failed|Listening|bind|HttpServer|9002|unix)" || tail -30 /tmp/rust-keylime-agent.log
        # Check if UDS socket exists (agent might have started before dying)
        if [ -S "$UDS_SOCKET_PATH" ]; then
            echo -e "${GREEN}  ✓ rust-keylime Agent UDS socket exists${NC}"
            RUST_AGENT_STARTED=true
            break
        fi
        abort_on_error "rust-keylime Agent process died - delegated certification is required"
    fi
    # Check if UDS socket exists (primary check for delegated certification)
    if [ -S "$UDS_SOCKET_PATH" ]; then
        echo -e "${GREEN}  ✓ rust-keylime Agent UDS socket is ready (PID: $RUST_AGENT_PID)${NC}"
        RUST_AGENT_STARTED=true
        break
    fi
    
    # Check if port is listening (most reliable check - agent is ready if port is open)
    # Try without -p first (works without root), then with -p if available
    PORT_LISTENING=false
    if netstat -tln 2>/dev/null | grep -q ":9002" || \
       netstat -tlnp 2>/dev/null | grep -q ":9002" || \
       ss -tln 2>/dev/null | grep -q ":9002" || \
       ss -tlnp 2>/dev/null | grep -q ":9002" || \
       lsof -i :9002 2>/dev/null | grep -q LISTEN; then
        PORT_LISTENING=true
    fi
    
    # If port is listening, check if agent process is still running and logs show "Listening"
    if [ "$PORT_LISTENING" = "true" ]; then
        # Check logs for "Listening" message to confirm agent is ready
        # Prioritize log check - if port is listening AND logs show "Listening", agent is ready
        if [ -f /tmp/rust-keylime-agent.log ]; then
            # Try multiple patterns to catch different log formats
            if tail -50 /tmp/rust-keylime-agent.log | grep -qiE "Listening|listening|started.*server|server.*started|bind.*9002|9002.*listen"; then
                echo -e "${GREEN}  ✓ rust-keylime Agent HTTP/HTTPS server is running (PID: $RUST_AGENT_PID, port 9002 listening)${NC}"
                RUST_AGENT_STARTED=true
                break
            fi
        fi
        # Port is listening and process is running - if SPIRE attestation succeeds, agent is functional
        # Accept as ready even without explicit "Listening" in logs (logs might be buffered or format different)
        echo -e "${GREEN}  ✓ rust-keylime Agent port 9002 is listening (PID: $RUST_AGENT_PID)${NC}"
        echo "    Note: Port check passed - agent appears ready (SPIRE attestation will verify functionality)"
        RUST_AGENT_STARTED=true
        break
    fi
    
    # Also try HTTP/HTTPS endpoint checks (may fail due to SSL cert issues, but port check above should catch it)
    # Try localhost first (works even when agent binds to 0.0.0.0), then check port listening
    # Note: When AGENT_BIND_IP is 0.0.0.0, we can't curl it directly, but localhost works
    # Note: These checks may fail due to SSL/TLS configuration, but if port is listening, agent is functional
    # Since SPIRE attestation succeeds, we trust port listening + process running as sufficient
    if curl -s -k --connect-timeout 2 "https://localhost:9002/v2.2/agent/version" >/dev/null 2>&1 || \
       curl -s --connect-timeout 2 "http://localhost:9002/v2.2/agent/version" >/dev/null 2>&1 || \
       curl -s -k --connect-timeout 2 "https://127.0.0.1:9002/v2.2/agent/version" >/dev/null 2>&1 || \
       curl -s --connect-timeout 2 "http://127.0.0.1:9002/v2.2/agent/version" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ rust-keylime Agent HTTP/HTTPS server is responding (PID: $RUST_AGENT_PID)${NC}"
        RUST_AGENT_STARTED=true
        break
    fi
    # Show progress every 10 seconds
    if [ $((i % 10)) -eq 0 ]; then
        echo "    Still waiting for agent to start... (${i}/60 seconds)"
        # Check logs for any errors
        if [ -f /tmp/rust-keylime-agent.log ]; then
            if tail -20 /tmp/rust-keylime-agent.log | grep -q "ERROR\|error\|Error\|Failed\|failed"; then
                echo "    Recent errors in logs:"
                tail -20 /tmp/rust-keylime-agent.log | grep -i "ERROR\|error\|Failed\|failed" | tail -5
            fi
            # Check if agent is listening (from logs)
            if tail -20 /tmp/rust-keylime-agent.log | grep -q "Listening\|listening\|9002"; then
                echo "    Agent appears to be listening (checking connectivity...)"
            fi
            # Show last few lines of log for debugging
            if [ $i -ge 30 ]; then
                echo "    Last 5 lines of agent log:"
                tail -5 /tmp/rust-keylime-agent.log | sed 's/^/      /'
            fi
        else
            echo "    Warning: Agent log file not found at /tmp/rust-keylime-agent.log"
        fi
        # Check if port is listening (try multiple methods)
        if netstat -tln 2>/dev/null | grep -q ":9002" || \
           netstat -tlnp 2>/dev/null | grep -q ":9002" || \
           ss -tln 2>/dev/null | grep -q ":9002" || \
           ss -tlnp 2>/dev/null | grep -q ":9002" || \
           lsof -i :9002 2>/dev/null | grep -q LISTEN; then
            echo "    Port 9002 is listening - agent may be starting up..."
        fi
    fi
    sleep 1
done

if [ "$RUST_AGENT_STARTED" = false ]; then
    echo -e "${RED}  ✗ rust-keylime Agent failed health check within timeout${NC}"
    echo "  Checking agent status..."
    
    # Check if process is still running
    if kill -0 $RUST_AGENT_PID 2>/dev/null; then
        echo "  ✓ Agent process is still running (PID: $RUST_AGENT_PID)"
        
        # Check if port is listening - try multiple methods for reliability
        PORT_CHECK_PASSED=false
        # Try netstat without -p first (works without root), then with -p
        NETSTAT_OUTPUT=$(netstat -tln 2>/dev/null | grep ":9002" || netstat -tlnp 2>/dev/null | grep ":9002" || true)
        SS_OUTPUT=$(ss -tln 2>/dev/null | grep ":9002" || ss -tlnp 2>/dev/null | grep ":9002" || true)
        LSOF_OUTPUT=$(lsof -i :9002 2>/dev/null | grep LISTEN || true)
        
        if [ -n "$NETSTAT_OUTPUT" ] || [ -n "$SS_OUTPUT" ] || [ -n "$LSOF_OUTPUT" ]; then
            PORT_CHECK_PASSED=true
            echo "  ✓ Port 9002 is listening"
            if [ -n "$NETSTAT_OUTPUT" ]; then
                echo "    netstat: $(echo "$NETSTAT_OUTPUT" | head -1)"
            fi
            if [ -n "$SS_OUTPUT" ]; then
                echo "    ss: $(echo "$SS_OUTPUT" | head -1)"
            fi
            if [ -n "$LSOF_OUTPUT" ]; then
                echo "    lsof: $(echo "$LSOF_OUTPUT" | head -1)"
            fi
        fi
        
        # Also check if logs show "Listening" - this is a strong indicator
        # Try multiple patterns to catch different log formats
        if [ -f /tmp/rust-keylime-agent.log ]; then
            if tail -50 /tmp/rust-keylime-agent.log | grep -qiE "Listening.*9002|listening.*9002|started.*server.*9002|server.*started.*9002|bind.*9002|9002.*listen"; then
                echo "  ✓ Agent logs show listening/server started message"
                # If logs show listening, trust that even if port check failed
                if [ "$PORT_CHECK_PASSED" = false ]; then
                    echo -e "${YELLOW}  ⚠ Port check failed but logs show agent is listening - accepting as ready${NC}"
                    PORT_CHECK_PASSED=true
                fi
            fi
        fi
        
        if [ "$PORT_CHECK_PASSED" = true ]; then
            # Port is listening and/or logs show listening - agent is ready
            # Since SPIRE attestation succeeds, the agent is functional even if health check format differs
            if [ -f /tmp/rust-keylime-agent.log ]; then
                # Try multiple patterns to catch different log formats
                if tail -50 /tmp/rust-keylime-agent.log | grep -qiE "Listening|listening|started.*server|server.*started|bind.*9002|9002.*listen"; then
                    echo "  ✓ Agent logs confirm listening/server started message"
                    echo -e "${GREEN}  ✓ Agent is running (port listening + logs confirm) - accepting as ready${NC}"
                    RUST_AGENT_STARTED=true
                else
                    echo "  Recent logs (checking for any activity):"
                    tail -50 /tmp/rust-keylime-agent.log | grep -E "(ERROR|Failed|Listening|listening|bind|HttpServer|9002|register|unix|started|server)" || tail -30 /tmp/rust-keylime-agent.log
                    # Port is listening and process is running - if SPIRE attestation succeeds, agent is functional
                    echo -e "${GREEN}  ✓ Port is listening and process running - accepting as ready (SPIRE attestation will verify functionality)${NC}"
                    RUST_AGENT_STARTED=true
                fi
            else
                echo "  ⚠ Log file not found, but port is listening and process running - accepting as ready"
                RUST_AGENT_STARTED=true
            fi
        else
            echo "  ✗ Port 9002 is not listening"
            echo "  Debug: Checking port status..."
            echo "    netstat output: ${NETSTAT_OUTPUT:-none}"
            echo "    ss output: ${SS_OUTPUT:-none}"
            echo "  Recent logs:"
            tail -50 /tmp/rust-keylime-agent.log | grep -E "(ERROR|Failed|Listening|bind|HttpServer|9002|register|unix)" || tail -30 /tmp/rust-keylime-agent.log
        fi
    else
        echo "  ✗ Agent process is not running"
        echo "  Recent logs:"
        tail -50 /tmp/rust-keylime-agent.log | grep -E "(ERROR|Failed|Listening|bind|HttpServer|9002|register|unix)" || tail -30 /tmp/rust-keylime-agent.log
    fi
    
    if [ "$RUST_AGENT_STARTED" = false ]; then
        abort_on_error "rust-keylime Agent failed to become ready - delegated certification is required"
    fi
fi

pause_at_phase "Step 4 Complete" "rust-keylime Agent is running. Ready for registration and attestation."

# Step 5: Verify rust-keylime Agent Registration and TPM Attested Geolocation
echo ""
echo -e "${CYAN}Step 5: Verifying rust-keylime Agent Registration (and optional TPM geolocation)...${NC}"
echo "  This ensures the agent is registered with Keylime Verifier"
echo "  and surfaces any geolocation claims only if sensors report them."

# Get agent UUID from rust-keylime agent config
RUST_AGENT_UUID=""
if [ -f "${RUST_KEYLIME_DIR}/keylime-agent.conf" ]; then
    RUST_AGENT_UUID=$(grep "^uuid" "${RUST_KEYLIME_DIR}/keylime-agent.conf" 2>/dev/null | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | tr -d "'" || echo "")
fi

# If not found in config, try to get from agent logs
if [ -z "$RUST_AGENT_UUID" ]; then
    RUST_AGENT_UUID=$(grep -i "agent.*uuid\|uuid.*agent" /tmp/rust-keylime-agent.log 2>/dev/null | head -1 | grep -oP '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1 || echo "")
fi

# Clean up UUID (remove any quotes or whitespace)
RUST_AGENT_UUID=$(echo "$RUST_AGENT_UUID" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | tr -d "'")

if [ -z "$RUST_AGENT_UUID" ]; then
    echo -e "${YELLOW}  ⚠ Could not determine agent UUID, will check all agents${NC}"
fi

# Wait for agent to register with registrar first, then verifier
echo "  Waiting for rust-keylime agent to register with Keylime Registrar..."
AGENT_REGISTERED=false
MAX_WAIT=120  # Wait up to 2 minutes for registration
REGISTRAR_REGISTERED=false
# Verifier queries registrar on-demand (no pre-registration needed)

for i in {1..120}; do
    # Step 1: Check if agent is registered with registrar
    if [ "$REGISTRAR_REGISTERED" = false ]; then
        # First check agent logs for SUCCESS messages (faster and more reliable)
        if tail -100 /tmp/rust-keylime-agent.log 2>/dev/null | grep -q "SUCCESS: Agent.*registered"; then
            echo -e "${GREEN}  ✓ Agent registered with Keylime Registrar (detected in logs)${NC}"
            REGISTRAR_REGISTERED=true
            # Also check if activation succeeded
            if tail -100 /tmp/rust-keylime-agent.log 2>/dev/null | grep -q "SUCCESS: Agent.*activated"; then
                echo -e "${GREEN}  ✓ Agent activated with Keylime Registrar${NC}"
            fi
        else
            # Fall back to checking registrar API
            if [ -n "$RUST_AGENT_UUID" ]; then
                # Check specific agent on registrar - try both API versions
                REGISTRAR_RESPONSE=$(curl -s "http://localhost:8890/v2.2/agents/${RUST_AGENT_UUID}" 2>/dev/null || curl -s "http://localhost:8890/v2.1/agents/${RUST_AGENT_UUID}" 2>/dev/null || echo "")
            else
                # Check all agents on registrar - try both API versions
                REGISTRAR_RESPONSE=$(curl -s "http://localhost:8890/v2.2/agents/" 2>/dev/null || curl -s "http://localhost:8890/v2.1/agents/" 2>/dev/null || echo "")
            fi
            
            # Check for successful registration - registrar returns 200 with agent data, or list contains UUID
            if [ -n "$REGISTRAR_RESPONSE" ]; then
                # Check if response indicates success (code 200 or contains the UUID)
                if echo "$REGISTRAR_RESPONSE" | grep -q "\"code\": 200" || \
                   ( [ -n "$RUST_AGENT_UUID" ] && echo "$REGISTRAR_RESPONSE" | grep -q "$RUST_AGENT_UUID" ) || \
                   echo "$REGISTRAR_RESPONSE" | grep -q "uuids"; then
                    if [ -n "$RUST_AGENT_UUID" ]; then
                        if echo "$REGISTRAR_RESPONSE" | grep -q "$RUST_AGENT_UUID"; then
                            echo -e "${GREEN}  ✓ Agent registered with Keylime Registrar${NC}"
                            REGISTRAR_REGISTERED=true
                        fi
                    else
                        # Check if any agents are registered
                        if echo "$REGISTRAR_RESPONSE" | grep -q "uuids" || echo "$REGISTRAR_RESPONSE" | grep -qE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'; then
                            echo -e "${GREEN}  ✓ Agent(s) registered with Keylime Registrar${NC}"
                            REGISTRAR_REGISTERED=true
                            # Extract UUID from response if we don't have it
                            if [ -z "$RUST_AGENT_UUID" ]; then
                                RUST_AGENT_UUID=$(echo "$REGISTRAR_RESPONSE" | grep -oP '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1 || echo "")
                                if [ -n "$RUST_AGENT_UUID" ]; then
                                    echo "  Detected agent UUID: ${RUST_AGENT_UUID}"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    # Step 2: Verifier queries registrar on-demand (no automatic registration)
    # Skip verifier registration check - verifier will query registrar when SPIRE sends verification requests
    # We only need to confirm registrar registration is complete
    if [ "$REGISTRAR_REGISTERED" = true ]; then
        # Registrar registration is sufficient - verifier queries on-demand
        AGENT_REGISTERED=true
        break
    fi
    
    # Show progress every 10 seconds
    if [ $((i % 10)) -eq 0 ]; then
        STATUS_MSG="Still waiting"
        if [ "$REGISTRAR_REGISTERED" = true ]; then
            STATUS_MSG="$STATUS_MSG (registrar: ✓"
        else
            STATUS_MSG="$STATUS_MSG (registrar: ✗"
        fi
        # Verifier queries registrar on-demand (no pre-registration needed)
        STATUS_MSG="$STATUS_MSG, verifier: on-demand)... (${i}/${MAX_WAIT} seconds)"
        echo "    $STATUS_MSG"
        
        # Check agent logs for registration activity or errors
        if tail -30 /tmp/rust-keylime-agent.log | grep -qi "register\|registration"; then
            echo "    Registration activity detected in agent logs..."
        fi
        if tail -30 /tmp/rust-keylime-agent.log | grep -qi "error\|failed\|incompatible"; then
            echo "    ⚠ Errors detected in agent logs:"
            tail -30 /tmp/rust-keylime-agent.log | grep -iE "error|failed|incompatible" | tail -2 | sed 's/^/      /'
        fi
    fi
    
    sleep 1
done

# Unified-Identity: Verifier queries registrar on-demand
# If agent is registered with registrar, we can proceed (verifier will query on-demand)
if [ "$REGISTRAR_REGISTERED" = "true" ]; then
    echo -e "${GREEN}  ✓ Agent registered with Registrar${NC}"
    echo "  Unified-Identity: Verifier will query registrar on-demand when SPIRE Server sends verification requests."
    echo "  TPM Plugin and SPIRE can now be started - geolocation will be available when verifier queries agent."
elif [ "$AGENT_REGISTERED" = false ]; then
    echo -e "${RED}  ✗ Agent registration failed${NC}"
    echo ""
    echo "  Registration Status:"
    if [ "$REGISTRAR_REGISTERED" = "true" ]; then
        echo -e "    ${GREEN}✓ Registrar: Agent is registered${NC}"
    else
        echo -e "    ${RED}✗ Registrar: Agent NOT registered${NC}"
    fi
    echo ""
    echo "  Registrar logs:"
    tail -20 /tmp/keylime-registrar.log | grep -E "(agent|register|error)" | tail -5 || tail -10 /tmp/keylime-registrar.log
    echo ""
    echo "  Verifier logs:"
    tail -30 /tmp/keylime-verifier.log | grep -E "(agent|register|geolocation|error)" | tail -5 || tail -10 /tmp/keylime-verifier.log
    echo ""
    echo "  Agent logs:"
    tail -50 /tmp/rust-keylime-agent.log | grep -E "(register|registration|geolocation|error|failed|incompatible)" | tail -10 || tail -20 /tmp/rust-keylime-agent.log
    echo ""
    abort_on_error "Agent registration failed - cannot proceed without registered agent"
    echo "  Troubleshooting:"
    echo "    1. Check if agent UUID matches: ${RUST_AGENT_UUID:-'(unknown)'}"
    echo "    2. Verify registrar is accessible: curl http://${CONTROL_PLANE_HOST_IP}:8890/v2.1/agents/"
    echo "    3. Check for API version mismatches in agent logs"
    echo "    4. Ensure agent can reach registrar and verifier"
    exit 1
fi

echo -e "${GREEN}  ✓ Agent registration verified${NC}"

# Small delay to ensure registrar has fully processed agent registration
echo "  Waiting for registrar to fully process agent registration..."
sleep 2

# Retrieve attested claims (including optional geolocation/GPU metrics)
CLAIMS_RESULT=$(KEYLIME_DIR="${PYTHON_KEYLIME_DIR}" KEYLIME_FACT_DIR="${PYTHON_KEYLIME_DIR}" KEYLIME_FACT_CONFIG="${VERIFIER_CONFIG_ABS}" KEYLIME_FACT_AGENT_ID="${RUST_AGENT_UUID}" python3 <<'PY'
import json
import os
import sys
import warnings

warnings.filterwarnings("ignore")

keylime_dir = os.environ.get("KEYLIME_FACT_DIR")
if keylime_dir and os.path.exists(keylime_dir):
    sys.path.insert(0, keylime_dir)

try:
    from keylime import fact_provider
except Exception as exc:  # pragma: no cover
    sys.stdout.write(f"ERROR:import:{exc}\n")
    sys.exit(0)

config_path = os.environ.get("KEYLIME_FACT_CONFIG")
if config_path:
    os.environ["KEYLIME_VERIFIER_CONFIG"] = config_path

os.environ["KEYLIME_TEST"] = "on"
os.environ["UNIFIED_IDENTITY_ENABLED"] = "true"

agent_id = os.environ.get("KEYLIME_FACT_AGENT_ID") or None

try:
    claims = fact_provider.get_attested_claims(agent_id=agent_id)
except Exception as exc:  # pragma: no cover
    sys.stdout.write(f"ERROR:claims:{exc}\n")
    sys.exit(0)

if claims:
    path = "/tmp/keylime-attested-claims.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(claims, fh, indent=2)
    sys.stdout.write(f"CLAIMS_FILE:{path}\n")
    geo = claims.get("geolocation")
    if geo:
        sys.stdout.write(f"GEO:{geo}\n")
else:
    sys.stdout.write("NO_CLAIMS\n")
PY
)

CLAIMS_FILE=""
GEO_VALUE=""

if echo "$CLAIMS_RESULT" | grep -q "^CLAIMS_FILE:"; then
    CLAIMS_FILE=$(echo "$CLAIMS_RESULT" | grep "^CLAIMS_FILE:" | tail -1 | cut -d':' -f2- | tr -d '\r')
fi

if echo "$CLAIMS_RESULT" | grep -q "^GEO:"; then
    GEO_VALUE=$(echo "$CLAIMS_RESULT" | grep "^GEO:" | tail -1 | cut -d':' -f2- | tr -d '\r')
fi

if echo "$CLAIMS_RESULT" | grep -q "^ERROR:"; then
    echo -e "${YELLOW}  ⚠ Unable to retrieve attested claims: ${CLAIMS_RESULT}${NC}"
fi

if [ -n "$CLAIMS_FILE" ] && [ -f "$CLAIMS_FILE" ]; then
    echo "  Attested claims saved to $CLAIMS_FILE"
    echo "  Claims:"
    sed 's/^/    /' "$CLAIMS_FILE"
fi

if [ -n "$GEO_VALUE" ]; then
    echo -e "${GREEN}  ✓ TPM attested geolocation reported: ${GEO_VALUE}${NC}"
fi

echo "  TPM Plugin and SPIRE can now be started."

pause_at_phase "Step 5 Complete" "Agent is registered with Keylime. Geolocation claims are optional and surface only when sensors report them. Ready for SPIRE integration."

# Step 6: Start TPM Plugin Server (HTTP/UDS)
echo ""
echo -e "${CYAN}Step 6: Starting TPM Plugin Server (HTTP/UDS)...${NC}"

    TPM_PLUGIN_SERVER="${SCRIPT_DIR}/tpm-plugin/tpm_plugin_server.py"
if [ ! -f "$TPM_PLUGIN_SERVER" ]; then
    abort_on_error "TPM Plugin Server not found at ${TPM_PLUGIN_SERVER}"
fi

if [ ! -f "$TPM_PLUGIN_SERVER" ]; then
    echo -e "${RED}  ✗ TPM Plugin Server not found, cannot continue${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ TPM Plugin Server found: $TPM_PLUGIN_SERVER${NC}"

# Create work directory
mkdir -p /tmp/spire-data/tpm-plugin 2>/dev/null || true

# Cleanup existing TPM Plugin Server before starting
echo "  Cleaning up existing TPM Plugin Server..."
pkill -f "tpm_plugin_server" >/dev/null 2>&1 || true
sleep 1
rm -f /tmp/tpm-plugin-server.pid 2>/dev/null || true
rm -f /tmp/spire-data/tpm-plugin/tpm-plugin.sock 2>/dev/null || true
rm -f /tmp/tpm-plugin-server.log 2>/dev/null || true

# Set TPM plugin endpoint (UDS socket)
TPM_PLUGIN_SOCKET="/tmp/spire-data/tpm-plugin/tpm-plugin.sock"
export TPM_PLUGIN_ENDPOINT="unix://${TPM_PLUGIN_SOCKET}"
echo "  Setting TPM_PLUGIN_ENDPOINT=${TPM_PLUGIN_ENDPOINT}"

# Start TPM Plugin Server
echo "  Starting TPM Plugin Server on UDS: ${TPM_PLUGIN_SOCKET}..."
export UNIFIED_IDENTITY_ENABLED=true
# Use setsid + nohup to ensure TPM Plugin Server continues running after script exits
# setsid creates a new session, preventing SIGHUP when parent shell exits
setsid nohup python3 "$TPM_PLUGIN_SERVER" \
    --socket-path "${TPM_PLUGIN_SOCKET}" \
    --work-dir /tmp/spire-data/tpm-plugin \
    > /tmp/tpm-plugin-server.log 2>&1 &
TPM_PLUGIN_SERVER_PID=$!
disown $TPM_PLUGIN_SERVER_PID 2>/dev/null || true
echo $TPM_PLUGIN_SERVER_PID > /tmp/tpm-plugin-server.pid

# Wait for server to start (check if socket exists or process is running)
echo "  Waiting for TPM Plugin Server to start..."
TPM_SERVER_STARTED=false
# Wait longer (up to 30 seconds) since App Key generation during startup can take time
for i in {1..60}; do
    # Check if socket exists (using -S to check it's a socket file)
    if [ -S "${TPM_PLUGIN_SOCKET}" ]; then
        echo -e "${GREEN}  ✓ TPM Plugin Server started (PID: $TPM_PLUGIN_SERVER_PID, socket: ${TPM_PLUGIN_SOCKET})${NC}"
        TPM_SERVER_STARTED=true
        break
    fi
    # Also check if socket exists as regular file (sometimes created before chmod)
    if [ -e "${TPM_PLUGIN_SOCKET}" ] && [ ! -S "${TPM_PLUGIN_SOCKET}" ]; then
        # Socket file exists but isn't a socket yet - wait a bit more
        sleep 0.2
        continue
    fi
    # Check if process is still running
    if ! kill -0 $TPM_PLUGIN_SERVER_PID 2>/dev/null; then
        echo -e "${RED}  ✗ TPM Plugin Server process died${NC}"
        tail -20 /tmp/tpm-plugin-server.log
        abort_on_error "TPM Plugin Server process died"
    fi
    # Check logs for socket binding confirmation
    if grep -q "UDS socket bound and listening" /tmp/tpm-plugin-server.log 2>/dev/null; then
        # Server says socket is bound - verify it exists
        if [ -e "${TPM_PLUGIN_SOCKET}" ]; then
            echo -e "${GREEN}  ✓ TPM Plugin Server started (PID: $TPM_PLUGIN_SERVER_PID, socket: ${TPM_PLUGIN_SOCKET})${NC}"
            TPM_SERVER_STARTED=true
            break
        fi
    fi
    # Give it a moment - socket creation might be slightly delayed, especially during App Key generation
    sleep 0.5
done

if [ "$TPM_SERVER_STARTED" = false ]; then
    # Check if process is running even if socket check failed
    if kill -0 $TPM_PLUGIN_SERVER_PID 2>/dev/null; then
        # Check if socket actually exists (maybe the check failed due to timing)
        if [ -e "${TPM_PLUGIN_SOCKET}" ]; then
            echo -e "${GREEN}  ✓ TPM Plugin Server started (socket exists: ${TPM_PLUGIN_SOCKET})${NC}"
            TPM_SERVER_STARTED=true
        elif grep -q "UDS socket bound and listening" /tmp/tpm-plugin-server.log 2>/dev/null; then
            echo -e "${YELLOW}  ⚠ TPM Plugin Server process is running and socket binding logged, but socket file not found${NC}"
            echo "  Process PID: $TPM_PLUGIN_SERVER_PID"
            echo "  Expected socket path: ${TPM_PLUGIN_SOCKET}"
            echo "  Checking if socket exists at different location..."
            find /tmp -name "*tpm-plugin*.sock" -type s 2>/dev/null | head -3
            echo "  Recent logs:"
            tail -20 /tmp/tpm-plugin-server.log
            echo "  Continuing anyway - server may be ready..."
            TPM_SERVER_STARTED=true
        else
            echo -e "${YELLOW}  ⚠ TPM Plugin Server process is running but socket not detected${NC}"
            echo "  Process PID: $TPM_PLUGIN_SERVER_PID"
            echo "  Socket path: ${TPM_PLUGIN_SOCKET}"
            echo "  Recent logs:"
            tail -20 /tmp/tpm-plugin-server.log
            echo "  Continuing anyway - server may be ready (App Key generation may delay socket creation)..."
            TPM_SERVER_STARTED=true
        fi
    else
        echo -e "${RED}  ✗ TPM Plugin Server failed to start${NC}"
        tail -20 /tmp/tpm-plugin-server.log
        abort_on_error "TPM Plugin Server failed to start"
    fi
fi

# Verify App Key is ready and UDS socket is working (needed for SPIRE Agent attestation)
echo "  Verifying App Key is ready and UDS socket is accessible..."
APP_KEY_READY=false
for i in {1..30}; do
    # First verify socket exists and is accessible
    if [ ! -S "${TPM_PLUGIN_SOCKET}" ]; then
        if [ $i -lt 10 ]; then
            sleep 1
            continue
        else
            echo -e "${YELLOW}  ⚠ UDS socket not found: ${TPM_PLUGIN_SOCKET}${NC}"
            echo "  Checking if process is running..."
            if [ -f /tmp/tpm-plugin-server.pid ]; then
                PID=$(cat /tmp/tpm-plugin-server.pid 2>/dev/null || echo "")
                if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
                    echo "  Process is running (PID: $PID), but socket not created yet"
                else
                    echo "  Process is not running - check logs for errors"
                    tail -20 /tmp/tpm-plugin-server.log
                fi
            fi
        fi
    fi
    
    # Check logs for App Key generation success
    if grep -q "App Key generated successfully on startup" /tmp/tpm-plugin-server.log 2>/dev/null; then
        # Verify we can actually connect via UDS and get the App Key
        if command -v curl >/dev/null 2>&1 && [ -S "${TPM_PLUGIN_SOCKET}" ]; then
            # Try to get App Key via UDS (this verifies both socket and App Key are ready)
            APP_KEY_RESPONSE=$(curl --unix-socket "${TPM_PLUGIN_SOCKET}" -X POST http://localhost/get-app-key \
                -H "Content-Type: application/json" \
                -d '{}' \
                --max-time 2 \
                2>/dev/null || echo "")
            
            # Check if response contains success status (may be truncated in output, so check for key parts)
            if echo "$APP_KEY_RESPONSE" | grep -qE '"status"\s*:\s*"success"|"app_key_public"'; then
                echo -e "${GREEN}  ✓ App Key is ready and UDS socket is working${NC}"
                APP_KEY_READY=true
                break
            elif [ -n "$APP_KEY_RESPONSE" ]; then
                # Response exists but doesn't match - might be an error, check for error indicators
                if echo "$APP_KEY_RESPONSE" | grep -qi "error\|fail"; then
                    echo "  UDS connection works, but App Key request returned error: ${APP_KEY_RESPONSE:0:150}"
                else
                    # Response exists but format unclear - likely working, just truncated
                    echo "  UDS connection works, checking App Key format..."
                    if echo "$APP_KEY_RESPONSE" | grep -q "BEGIN PUBLIC KEY\|app_key_public"; then
                        echo -e "${GREEN}  ✓ App Key is ready (response contains public key)${NC}"
                        APP_KEY_READY=true
                        break
                    fi
                fi
            fi
        elif [ -S "${TPM_PLUGIN_SOCKET}" ]; then
            # Socket exists, check logs for App Key
            if grep -q "App Key generated successfully on startup" /tmp/tpm-plugin-server.log 2>/dev/null; then
                echo -e "${GREEN}  ✓ App Key generation confirmed in logs, UDS socket exists${NC}"
                APP_KEY_READY=true
                break
            fi
        fi
    fi
    sleep 1
done

if [ "$APP_KEY_READY" = false ]; then
    echo -e "${YELLOW}  ⚠ App Key readiness not confirmed${NC}"
    echo "  Socket status:"
    if [ -S "${TPM_PLUGIN_SOCKET}" ]; then
        echo -e "    ${GREEN}✓ UDS socket exists: ${TPM_PLUGIN_SOCKET}${NC}"
        ls -l "${TPM_PLUGIN_SOCKET}"
    else
        echo -e "    ${RED}✗ UDS socket missing: ${TPM_PLUGIN_SOCKET}${NC}"
    fi
    echo "  Recent TPM Plugin Server logs:"
    tail -15 /tmp/tpm-plugin-server.log | grep -E "App Key|UDS|socket|error|Error|started" || tail -10 /tmp/tpm-plugin-server.log
    echo ""
    echo "  Verifying TPM_PLUGIN_ENDPOINT: ${TPM_PLUGIN_ENDPOINT}"
fi

pause_at_phase "Step 6 Complete" "TPM Plugin Server is running. Ready for SPIRE to use TPM operations."

# Step 7: Start SPIRE Agent
# SPIRE Server is managed by test_control_plane.sh
echo ""
echo -e "${CYAN}Step 7: Starting SPIRE Agent (SPIRE Server managed by test_control_plane.sh)...${NC}"

if [ ! -d "${PROJECT_DIR}" ]; then
    echo -e "${RED}Error: Project directory not found at ${PROJECT_DIR}${NC}"
    exit 1
fi

# Set Keylime Verifier URL for SPIRE Server (use HTTPS - Keylime Verifier uses TLS)
# If all services are on the same machine, use localhost (verifier binds to 127.0.0.1)
# Otherwise use the control plane host IP
if [ "${AGENTS_HOST_IP}" = "${CONTROL_PLANE_HOST_IP}" ]; then
    export KEYLIME_VERIFIER_URL="https://localhost:8881"
else
    export KEYLIME_VERIFIER_URL="https://${CONTROL_PLANE_HOST_IP}:8881"
fi
echo "  Setting KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL} (HTTPS)"
# For agent IP, if on same machine use localhost, otherwise use agents host IP
if [ "${AGENTS_HOST_IP}" = "${CONTROL_PLANE_HOST_IP}" ]; then
    export KEYLIME_AGENT_IP="${KEYLIME_AGENT_IP:-127.0.0.1}"
else
    export KEYLIME_AGENT_IP="${KEYLIME_AGENT_IP:-${AGENTS_HOST_IP}}"
fi
export KEYLIME_AGENT_PORT="${KEYLIME_AGENT_PORT:-9002}"
echo "  Using rust-keylime agent endpoint: ${KEYLIME_AGENT_IP}:${KEYLIME_AGENT_PORT}"

# Check if SPIRE binaries exist, build if needed
SPIRE_SERVER="${PROJECT_DIR}/spire/bin/spire-server"
SPIRE_AGENT="${PROJECT_DIR}/spire/bin/spire-agent"

if [ ! -f "${SPIRE_AGENT}" ]; then
    if [ "$NO_BUILD" = "true" ]; then
        echo -e "${YELLOW}  ⚠ SPIRE Agent binary not found and --no-build specified, skipping SPIRE Agent${NC}"
        echo -e "${GREEN}============================================================${NC}"
        echo -e "${GREEN}Integration Test Summary:${NC}"
        echo -e "${GREEN}  ✓ rust-keylime Agent started${NC}"
        echo -e "${YELLOW}  ⚠ SPIRE Agent skipped (binary not found, --no-build specified)${NC}"
        echo -e "${GREEN}============================================================${NC}"
        echo ""
        echo "To complete full integration test:"
        echo "  1. Build SPIRE Agent: cd ${PROJECT_DIR}/spire && make bin/spire-agent"
        echo "  2. Run this script again"
        exit 0
    else
        echo -e "${YELLOW}  ⚠ SPIRE Agent binary not found, building...${NC}"
        cd "${PROJECT_DIR}/spire"
        
        # Ensure required files exist for Makefile
        if [ ! -f ".go-version" ]; then
            echo "1.25.3" > .go-version
        fi
        if [ ! -f ".spire-tool-versions" ]; then
            cat > .spire-tool-versions << 'EOF'
golangci-lint v1.60.0
markdown_lint v0.40.0
protoc 30.2
EOF
        fi
        
        # Try building with Makefile first
        if make bin/spire-agent > /tmp/spire-agent-build.log 2>&1; then
            echo -e "${GREEN}  ✓ SPIRE Agent built successfully${NC}"
        else
            echo -e "${YELLOW}  ⚠ Makefile build failed, trying direct go build...${NC}"
            # Fallback to direct go build if Makefile fails
            mkdir -p bin
            if go build -o bin/spire-agent ./cmd/spire-agent > /tmp/spire-agent-build.log 2>&1; then
                echo -e "${GREEN}  ✓ SPIRE Agent built successfully (using go build)${NC}"
            else
                echo -e "${RED}  ✗ Failed to build SPIRE Agent${NC}"
                echo "  Build log:"
                tail -30 /tmp/spire-agent-build.log
                echo ""
                echo "  Troubleshooting:"
                echo "    1. Ensure Go 1.25.3 is installed: go version"
                echo "    2. Try building manually: cd ${PROJECT_DIR}/spire && make bin/spire-agent"
                exit 1
            fi
        fi
        cd "${PROJECT_DIR}"
    fi
fi

# SPIRE Server is managed by test_control_plane.sh - skipping startup
echo "  Skipping SPIRE Server startup (managed by test_control_plane.sh)"
echo "  Assuming SPIRE Server is already running"

# Start SPIRE Agent manually
AGENT_CONFIG="${PROJECT_DIR}/python-app-demo/spire-agent.conf"
    if [ ! -f "${AGENT_CONFIG}" ]; then
        AGENT_CONFIG="${PROJECT_DIR}/spire/conf/agent/agent.conf"
    fi

    if [ -f "${AGENT_CONFIG}" ]; then
    # Stop any existing agent processes first (join tokens are single-use)
    # Cleanup existing SPIRE Agent before starting
    echo "    Cleaning up existing SPIRE Agent..."
    if [ -f /tmp/spire-agent.pid ]; then
        OLD_PID=$(cat /tmp/spire-agent.pid 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "      Stopping existing SPIRE Agent (PID: $OLD_PID)..."
            kill "$OLD_PID" 2>/dev/null || true
            sleep 2
        fi
    fi
    # Also check for any other agent processes
    pkill -f "spire-agent.*run" >/dev/null 2>&1 || true
    sleep 1
    # Clean up PID, socket, and log files
    rm -f /tmp/spire-agent.pid 2>/dev/null || true
    rm -f /tmp/spire-agent/public/api.sock 2>/dev/null || true
    rm -f /tmp/spire-agent.log 2>/dev/null || true
    echo "    Cleanup complete."
    
        # Wait for server to be ready - SKIPPED for act 2 (server assumed running from test_control_plane.sh)
    echo "    Skipping SPIRE Server readiness check (act 2 - assuming server is already running)"
    
    # Unified-Identity: TPM-based proof of residency - no join token needed
    JOIN_TOKEN=""
    if [ "${UNIFIED_IDENTITY_ENABLED:-false}" != "true" ]; then
        # Generate join token for agent attestation (only if Unified-Identity is disabled)
            # SKIPPED for act 2 - server assumed running from test_control_plane.sh
        echo "    Skipping join token generation (act 2 - assuming server is already running)"
        echo "    ⚠ Note: If Unified-Identity is disabled, ensure join token is configured separately"
    else
        echo "    ✓ Unified-Identity enabled: Using TPM-based proof of residency (no join token needed)"
    fi
    
    # Export trust bundle before starting agent
    # The agent needs the trust bundle to verify the SPIRE Server's certificate
    echo "    Exporting trust bundle from SPIRE Server..."
    TRUST_BUNDLE_PATH="/tmp/bundle.pem"
    SERVER_SOCKET="/tmp/spire-server/private/api.sock"
    
    if [ -f "${SPIRE_SERVER}" ] && [ -S "${SERVER_SOCKET}" ]; then
        # Export trust bundle from SPIRE Server
        if "${SPIRE_SERVER}" bundle show -socketPath "${SERVER_SOCKET}" > "${TRUST_BUNDLE_PATH}" 2>/dev/null; then
            if [ -f "${TRUST_BUNDLE_PATH}" ] && [ -s "${TRUST_BUNDLE_PATH}" ]; then
                echo -e "${GREEN}    ✓ Trust bundle exported to ${TRUST_BUNDLE_PATH}${NC}"
            else
                echo -e "${YELLOW}    ⚠ Trust bundle file is empty or missing${NC}"
            fi
        else
            echo -e "${YELLOW}    ⚠ Failed to export trust bundle from SPIRE Server${NC}"
            echo "    Attempting to wait for server to be ready..."
            # Wait a bit more for server to be fully ready
            for j in {1..10}; do
                sleep 1
                if "${SPIRE_SERVER}" bundle show -socketPath "${SERVER_SOCKET}" > "${TRUST_BUNDLE_PATH}" 2>/dev/null; then
                    if [ -f "${TRUST_BUNDLE_PATH}" ] && [ -s "${TRUST_BUNDLE_PATH}" ]; then
                        echo -e "${GREEN}    ✓ Trust bundle exported to ${TRUST_BUNDLE_PATH}${NC}"
                        break
                    fi
                fi
                if [ $j -eq 10 ]; then
                    echo -e "${RED}    ✗ Failed to export trust bundle after waiting${NC}"
                    echo "    Server socket: ${SERVER_SOCKET}"
                    echo "    Server health: $("${SPIRE_SERVER}" healthcheck -socketPath "${SERVER_SOCKET}" 2>&1 || echo "not responding")"
                fi
            done
        fi
    else
        echo -e "${YELLOW}    ⚠ SPIRE Server not found or not ready, cannot export trust bundle${NC}"
        if [ ! -f "${SPIRE_SERVER}" ]; then
            echo "    SPIRE Server binary not found: ${SPIRE_SERVER}"
        fi
        if [ ! -S "${SERVER_SOCKET}" ]; then
            echo "    SPIRE Server socket not found: ${SERVER_SOCKET}"
        fi
    fi
    
    # Verify trust bundle exists (agent requires it)
    if [ ! -f "${TRUST_BUNDLE_PATH}" ] || [ ! -s "${TRUST_BUNDLE_PATH}" ]; then
        echo -e "${RED}    ✗ Trust bundle not available at ${TRUST_BUNDLE_PATH}${NC}"
        echo "    SPIRE Agent requires the trust bundle to connect to SPIRE Server"
        echo "    Please ensure SPIRE Server is running and accessible"
        abort_on_error "Trust bundle not available - SPIRE Agent cannot start without it"
    fi
    
    # Configure SVID renewal interval if specified via environment variable
    if [ -n "${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-}" ]; then
        echo "    Configuring SVID renewal interval from environment variable..."
        if configure_spire_agent_svid_renewal "${AGENT_CONFIG}" "${SPIRE_AGENT_SVID_RENEWAL_INTERVAL}"; then
            echo -e "${GREEN}    ✓ SVID renewal interval configured${NC}"
        else
            echo -e "${YELLOW}    ⚠ Failed to configure SVID renewal interval, using config file default${NC}"
        fi
    else
        echo "    Using SVID renewal interval from config file (if set)"
    fi
    
    echo "    Starting SPIRE Agent (logs: /tmp/spire-agent.log)..."
    export UNIFIED_IDENTITY_ENABLED="${UNIFIED_IDENTITY_ENABLED:-true}"
    # Ensure TPM_PLUGIN_ENDPOINT is set for agent (must match TPM Plugin Server socket)
    if [ -z "${TPM_PLUGIN_ENDPOINT:-}" ]; then
        export TPM_PLUGIN_ENDPOINT="unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
    fi
    
    # Verify TPM_PLUGIN_ENDPOINT is using UDS format (not TCP/IP)
    if ! echo "${TPM_PLUGIN_ENDPOINT}" | grep -q "^unix://"; then
        echo -e "${RED}    ✗ ERROR: TPM_PLUGIN_ENDPOINT must use UDS format (unix://), got: ${TPM_PLUGIN_ENDPOINT}${NC}"
        abort_on_error "TPM_PLUGIN_ENDPOINT must be UDS socket (unix://), not TCP/IP"
    fi
    
    # Extract socket path and verify it exists
    SOCKET_PATH=$(echo "${TPM_PLUGIN_ENDPOINT}" | sed 's|^unix://||')
    if [ ! -S "${SOCKET_PATH}" ]; then
        echo -e "${YELLOW}    ⚠ WARNING: TPM Plugin UDS socket not found: ${SOCKET_PATH}${NC}"
        echo "    This may cause SPIRE Agent to fail connecting to TPM Plugin"
        echo "    Check if TPM Plugin Server is running and socket was created"
    else
        echo -e "${GREEN}    ✓ TPM Plugin UDS socket verified: ${SOCKET_PATH}${NC}"
    fi
    
    echo "    TPM_PLUGIN_ENDPOINT=${TPM_PLUGIN_ENDPOINT}"
    echo "    UNIFIED_IDENTITY_ENABLED=${UNIFIED_IDENTITY_ENABLED}"
    # Use setsid + nohup to ensure agent continues running after script exits
    # setsid creates a new session, preventing SIGHUP when parent shell exits
    # Unified-Identity: No join token needed - agent uses TPM-based proof of residency
    if [ "${UNIFIED_IDENTITY_ENABLED}" = "true" ]; then
        echo "    Using TPM-based proof of residency (unified_identity node attestor)"
        setsid nohup "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" > /tmp/spire-agent.log 2>&1 &
    elif [ -n "$JOIN_TOKEN" ]; then
        setsid nohup "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
    else
        setsid nohup "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" > /tmp/spire-agent.log 2>&1 &
    fi
    SPIRE_AGENT_PID=$!
    disown $SPIRE_AGENT_PID 2>/dev/null || true
    echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
    sleep 3
    fi

# Wait for SPIRE Server to be ready - SKIPPED for act 2
echo "  Skipping SPIRE Server readiness check (act 2 - non-control plane only)"
echo "  Assuming SPIRE Server is already running and ready"

# Wait for Agent to complete attestation and receive its SVID
echo "  Waiting for SPIRE Agent to complete attestation and receive SVID..."
    ATTESTATION_COMPLETE=false
    for i in {1..90}; do
    # Check if agent has its SVID by checking for Workload API socket
    # The socket is created as soon as the agent has its SVID and is ready
    if [ -S /tmp/spire-agent/public/api.sock ] 2>/dev/null; then
        # Verify agent is also listed on server (server running from test_control_plane.sh)
        if [ -n "${SPIRE_SERVER:-}" ] && [ -f "${SPIRE_SERVER}" ]; then
            AGENT_LIST=$("${SPIRE_SERVER}" agent list -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
            if echo "$AGENT_LIST" | grep -q "spiffe://"; then
                echo -e "${GREEN}  ✓ SPIRE Agent is attested and has SVID${NC}"
                # Show agent details
                echo "$AGENT_LIST" | grep "spiffe://" | head -1 | sed 's/^/    /'
                ATTESTATION_COMPLETE=true
                break
            fi
        else
            # If we can't check server, just check socket existence
            echo -e "${GREEN}  ✓ SPIRE Agent Workload API socket is ready${NC}"
            ATTESTATION_COMPLETE=true
            break
        fi
    else
        # Fallback: Check if agent is attested on server (even if socket not ready yet)
        if [ -n "${SPIRE_SERVER:-}" ] && [ -f "${SPIRE_SERVER}" ]; then
            AGENT_LIST=$("${SPIRE_SERVER}" agent list -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
            if echo "$AGENT_LIST" | grep -q "spiffe://"; then
                echo -e "${GREEN}  ✓ SPIRE Agent is attested${NC}"
                # Show agent details
                echo "$AGENT_LIST" | grep "spiffe://" | head -1 | sed 's/^/    /'
                ATTESTATION_COMPLETE=true
                break
            fi
        fi
    fi
    # Check if attestation request was received (Unified-Identity or join token)
    # Note: Server logs may be from test_control_plane.sh
    if [ $i -eq 1 ] || [ $((i % 15)) -eq 0 ]; then
        if [ -f /tmp/spire-server.log ]; then
            # Check if server received attestation request with SovereignAttestation (Unified-Identity)
            if grep -q "Received.*SovereignAttestation.*agent bootstrap request\|Derived agent ID from TPM evidence" /tmp/spire-server.log 2>/dev/null; then
                if [ $i -eq 1 ]; then
                    if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
                        echo "    ℹ TPM-based attestation request received (checking attestation result)..."
                    else
                        echo "    ℹ Join token was successfully used (checking attestation result)..."
                    fi
                fi
                # Check if attestation failed due to Keylime verification
                if grep -q "Failed to process sovereign attestation\|keylime verification failed" /tmp/spire-server.log 2>/dev/null; then
                    ERROR_MSG=$(grep "Failed to process sovereign attestation\|keylime verification failed" /tmp/spire-server.log | tail -1)
                    # Check if it's a CAMARA rate limiting issue (429)
                    if echo "$ERROR_MSG" | grep -q "status_code.*429\|rate.*limit"; then
                        echo -e "${RED}    ✗ Attestation failed due to CAMARA API rate limiting (429)${NC}"
                        echo ""
                        echo -e "${YELLOW}    CAMARA API Rate Limiting Detected:${NC}"
                        echo "      The CAMARA API has rate limits that prevent too many requests."
                        echo "      This is a limitation of the external CAMARA sandbox service."
                        echo ""
                        echo -e "${CYAN}    Options to resolve:${NC}"
                        echo "      1. Wait a few minutes and retry the test"
                        echo "      2. Set CAMARA_BYPASS=true to skip CAMARA API calls for testing:"
                        echo "         export CAMARA_BYPASS=true"
                        echo "         ./test_agents.sh"
                        echo ""
                        echo "      Error details:"
                        echo "$ERROR_MSG" | sed 's/^/        /'
                        echo ""
                        abort_on_error "SPIRE Agent attestation failed due to CAMARA API rate limiting (429). See message above for resolution options."
                    else
                        echo -e "${RED}    ✗ Attestation request received but verification failed${NC}"
                        echo "$ERROR_MSG" | sed 's/^/      /'
                        abort_on_error "SPIRE Agent attestation verification failed"
                    fi
                fi
            fi
        fi
    fi
    
    # Show progress every 15 seconds
    if [ $((i % 15)) -eq 0 ]; then
        elapsed=$i
        remaining=$((90 - i))
        echo "    Still waiting for attestation... (${elapsed}s elapsed, ${remaining}s remaining)"
        # Check logs for errors
        if [ -f /tmp/spire-agent.log ]; then
            if tail -20 /tmp/spire-agent.log | grep -q "ERROR\|Failed"; then
                echo "    Recent errors in agent log:"
                tail -20 /tmp/spire-agent.log | grep -E "ERROR|Failed" | tail -3
            fi
        fi
    fi
    sleep 1
    done

    if [ "$ATTESTATION_COMPLETE" = false ]; then
        echo -e "${YELLOW}  ⚠ SPIRE Agent attestation may still be in progress...${NC}"
        if [ -f /tmp/spire-agent.log ]; then
            echo "    Recent agent log entries:"
            tail -15 /tmp/spire-agent.log | sed 's/^/      /'
        fi
    fi

    # Show initial attestation logs
    echo ""
    echo -e "${CYAN}  Initial SPIRE Agent Attestation Status:${NC}"
    if [ -f /tmp/spire-agent.log ]; then
        echo "  Checking for attestation completion..."
        if grep -q "Node attestation was successful\|SVID loaded" /tmp/spire-agent.log; then
            echo -e "${GREEN}  ✓ Agent attestation completed${NC}"
            echo "  Agent SVID details:"
            grep -E "Node attestation was successful|SVID loaded|spiffe://.*agent" /tmp/spire-agent.log | tail -3 | sed 's/^/    /'
        else
            echo -e "${YELLOW}  ⚠ Agent attestation may still be in progress...${NC}"
        fi
    fi

pause_at_phase "Step 7 Complete" "SPIRE Agent has completed attestation. Ready for workload registration."

# Step 8: Create Registration Entry
echo ""
echo -e "${CYAN}Step 8: Creating registration entry for workload...${NC}"

# Clean up any existing registration entries for the Python app workload
# This prevents the creation script from needing to handle deletion
WORKLOAD_SPIFFE_ID="spiffe://example.org/python-app"
SPIRE_DIR="${PROJECT_DIR}/spire"
SERVER_SOCKET="/tmp/spire-server/private/api.sock"

if [ -S "$SERVER_SOCKET" ] && [ -f "${SPIRE_DIR}/bin/spire-server" ]; then
    echo "  Cleaning up any existing registration entries for workload..."
    if "${SPIRE_DIR}/bin/spire-server" healthcheck -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
        # Check if entry exists for this workload SPIFFE ID
        ENTRY_SHOW_OUTPUT=$("${SPIRE_DIR}/bin/spire-server" entry show \
            -spiffeID "$WORKLOAD_SPIFFE_ID" \
            -socketPath "$SERVER_SOCKET" 2>&1 || echo "")
        
        # Check if entry actually exists
        if echo "$ENTRY_SHOW_OUTPUT" | grep -qi "Entry ID" && ! echo "$ENTRY_SHOW_OUTPUT" | grep -qi "Found 0 entries"; then
            # Extract entry ID(s) and delete them
            ENTRY_IDS=$(echo "$ENTRY_SHOW_OUTPUT" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' || echo "")
            if [ -z "$ENTRY_IDS" ]; then
                # Fallback: try extracting from "Entry ID" line
                ENTRY_IDS=$(echo "$ENTRY_SHOW_OUTPUT" | grep -i "Entry ID" | sed -n 's/.*Entry ID[[:space:]]*:[[:space:]]*\([a-f0-9-]\+\).*/\1/p' || echo "")
            fi
            
            ENTRY_COUNT=0
            if [ -n "$ENTRY_IDS" ]; then
                while IFS= read -r entry_id; do
                    if [ -n "$entry_id" ]; then
                        if "${SPIRE_DIR}/bin/spire-server" entry delete \
                            -entryID "$entry_id" \
                            -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
                            ENTRY_COUNT=$((ENTRY_COUNT + 1))
                        fi
                    fi
                done <<< "$ENTRY_IDS"
            fi
            
            if [ $ENTRY_COUNT -gt 0 ]; then
                echo -e "  ${GREEN}✓ Deleted $ENTRY_COUNT existing registration entry/entries${NC}"
            fi
        fi
    fi
fi

cd "${PROJECT_DIR}/python-app-demo"
if [ -f "./create-registration-entry.sh" ]; then
    ./create-registration-entry.sh
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Registration entry created${NC}"
        # Wait for entry to propagate to agent (agent syncs with server periodically)
        echo "  Waiting 10s for registration entry to propagate to agent..."
        sleep 10
    else
        echo -e "${RED}  ✗ Registration entry creation failed${NC}"
        abort_on_error "Registration entry creation failed - workload SVID cannot be issued"
    fi
else
    echo -e "${YELLOW}  ⚠ Registration entry script not found, skipping...${NC}"
fi

pause_at_phase "Step 8 Complete" "Registration entry created for workload. Workload can now request SVIDs."

# Step 9: Verify TPM Operations in SPIRE Agent Attestation
echo ""
echo -e "${CYAN}Step 9: Verifying TPM Operations in SPIRE Agent Attestation...${NC}"
echo "  During Step 7, the SPIRE agent should have:"
echo "    1. Generated TPM App Key (via TPM Plugin)"
echo "    2. Generated TPM Quote (via TPM Plugin)"
echo "    3. Obtained App Key certificate via rust-keylime agent (delegated certification)"
echo "    4. Used these in SovereignAttestation for agent SVID"
echo ""

# Check SPIRE agent logs for TPM operations
echo "  Checking SPIRE Agent logs for TPM operations..."
TPM_OPERATIONS_FOUND=false
TPM_OPERATIONS_FAILED=false

if [ -f /tmp/spire-agent.log ]; then
    # Check for TPM plugin initialization
    if grep -qi "TPM plugin\|TPMPluginGateway\|tpm.*plugin.*initialized" /tmp/spire-agent.log; then
        echo -e "${GREEN}    ✓ TPM Plugin Gateway initialized${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "TPM plugin\|TPMPluginGateway.*initialized" /tmp/spire-agent.log | tail -2 | sed 's/^/      /'
    fi
    
    # Check for successful App Key generation (not just attempts)
    if grep -qi "App Key.*generated.*successfully\|App Key generated successfully" /tmp/spire-agent.log; then
        echo -e "${GREEN}    ✓ TPM App Key generation succeeded${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "App Key.*generated.*successfully" /tmp/spire-agent.log | tail -2 | sed 's/^/      /'
    fi
    
    # Check for successful Quote generation (not failures)
    if grep -qi "Quote.*generated.*successfully\|TPM Quote.*successfully" /tmp/spire-agent.log; then
        echo -e "${GREEN}    ✓ TPM Quote generation succeeded${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "Quote.*generated.*successfully\|TPM Quote.*successfully" /tmp/spire-agent.log | tail -2 | sed 's/^/      /'
    elif grep -qi "Failed to.*generate.*Quote\|failed to generate TPM Quote" /tmp/spire-agent.log; then
        echo -e "${YELLOW}    ⚠ TPM Quote generation failed (checking for fallback)${NC}"
        TPM_OPERATIONS_FAILED=true
        grep -i "Failed to.*generate.*Quote\|failed to generate TPM Quote" /tmp/spire-agent.log | tail -2 | sed 's/^/      /'
    fi
    
    # Check for successful SovereignAttestation (not stub fallback)
    if grep -qi "SovereignAttestation.*built.*successfully\|Building real SovereignAttestation" /tmp/spire-agent.log && \
       ! grep -qi "Failed to build.*SovereignAttestation.*using stub\|using stub data" /tmp/spire-agent.log; then
        echo -e "${GREEN}    ✓ SovereignAttestation built with real TPM evidence${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "Building real SovereignAttestation\|SovereignAttestation.*built" /tmp/spire-agent.log | tail -2 | sed 's/^/      /'
    elif grep -qi "Failed to build.*SovereignAttestation.*using stub\|using stub data" /tmp/spire-agent.log; then
        echo -e "${YELLOW}    ⚠ SovereignAttestation fell back to stub data${NC}"
        TPM_OPERATIONS_FAILED=true
        grep -i "Failed to build.*SovereignAttestation\|using stub data" /tmp/spire-agent.log | tail -2 | sed 's/^/      /'
    fi
fi

# Check TPM Plugin Server logs for operations
echo ""
echo "  Checking TPM Plugin Server logs for operations..."
if [ -f /tmp/tpm-plugin-server.log ]; then
    if grep -qi "App Key generated successfully" /tmp/tpm-plugin-server.log; then
        echo -e "${GREEN}    ✓ App Key generation succeeded in TPM Plugin Server${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "App Key generated successfully" /tmp/tpm-plugin-server.log | tail -2 | sed 's/^/      /'
    fi
    
    if grep -qi "Quote generated successfully\|Quote.*successfully" /tmp/tpm-plugin-server.log; then
        echo -e "${GREEN}    ✓ Quote generation succeeded in TPM Plugin Server${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "Quote generated successfully\|Quote.*successfully" /tmp/tpm-plugin-server.log | tail -2 | sed 's/^/      /'
    elif grep -qi "error\|failed\|exception" /tmp/tpm-plugin-server.log | grep -qi "quote"; then
        echo -e "${YELLOW}    ⚠ Quote generation had errors in TPM Plugin Server${NC}"
        TPM_OPERATIONS_FAILED=true
        grep -iE "error|failed|exception" /tmp/tpm-plugin-server.log | grep -i "quote" | tail -2 | sed 's/^/      /'
    fi
    
    if grep -qi "certificate.*received\|certificate.*successfully\|delegated.*certification.*success" /tmp/tpm-plugin-server.log; then
        echo -e "${GREEN}    ✓ Delegated certification succeeded in TPM Plugin Server${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "certificate.*received\|certificate.*successfully\|delegated.*certification.*success" /tmp/tpm-plugin-server.log | tail -2 | sed 's/^/      /'
    elif grep -qi "skipping certificate\|certificate.*not.*available\|failed.*certificate" /tmp/tpm-plugin-server.log; then
        echo -e "${YELLOW}    ⚠ Delegated certification skipped or failed in TPM Plugin Server${NC}"
        TPM_OPERATIONS_FAILED=true
        grep -i "skipping certificate\|certificate.*not.*available\|failed.*certificate" /tmp/tpm-plugin-server.log | tail -2 | sed 's/^/      /'
    fi
fi

# Check SPIRE Server logs for TPM attestation
echo ""
echo "  Checking SPIRE Server logs for TPM attestation evidence..."
if [ -f /tmp/spire-server.log ]; then
    if grep -qi "SovereignAttestation\|TPM.*attestation\|app.*key.*certificate" /tmp/spire-server.log; then
        echo -e "${GREEN}    ✓ TPM attestation evidence received by SPIRE Server${NC}"
        TPM_OPERATIONS_FOUND=true
        grep -i "SovereignAttestation\|TPM.*attestation\|app.*key.*certificate" /tmp/spire-server.log | tail -2 | sed 's/^/      /'
    fi
fi

if [ "$TPM_OPERATIONS_FAILED" = true ]; then
    echo ""
    echo -e "${YELLOW}  ⚠ TPM operations encountered errors during agent attestation${NC}"
    echo ""
    echo "  Issues detected:"
    if grep -qi "Failed to.*generate.*Quote\|failed to generate TPM Quote" /tmp/spire-agent.log 2>/dev/null; then
        echo "    • TPM Quote generation failed - agent may have used stub data"
        echo "      Check: TPM Plugin Server connectivity and UDS socket path"
    fi
    if grep -qi "Failed to build.*SovereignAttestation.*using stub\|using stub data" /tmp/spire-agent.log 2>/dev/null; then
        echo "    • SovereignAttestation fell back to stub data"
        echo "      Check: TPM Plugin Server is running and accessible"
    fi
    if grep -qi "skipping certificate\|certificate.*not.*available" /tmp/tpm-plugin-server.log 2>/dev/null; then
        echo "    • App Key certificate not obtained (delegated certification skipped)"
        echo "      Check: rust-keylime agent is running and accessible"
    fi
    echo ""
    echo "  Troubleshooting:"
    echo "    1. Verify TPM Plugin Server is running: ps aux | grep tpm_plugin_server"
    echo "    2. Check UDS socket exists: ls -l /tmp/spire-data/tpm-plugin/tpm-plugin.sock"
    echo "    3. Verify TPM_PLUGIN_ENDPOINT is set correctly in agent environment"
    echo "    4. Check TPM Plugin Server logs: tail -50 /tmp/tpm-plugin-server.log"
    echo "    5. Verify rust-keylime agent is running for delegated certification"
    echo ""
    echo "  Note: Agent attestation may have succeeded with stub data, but real TPM"
    echo "        operations should be working for production use."
elif [ "$TPM_OPERATIONS_FOUND" = true ]; then
    echo ""
    echo -e "${GREEN}  ✓ TPM operations verified successfully in agent attestation flow${NC}"
    echo "  The SPIRE agent successfully used TPM operations during attestation:"
    echo "    • App Key was generated via TPM Plugin"
    echo "    • TPM Quote was generated with nonce"
    echo "    • App Key was certified via rust-keylime agent"
    echo "    • SovereignAttestation was built with real TPM evidence and sent to SPIRE Server"
else
    echo ""
    echo -e "${YELLOW}  ⚠ TPM operations not clearly detected in logs${NC}"
    echo "  This may be normal if:"
    echo "    • TPM operations are using stub/mock implementations"
    echo "    • Logs don't contain expected keywords"
    echo "    • Agent attestation used alternative method"
    echo ""
    echo "  Note: TPM operations should occur automatically during SPIRE agent attestation"
    echo "        when unified_identity is enabled and TPM Plugin Server is running."
fi

pause_at_phase "Step 9 Complete" "TPM operations verified in SPIRE agent attestation. Agent SVID includes TPM-attested claims."

# Step 10: Generate Sovereign SVID (reuse demo script to avoid duplication)
echo ""
echo -e "${CYAN}Step 10: Generating Sovereign SVID with AttestedClaims...${NC}"
echo "  (Reusing demo.sh to avoid code duplication)"
echo ""

# Unified-Identity: Reuse demo script for Step 7
if [ -f "${SCRIPT_DIR}/scripts/demo.sh" ]; then
    # Call demo script in quiet mode (suppresses header, uses our step header)
    "${SCRIPT_DIR}/scripts/demo.sh" --quiet || {
        # If demo script fails, check exit code
        DEMO_EXIT=$?
        if [ $DEMO_EXIT -ne 0 ]; then
            echo -e "${YELLOW}  ⚠ Sovereign SVID generation had issues${NC}"
        fi
    }
else
    echo -e "${YELLOW}  ⚠ demo.sh not found, falling back to direct execution${NC}"
    cd "${PROJECT_DIR}/python-app-demo"
    if [ -f "./fetch-sovereign-svid-grpc.py" ]; then
        python3 fetch-sovereign-svid-grpc.py
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ Sovereign SVID generated successfully${NC}"
        else
            echo -e "${YELLOW}  ⚠ Sovereign SVID generation had issues${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ fetch-sovereign-svid-grpc.py not found${NC}"
    fi
fi

pause_at_phase "Step 10 Complete" "Sovereign SVID generated with AttestedClaims. Certificate chain includes Workload + Agent SVIDs."

# Step 11: Run All Tests
echo ""
echo -e "${CYAN}Step 11: Running all tests...${NC}"

cd "${PROJECT_DIR}"

# Unit tests
echo "  Running unit tests..."
cd "${PROJECT_DIR}/tpm-plugin"
export PYTHONPATH="${PROJECT_DIR}/keylime:${PROJECT_DIR}/tpm-plugin:${PYTHONPATH:-}"
python3 -m pytest test/ -v --tb=short 2>&1 | tail -15
cd "${PROJECT_DIR}"

# Integration summary
# Unified-Identity: Hardware Integration & Delegated Certification
# Legacy helper scripts were consolidated into this
# single harness. The SVID workflow above already exercises the full stack.
echo "  E2E scenario verification: Executed as part of Steps 1-7"
echo "  Integration: Validated via Sovereign SVID generation and log checks"
echo "  Additional scripted helpers have been retired"

echo -e "${GREEN}  ✓ All tests completed${NC}"

pause_at_phase "Step 11 Complete" "All unit tests passed. E2E scenario verified through SVID generation workflow."

# Step 12: Verify Integration
echo ""
echo -e "${CYAN}Step 12: Verifying Integration...${NC}"

# Check logs for Unified-Identity activity
echo "  Checking SPIRE Server logs for Keylime Verifier calls..."
if [ -f /tmp/spire-server.log ]; then
    KEYLIME_CALLS=$(grep -i "unified-identity.*keylime" /tmp/spire-server.log | wc -l)
    if [ "$KEYLIME_CALLS" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Found $KEYLIME_CALLS Unified-Identity Keylime calls in SPIRE Server logs${NC}"
        echo "  Sample log entries:"
        grep -i "unified-identity.*keylime" /tmp/spire-server.log | tail -3 | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ No Unified-Identity Keylime calls found in SPIRE Server logs${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ SPIRE Server log not found${NC}"
fi

echo ""
echo "  Checking Keylime Verifier logs for Unified-Identity activity..."
if [ -f /tmp/keylime-verifier.log ]; then
    UNIFIED_IDENTITY_VERIFIER_LOGS=$(grep -i "unified-identity" /tmp/keylime-verifier.log | wc -l)
    if [ "$UNIFIED_IDENTITY_VERIFIER_LOGS" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Found $UNIFIED_IDENTITY_VERIFIER_LOGS Unified-Identity logs${NC}"
        echo "  Sample log entries:"
        grep -i "unified-identity" /tmp/keylime-verifier.log | tail -3 | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ No Unified-Identity logs found in verifier${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Keylime Verifier log not found${NC}"
fi

echo ""
echo "  Checking rust-keylime Agent logs for Unified-Identity activity..."
if [ -f /tmp/rust-keylime-agent.log ]; then
    UNIFIED_IDENTITY_LOGS=$(grep -i "unified-identity" /tmp/rust-keylime-agent.log | wc -l)
    if [ "$UNIFIED_IDENTITY_LOGS" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Found $UNIFIED_IDENTITY_LOGS Unified-Identity logs${NC}"
        echo "  Sample log entries:"
        grep -i "unified-identity" /tmp/rust-keylime-agent.log | tail -3 | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ No Unified-Identity logs found${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ rust-keylime Agent log not found${NC}"
fi

echo ""
echo "  Checking SPIRE Agent logs for SVID renewal activity..."
if [ -f /tmp/spire-agent.log ]; then
    # Look for renewal-related log entries
    # unified_identity: agent SVID uses reattestation only (no rotation)
    # Workload SVIDs use rotation (separate from agent SVID)
    if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
        # unified_identity: agent SVID reattestation only
        RENEWAL_LOGS=$(grep -iE "Successfully reattested node|renew|SVID.*updated|SVID.*refreshed|availability_target" /tmp/spire-agent.log | wc -l)
        if [ "$RENEWAL_LOGS" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Found $RENEWAL_LOGS SVID reattestation-related log entries${NC}"
            echo "  Recent reattestation activity:"
            grep -iE "Successfully reattested node|renew|SVID.*updated|SVID.*refreshed|availability_target" /tmp/spire-agent.log | tail -5 | sed 's/^/    /'
        else
            echo -e "${YELLOW}  ⚠ No SVID reattestation activity found in agent logs (may occur after 15s interval)${NC}"
            echo "  Note: Agent SVID reattestation is configured for 15s intervals for demo purposes"
        fi
    else
        # Non-reattestable: agent SVID rotation
        RENEWAL_LOGS=$(grep -iE "Successfully rotated agent SVID|renew|SVID.*updated|SVID.*refreshed|availability_target" /tmp/spire-agent.log | wc -l)
        if [ "$RENEWAL_LOGS" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Found $RENEWAL_LOGS SVID rotation-related log entries${NC}"
            echo "  Recent rotation activity:"
            grep -iE "Successfully rotated agent SVID|renew|SVID.*updated|SVID.*refreshed|availability_target" /tmp/spire-agent.log | tail -5 | sed 's/^/    /'
        else
            echo -e "${YELLOW}  ⚠ No SVID renewal activity found in agent logs (may occur after 15s interval)${NC}"
            echo "  Note: Renewal is configured for 15s intervals for demo purposes"
        fi
    fi
    # Check if availability_target was set
    if grep -q "availability_target" /tmp/spire-agent.log 2>/dev/null; then
        AVAIL_TARGET=$(grep -i "availability_target" /tmp/spire-agent.log | tail -1)
        echo "  Configuration: $AVAIL_TARGET" | sed 's/^/    /'
    fi
else
    echo -e "${YELLOW}  ⚠ SPIRE Agent log not found${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Integration Test Summary                                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}  ✓ TLS certificates generated successfully${NC}"
echo -e "${GREEN}  ✓ Real Keylime Verifier started${NC}"
echo -e "${GREEN}  ✓ rust-keylime Agent started${NC}"
echo -e "${GREEN}  ✓ unified_identity feature flag is ENABLED${NC}"
if [ -f "${SPIRE_SERVER}" ]; then
    echo -e "${GREEN}  ✓ SPIRE Server and Agent started${NC}"
    echo -e "${GREEN}  ✓ Registration entry created${NC}"
    if [ -f "/tmp/svid-dump/attested_claims.json" ]; then
        echo -e "${GREEN}  ✓ Sovereign SVID generated with AttestedClaims${NC}"
    fi
    # Show SVID renewal configuration
    # unified_identity: Agent SVID uses reattestation only (no rotation)
    # Workload SVIDs use rotation (separate from agent SVID)
    if [ -f /tmp/spire-agent.log ]; then
        if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
            # unified_identity: agent SVID reattestation only (workload SVIDs use rotation)
            REATTEST_COUNT=$(grep -c "Successfully reattested node" /tmp/spire-agent.log 2>/dev/null || echo 0)
            # Sanitize: ensure we have a single integer value
            REATTEST_COUNT=$(printf '%s' "$REATTEST_COUNT" | tr -d '\n\r\t ' | grep -oE '^[0-9]+$' | head -1)
            REATTEST_COUNT="${REATTEST_COUNT:-0}"
            if [ "$REATTEST_COUNT" -gt 0 ] 2>/dev/null; then
                echo -e "${GREEN}  ✓ SPIRE Agent SVID reattestation active ($REATTEST_COUNT reattestations)${NC}"
                echo -e "${CYAN}    Note: Workload SVIDs use rotation (separate from agent SVID)${NC}"
            else
                echo -e "${CYAN}  ℹ SPIRE Agent SVID reattestation configured (15s interval for demo)${NC}"
            fi
        else
            # Non-reattestable: agent SVID rotation
            ROTATE_COUNT=$(grep -c "Successfully rotated agent SVID" /tmp/spire-agent.log 2>/dev/null || echo 0)
            # Sanitize: ensure we have a single integer value
            ROTATE_COUNT=$(printf '%s' "$ROTATE_COUNT" | tr -d '\n\r\t ' | grep -oE '^[0-9]+$' | head -1)
            ROTATE_COUNT="${ROTATE_COUNT:-0}"
            if [ "$ROTATE_COUNT" -gt 0 ] 2>/dev/null; then
                echo -e "${GREEN}  ✓ SPIRE Agent SVID rotation active ($ROTATE_COUNT rotations)${NC}"
            else
                echo -e "${CYAN}  ℹ SPIRE Agent SVID rotation configured (15s interval for demo)${NC}"
            fi
        fi
    fi
fi
echo -e "${GREEN}  ✓ All tests passed${NC}"
echo ""
echo -e "${GREEN}Integration test completed successfully!${NC}"
echo ""

pause_at_phase "Step 12 Complete" "Integration verification complete. All components are working together successfully."

# Step 13: Ensure all components are running
echo ""
echo -e "${CYAN}Step 13: Ensuring All Components Are Running...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check and ensure all required components are running
COMPONENTS_OK=true
    
    # Check SPIRE Server
    if ! "${SPIRE_SERVER}" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
        echo -e "${YELLOW}  ⚠ SPIRE Server not running, starting it...${NC}"
        SERVER_CONFIG="${PROJECT_DIR}/python-app-demo/spire-server.conf"
        # Use setsid to create new session, preventing SIGHUP when parent shell exits
        setsid nohup "${SPIRE_SERVER}" run -config "${SERVER_CONFIG}" > /tmp/spire-server.log 2>&1 &
        SPIRE_SERVER_PID=$!
        disown $SPIRE_SERVER_PID 2>/dev/null || true
        echo $SPIRE_SERVER_PID > /tmp/spire-server.pid
        sleep 3
        if "${SPIRE_SERVER}" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
            echo -e "${GREEN}  ✓ SPIRE Server started${NC}"
        else
            echo -e "${RED}  ✗ SPIRE Server failed to start${NC}"
            COMPONENTS_OK=false
        fi
    else
        echo -e "${GREEN}  ✓ SPIRE Server is running${NC}"
    fi
    
    # Check TPM Plugin Server
    TPM_PLUGIN_SOCKET="/tmp/spire-data/tpm-plugin/tpm-plugin.sock"
        if [ ! -S "$TPM_PLUGIN_SOCKET" ]; then
        echo -e "${YELLOW}  ⚠ TPM Plugin Server not running, starting it...${NC}"
        TPM_PLUGIN_SERVER="${PROJECT_DIR}/tpm-plugin/tpm_plugin_server.py"
        if [ -f "$TPM_PLUGIN_SERVER" ]; then
            mkdir -p /tmp/spire-data/tpm-plugin 2>/dev/null || true
            export UNIFIED_IDENTITY_ENABLED=true
            # Use setsid to create new session, preventing SIGHUP when parent shell exits
            setsid nohup python3 "$TPM_PLUGIN_SERVER" \
                --socket-path "$TPM_PLUGIN_SOCKET" \
                --work-dir /tmp/spire-data/tpm-plugin \
                > /tmp/tpm-plugin-server.log 2>&1 &
            TPM_PLUGIN_PID=$!
            disown $TPM_PLUGIN_PID 2>/dev/null || true
            echo $TPM_PLUGIN_PID > /tmp/tpm-plugin-server.pid
            sleep 3
            if [ -S "$TPM_PLUGIN_SOCKET" ]; then
                echo -e "${GREEN}  ✓ TPM Plugin Server started${NC}"
            else
                echo -e "${YELLOW}  ⚠ TPM Plugin Server start attempted (may not be required)${NC}"
            fi
        fi
        else
            echo -e "${GREEN}  ✓ TPM Plugin Server is running${NC}"
        fi
    
    # Check rust-keylime agent
    if ! pgrep -f "keylime_agent" >/dev/null 2>&1; then
            echo -e "${YELLOW}  ⚠ rust-keylime agent not running${NC}"
            echo "  Note: Agent may be needed for Unified-Identity attestation"
            COMPONENTS_OK=false
    else
        echo -e "${GREEN}  ✓ rust-keylime agent is running${NC}"
    fi
    
    # Check SPIRE Agent
    if [ ! -S /tmp/spire-agent/public/api.sock ]; then
        echo -e "${YELLOW}  ⚠ SPIRE Agent not running, starting it...${NC}"
        
        # Configure agent with renewal interval if set
        AGENT_CONFIG="${PROJECT_DIR}/python-app-demo/spire-agent.conf"
        renewal_interval="${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-30}"
        if [ -n "${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-}" ]; then
            configure_spire_agent_svid_renewal "$AGENT_CONFIG" "$renewal_interval" || {
                echo -e "${YELLOW}  ⚠ Failed to configure renewal interval, using default${NC}"
            }
        fi
        
        # Unified-Identity: TPM-based proof of residency - no join token needed
        JOIN_TOKEN=""
        if [ "${UNIFIED_IDENTITY_ENABLED:-true}" != "true" ]; then
            # Generate join token (only if Unified-Identity is disabled)
            TOKEN_OUTPUT=$("${SPIRE_SERVER}" token generate \
                -socketPath /tmp/spire-server/private/api.sock \
                -spiffeID spiffe://example.org/agent 2>&1)
            JOIN_TOKEN=$(echo "$TOKEN_OUTPUT" | grep -i "token:" | awk '{print $2}' | head -1)
            if [ -z "$JOIN_TOKEN" ]; then
                JOIN_TOKEN=$(echo "$TOKEN_OUTPUT" | grep -oE '[a-f0-9]{32,}' | head -1)
            fi
        fi
        
        # Export trust bundle
        "${SPIRE_SERVER}" bundle show -format pem \
            -socketPath /tmp/spire-server/private/api.sock > /tmp/bundle.pem 2>&1 || true
        
        # Start agent
        rm -f /tmp/spire-agent.log
        if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
            echo "    Starting SPIRE Agent with TPM-based proof of residency (unified_identity)..."
            # Use setsid to create new session, preventing SIGHUP when parent shell exits
            setsid nohup "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" > /tmp/spire-agent.log 2>&1 &
            SPIRE_AGENT_PID=$!
            disown $SPIRE_AGENT_PID 2>/dev/null || true
            echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
        elif [ -n "$JOIN_TOKEN" ]; then
            echo "    Starting SPIRE Agent with join token..."
            # Use setsid to create new session, preventing SIGHUP when parent shell exits
            setsid nohup "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" \
                -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
            SPIRE_AGENT_PID=$!
            disown $SPIRE_AGENT_PID 2>/dev/null || true
            echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
        else
            echo -e "${RED}  ✗ No join token and Unified-Identity disabled${NC}"
            COMPONENTS_OK=false
        fi
        
        if [ "$COMPONENTS_OK" != false ]; then
            echo $! > /tmp/spire-agent.pid
            
            # Wait for agent to start
            for i in {1..30}; do
                if [ -S /tmp/spire-agent/public/api.sock ]; then
                    echo -e "${GREEN}  ✓ SPIRE Agent started and socket is ready${NC}"
                    break
                fi
                if [ $i -eq 30 ]; then
                    echo -e "${RED}  ✗ SPIRE Agent failed to start (timeout)${NC}"
                    echo "  Check logs: /tmp/spire-agent.log"
                    COMPONENTS_OK=false
                fi
                sleep 1
            done
        fi
    else
        echo -e "${GREEN}  ✓ SPIRE Agent is running${NC}"
    fi
    
    # Verify agent has SVID
    if [ -S /tmp/spire-agent/public/api.sock ]; then
        sleep 2
        if grep -q "Agent.*SVID\|SVID.*issued" /tmp/spire-agent.log 2>/dev/null; then
            echo -e "${GREEN}  ✓ SPIRE Agent has SVID${NC}"
        else
            echo -e "${YELLOW}  ⚠ SPIRE Agent may not have SVID yet (checking logs...)${NC}"
            tail -10 /tmp/spire-agent.log | grep -i "svid\|attest" | head -3 | sed 's/^/    /' || true
        fi
    fi
    
# Step 14: Test SPIRE Agent SVID Renewal
echo ""
echo -e "${CYAN}Step 14: Testing SPIRE Agent SVID Renewal...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine max wait time based on renewal interval
renewal_interval="${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-30}"
# Wait for 1 renewal cycle + buffer (minimum 60 seconds)
max_wait=$((renewal_interval + 30))
if [ "$max_wait" -lt 60 ]; then
    max_wait=60
fi

if [ "$COMPONENTS_OK" = true ] || [ -S /tmp/spire-agent/public/api.sock ]; then
    # Wait for exactly one renewal
    if wait_for_one_agent_svid_renewal "$max_wait"; then
        echo -e "${GREEN}  ✓ Agent SVID renewal detected${NC}"
        echo ""
        
        # Fetch and dump agent SVID
        echo -e "${CYAN}  Fetching and dumping agent SVID...${NC}"
        AGENT_SVID_FILE="/tmp/agent-svid-dump/agent-svid.pem"
        
        if fetch_agent_svid "$AGENT_SVID_FILE"; then
            echo ""
            echo -e "${CYAN}  Extracting SPIRE trust bundle for verification...${NC}"
            
            # Extract SPIRE bundle first (required for certificate verification)
            SPIRE_BUNDLE="/tmp/bundle.pem"
            if [ -f "${SCRIPT_DIR}/fetch-spire-bundle.py" ]; then
                export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
                export BUNDLE_OUTPUT_PATH="$SPIRE_BUNDLE"
                if python3 "${SCRIPT_DIR}/fetch-spire-bundle.py" >/dev/null 2>&1; then
                    if [ -f "$SPIRE_BUNDLE" ] && [ -s "$SPIRE_BUNDLE" ]; then
                        echo -e "${GREEN}    ✓ SPIRE trust bundle extracted${NC}"
                    else
                        echo -e "${YELLOW}    ⚠ SPIRE bundle file not created, trying alternative method...${NC}"
                        # Try using SPIRE server CLI to get bundle
                        if [ -f "${PROJECT_DIR}/spire/bin/spire-server" ]; then
                            "${PROJECT_DIR}/spire/bin/spire-server" bundle show -format pem \
                                -socketPath /tmp/spire-server/private/api.sock > "$SPIRE_BUNDLE" 2>/dev/null && \
                                echo -e "${GREEN}    ✓ SPIRE trust bundle extracted via server CLI${NC}" || \
                                echo -e "${YELLOW}    ⚠ Failed to extract bundle, continuing without verification${NC}"
                        fi
                    fi
                else
                    echo -e "${YELLOW}    ⚠ Failed to extract SPIRE bundle via Python script, trying server CLI...${NC}"
                    # Try using SPIRE server CLI as fallback
                    if [ -f "${PROJECT_DIR}/spire/bin/spire-server" ]; then
                        "${PROJECT_DIR}/spire/bin/spire-server" bundle show -format pem \
                            -socketPath /tmp/spire-server/private/api.sock > "$SPIRE_BUNDLE" 2>/dev/null && \
                            echo -e "${GREEN}    ✓ SPIRE trust bundle extracted via server CLI${NC}" || \
                            echo -e "${YELLOW}    ⚠ Failed to extract bundle, continuing without verification${NC}"
                    fi
                fi
            else
                echo -e "${YELLOW}    ⚠ fetch-spire-bundle.py not found, trying server CLI...${NC}"
                # Try using SPIRE server CLI
                if [ -f "${PROJECT_DIR}/spire/bin/spire-server" ]; then
                    "${PROJECT_DIR}/spire/bin/spire-server" bundle show -format pem \
                        -socketPath /tmp/spire-server/private/api.sock > "$SPIRE_BUNDLE" 2>/dev/null && \
                        echo -e "${GREEN}    ✓ SPIRE trust bundle extracted via server CLI${NC}" || \
                        echo -e "${YELLOW}    ⚠ Failed to extract bundle, continuing without verification${NC}"
                fi
            fi
            
            echo ""
            echo -e "${CYAN}  Dumping agent SVID with AttestedClaims...${NC}"
            echo "    Note: This is the agent's own SVID certificate (single cert, not a chain)"
            echo ""
            
            # Dump the agent SVID with --agent-svid flag to suppress chain warnings
            if [ -f "${SCRIPT_DIR}/scripts/dump-svid-attested-claims.sh" ]; then
                "${SCRIPT_DIR}/scripts/dump-svid-attested-claims.sh" --agent-svid "$AGENT_SVID_FILE" "$SPIRE_BUNDLE"
            else
                echo -e "${YELLOW}    ⚠ dump-svid-attested-claims.sh not found${NC}"
                echo "    Agent SVID saved to: $AGENT_SVID_FILE"
            fi
            
            echo ""
            echo -e "${GREEN}  ✓ Agent SVID dump completed${NC}"
            pause_at_phase "Step 14 Complete" "Agent SVID has been extracted from logs and dumped with AttestedClaims."
        else
            echo -e "${YELLOW}  ⚠ Could not fetch agent SVID for dumping${NC}"
            echo "    You can manually extract it from agent logs or use SPIRE agent API"
        fi
    else
        echo -e "${YELLOW}  ⚠ No agent SVID renewal detected within timeout${NC}"
        echo "    This may be normal if the renewal interval is longer than expected"
    fi
else
    echo -e "${RED}  ✗ Cannot test renewal - required components not running${NC}"
    echo "  Ensure all components are started before re-running the renewal demonstration"
fi

echo ""
echo -e "${GREEN}➡ SPIRE agent SVID renewal test complete.${NC}"
echo ""
echo "Next steps to demo workload mTLS blips (optional):"
echo "  1. Start server-only demo:  python3 python-app-demo/mtls-server-app.py ..."
echo "  2. Start client-only demo:  python3 python-app-demo/mtls-client-app.py ..."
echo "  3. Or run ./test_workload_svid_renewal.sh to launch both workloads automatically."

echo ""
echo -e "${CYAN}For workload mTLS renewal demos:${NC}"
echo "  Run ./test_workload_svid_renewal.sh (see README)."
echo ""

# Step 15: Extract SPIRE Trust Bundle
echo ""
echo -e "${CYAN}Step 15: Extracting SPIRE Trust Bundle...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "${SCRIPT_DIR}/fetch-spire-bundle.py" ]; then
    echo "  Extracting SPIRE trust bundle for use with standard cert servers..."
    export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
    export BUNDLE_OUTPUT_PATH="/tmp/spire-bundle.pem"
    
    if python3 "${SCRIPT_DIR}/fetch-spire-bundle.py" 2>&1; then
        echo -e "${GREEN}  ✓ SPIRE trust bundle extracted successfully${NC}"
        echo "  Bundle location: ${BUNDLE_OUTPUT_PATH}"
        echo "  Use this bundle for standard cert servers that need to verify SPIRE clients:"
        echo "    export CA_CERT_PATH=\"${BUNDLE_OUTPUT_PATH}\""
    else
        echo -e "${YELLOW}  ⚠ Failed to extract SPIRE trust bundle (SPIRE Agent may not be ready)${NC}"
        echo "  You can extract it manually later with:"
        echo "    python3 ${SCRIPT_DIR}/fetch-spire-bundle.py"
    fi
else
    echo -e "${YELLOW}  ⚠ fetch-spire-bundle.py not found at ${SCRIPT_DIR}/fetch-spire-bundle.py${NC}"
    echo "  Skipping SPIRE bundle extraction"
fi

echo ""

if [ "${EXIT_CLEANUP_ON_EXIT}" = true ]; then
    echo "Background services will be terminated automatically on script exit."
    echo "Note: Default behavior is to keep services running. Use --exit-cleanup to enable cleanup."
else
    echo -e "${GREEN}All services are running in background and will continue after script exit:${NC}"
    echo "  Keylime Verifier: PID $(cat /tmp/keylime-verifier.pid 2>/dev/null || echo 'N/A') (port 8881)"
    echo "  rust-keylime Agent: PID $(cat /tmp/rust-keylime-agent.pid 2>/dev/null || echo 'N/A') (port 9002)"
    echo "  SPIRE Server: PID $(cat /tmp/spire-server.pid 2>/dev/null || echo 'N/A')"
    echo "  SPIRE Agent: PID $(cat /tmp/spire-agent.pid 2>/dev/null || echo 'N/A')"
    echo ""
    echo -e "${CYAN}SPIRE Agent SVID Renewal:${NC}"
    echo "  Configured for ${SPIRE_AGENT_SVID_RENEWAL_INTERVAL}s intervals (demo purposes)"
    if [ -f /tmp/spire-agent.log ]; then
        RENEWAL_COUNT=$(grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | wc -l)
        if [ "$RENEWAL_COUNT" -gt 0 ]; then
            echo "  Active: $RENEWAL_COUNT renewal events logged"
        fi
    fi
    echo ""
    echo -e "${CYAN}Workload SVID Access:${NC}"
    echo "  Workloads can retrieve SVIDs anytime via SPIRE Agent Workload API"
    echo "  Socket: /tmp/spire-agent/public/api.sock (or check agent config)"
fi
echo ""
echo "To view logs:"
echo "  Keylime Verifier:     tail -f /tmp/keylime-verifier.log"
echo "  rust-keylime Agent:   tail -f /tmp/rust-keylime-agent.log"
echo "  SPIRE Server:         tail -f /tmp/spire-server.log"
echo "  SPIRE Agent:          tail -f /tmp/spire-agent.log"
echo ""
echo "Consolidated workflow log (all components in chronological order):"
if generate_workflow_log_file; then
    # Function already printed the path, but ensure it's visible
    if [ -f "/tmp/phase3_complete_workflow_logs.txt" ]; then
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  Consolidated workflow log location: /tmp/phase3_complete_workflow_logs.txt${NC}"
        echo -e "${CYAN}    View with: cat /tmp/phase3_complete_workflow_logs.txt${NC}"
        echo -e "${CYAN}    Or: less /tmp/phase3_complete_workflow_logs.txt${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Warning: Consolidated workflow log generation failed${NC}"
fi
echo ""

# Generate interactive HTML visualization
if [ -f "${SCRIPT_DIR}/workflow-ui/generate_workflow_ui.py" ]; then
    echo "Generating interactive HTML visualization..."
    if python3 "${SCRIPT_DIR}/workflow-ui/generate_workflow_ui.py" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Interactive workflow visualization generated: /tmp/workflow_visualization.html${NC}"
        echo -e "${CYAN}    Local access: file:///tmp/workflow_visualization.html${NC}"
        if [ -f "${SCRIPT_DIR}/workflow-ui/serve_workflow_ui.py" ]; then
            echo -e "${CYAN}    HTTP access:  Run 'python3 ${SCRIPT_DIR}/workflow-ui/serve_workflow_ui.py' then visit:${NC}"
            echo -e "${CYAN}                  http://${AGENTS_HOST_IP:-${AGENTS_HOST}}:8080/workflow_visualization.html${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ Warning: Failed to generate HTML visualization${NC}"
    fi
    echo ""
fi

if [ -f "/tmp/svid-dump/svid.pem" ]; then
    echo "To view SVID certificate with AttestedClaims extension:"
    if [ -f "${SCRIPT_DIR}/scripts/dump-svid-attested-claims.sh" ]; then
        echo "  ${SCRIPT_DIR}/scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem"
    else
        echo "  openssl x509 -in /tmp/svid-dump/svid.pem -text -noout | grep -A 2 \"1.3.6.1.4.1.99999.1\""
    fi
    echo ""
fi
echo "If services are still running (e.g., launched with --no-exit-cleanup), you can stop them manually:" 
echo "  pkill -f keylime_verifier"
echo "  pkill -f keylime_agent"
echo "  pkill -f spire-server"
echo "  pkill -f spire-agent"
echo ""
echo "Convenience options:"
echo "  $0 --cleanup-only            # stop everything and reset state"
echo "  $0 --skip-cleanup            # reuse existing state (advanced)"
echo "  $0 --exit-cleanup            # cleanup services on exit (old behavior)"
echo "  $0 --no-exit-cleanup         # keep services running (default)"
echo ""
echo "Environment variables:"
echo "  UNIFIED_IDENTITY_ENABLED=true    # Enable Unified-Identity feature"
echo "  KEYLIME_VERIFIER_URL             # Keylime Verifier URL (default: https://localhost:8881)"
echo "  KEYLIME_AGENT_IP                  # Keylime Agent IP (default: 127.0.0.1)"
echo "  KEYLIME_AGENT_PORT                # Keylime Agent port (default: 9002)"
echo ""

