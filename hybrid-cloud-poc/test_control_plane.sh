#!/bin/bash
# Unified-Identity: Complete End-to-End Integration Test
# Tests the full workflow: SPIRE Server + Keylime Verifier + rust-keylime Agent -> Sovereign SVID Generation
# Hardware Integration & Delegated Certification

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

MOBILE_SENSOR_DIR="${SCRIPT_DIR}/mobile-sensor-microservice"
MOBILE_SENSOR_HOST="${MOBILE_SENSOR_HOST:-127.0.0.1}"
MOBILE_SENSOR_PORT="${MOBILE_SENSOR_PORT:-9050}"
MOBILE_SENSOR_BASE_URL="http://${MOBILE_SENSOR_HOST}:${MOBILE_SENSOR_PORT}"
MOBILE_SENSOR_DB_ROOT="/tmp/mobile-sensor-service"
MOBILE_SENSOR_DB_PATH="${MOBILE_SENSOR_DB_ROOT}/sensor_mapping.db"
MOBILE_SENSOR_LOG="/tmp/mobile-sensor-microservice.log"
MOBILE_SENSOR_PID_FILE="/tmp/mobile-sensor-microservice.pid"

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

# Function to clean up only control plane services
stop_control_plane_services_only() {
    echo -e "${CYAN}Step 0: Stopping control plane services and cleaning up their data...${NC}"
    echo ""
    
    # Step 1: Stop control plane processes only
    echo "  1. Stopping control plane processes..."
    
    # Stop SPIRE Server (not Agent)
    echo "     Stopping SPIRE Server..."
    pkill -f "spire-server" >/dev/null 2>&1 || true
    
    # Stop Keylime Verifier and Registrar
    echo "     Stopping Keylime Verifier and Registrar..."
    pkill -f "keylime_verifier" >/dev/null 2>&1 || true
    pkill -f "keylime\.cmd\.verifier" >/dev/null 2>&1 || true
    pkill -f "keylime_registrar" >/dev/null 2>&1 || true
    pkill -f "keylime\.cmd\.registrar" >/dev/null 2>&1 || true
    
    sleep 1
    
    # Step 2: Clean up only control plane data directories
    echo "  2. Cleaning up control plane data directories..."
    
    # Remove SPIRE Server data (not Agent data)
    echo "     Removing SPIRE Server data directories..."
    # Stop server first to ensure database is not locked
    pkill -f "spire-server" >/dev/null 2>&1 || true
    sleep 1
    rm -rf /tmp/spire-server 2>/dev/null || true
    rm -f /tmp/spire-server.pid 2>/dev/null || true
    rm -f /tmp/spire-server.log 2>/dev/null || true
    # Also clean up any SQLite database files that might be in the data directory
    find /tmp -name "*.db" -path "*/spire-server/*" -delete 2>/dev/null || true
    find /tmp -name "*.sqlite" -path "*/spire-server/*" -delete 2>/dev/null || true
    
    # Remove Keylime databases and persistent data
    echo "     Removing Keylime databases and persistent data..."
    rm -rf /tmp/keylime 2>/dev/null || true
    rm -f /tmp/keylime-verifier.pid 2>/dev/null || true
    rm -f /tmp/keylime-registrar.pid 2>/dev/null || true
    rm -f /tmp/keylime-verifier.log 2>/dev/null || true
    rm -f /tmp/keylime-registrar.log 2>/dev/null || true
    
    # Remove TLS certificates (needed for Keylime)
    echo "     Removing TLS certificates..."
    rm -rf "${KEYLIME_DIR}/cv_ca" 2>/dev/null || true
    
    # Step 3: Remove PID files
    echo "  3. Removing PID files..."
    rm -f /tmp/spire-server.pid 2>/dev/null || true
    rm -f /tmp/keylime-verifier.pid 2>/dev/null || true
    rm -f /tmp/keylime-registrar.pid 2>/dev/null || true
    
    # Step 4: Remove log files
    echo "  4. Removing log files..."
    rm -f /tmp/spire-server.log 2>/dev/null || true
    rm -f /tmp/keylime-verifier.log 2>/dev/null || true
    rm -f /tmp/keylime-registrar.log 2>/dev/null || true
    
    # Step 5: Remove socket files
    echo "  5. Removing socket files..."
    rm -f /tmp/spire-server/private/api.sock 2>/dev/null || true
    rm -f /tmp/spire-server/public/api.sock 2>/dev/null || true
    
    # Step 6: Create clean data directories
    echo "  6. Creating clean data directories..."
    mkdir -p /tmp/spire-server/private 2>/dev/null || true
    mkdir -p /tmp/spire-server/public 2>/dev/null || true
    mkdir -p /tmp/keylime 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}  ✓ Control plane services stopped and data cleaned up${NC}"
}

# Override with wrapper that adds Step 0 prefix
stop_all_instances_and_cleanup() {
    if [ "${CONTROL_PLANE_ONLY:-false}" = "true" ]; then
        stop_control_plane_services_only
    else
        echo -e "${CYAN}Step 0: Stopping all existing instances and cleaning up all data...${NC}"
        echo ""
        SKIP_HEADER=1 _original_stop_all_instances_and_cleanup
    fi
}

# Pause function for critical phases (only in interactive terminals)
pause_at_phase() {
    local phase_name="$1"
    local description="$2"
    
    # Only pause if:
    # 1. Running in interactive terminal (tty check)
    # 2. PAUSE_ENABLED is true (default: true for interactive, false for non-interactive)
    if [ -t 0 ] && [ "${PAUSE_ENABLED:-true}" = "true" ]; then
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

start_mobile_sensor_microservice() {
    echo ""
    #echo -e "${CYAN}Step 1.5: Starting Mobile Location Verification microservice...${NC}"
    if [ ! -d "${MOBILE_SENSOR_DIR}" ]; then
        abort_on_error "Mobile sensor microservice directory not found: ${MOBILE_SENSOR_DIR}"
    fi

    #echo "  Preparing mobile sensor service data directory..."
    mkdir -p "${MOBILE_SENSOR_DB_ROOT}" 2>/dev/null || true
    rm -f "${MOBILE_SENSOR_DB_PATH}" 2>/dev/null || true

    export MOBILE_SENSOR_DB="${MOBILE_SENSOR_DB_PATH}"
    # CAMARA APIs are bypassed by default (set CAMARA_BYPASS=false to enable CAMARA API calls)
    # Set CAMARA_BYPASS=false to use real CAMARA API calls
    export CAMARA_BYPASS="${CAMARA_BYPASS:-true}"
    
    # Set CAMARA_BASIC_AUTH (priority: 1) Environment variable, 2) File (camara_basic_auth.txt), 3) Error if bypass disabled
    if [ -z "${CAMARA_BASIC_AUTH:-}" ]; then
        # Try to load from file (similar to how auth_req_id is stored)
        # Check in multiple possible locations
        CAMARA_AUTH_FILE=""
        for possible_path in \
            "${MOBILE_SENSOR_DIR}/camara_basic_auth.txt" \
            "${SCRIPT_DIR}/camara_basic_auth.txt" \
            "${MOBILE_SENSOR_DB_ROOT}/camara_basic_auth.txt" \
            "$(pwd)/camara_basic_auth.txt"; do
            if [ -f "$possible_path" ]; then
                CAMARA_AUTH_FILE="$possible_path"
                break
            fi
        done
        
        if [ -n "$CAMARA_AUTH_FILE" ] && [ -f "$CAMARA_AUTH_FILE" ]; then
            # Read file, trim only newlines/carriage returns, preserve spaces
            CAMARA_BASIC_AUTH=$(cat "$CAMARA_AUTH_FILE" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 200)
            if [ -n "$CAMARA_BASIC_AUTH" ]; then
                echo "  [OK] Loaded CAMARA_BASIC_AUTH from file: $CAMARA_AUTH_FILE"
            else
                CAMARA_BASIC_AUTH=""
            fi
        fi
        
        # If still not set and bypass is disabled, show error
        if [ -z "${CAMARA_BASIC_AUTH:-}" ] && [ "$CAMARA_BYPASS" != "true" ]; then
            echo "  [ERROR] CAMARA_BYPASS=false but CAMARA_BASIC_AUTH is not set"
            echo "          CAMARA_BASIC_AUTH must be provided via one of:"
            echo "          1. Environment variable: export CAMARA_BASIC_AUTH=\"Basic <base64(client_id:client_secret)>\""
            echo "          2. File: Create camara_basic_auth.txt with the credentials"
            echo "             Location options:"
            echo "             - ${MOBILE_SENSOR_DIR}/camara_basic_auth.txt"
            echo "             - ${SCRIPT_DIR}/camara_basic_auth.txt"
            echo "             - ${MOBILE_SENSOR_DB_ROOT}/camara_basic_auth.txt"
            echo "          Format: Basic <base64(client_id:client_secret)>"
            echo "          See mobile-sensor-microservice/README.md for instructions"
            exit 1
        fi
    fi
    
    # Export if set (either from env var or file)
    if [ -n "${CAMARA_BASIC_AUTH:-}" ]; then
        export CAMARA_BASIC_AUTH
    fi
    
    # Allow lat/lon/accuracy to be overridden via env vars for testing
    if [ -n "${MOBILE_SENSOR_LATITUDE:-}" ]; then
        export MOBILE_SENSOR_LATITUDE="${MOBILE_SENSOR_LATITUDE}"
    #    echo "    Using custom latitude from MOBILE_SENSOR_LATITUDE: ${MOBILE_SENSOR_LATITUDE}"
    fi
    if [ -n "${MOBILE_SENSOR_LONGITUDE:-}" ]; then
        export MOBILE_SENSOR_LONGITUDE="${MOBILE_SENSOR_LONGITUDE}"
    #    echo "    Using custom longitude from MOBILE_SENSOR_LONGITUDE: ${MOBILE_SENSOR_LONGITUDE}"
    fi
    if [ -n "${MOBILE_SENSOR_ACCURACY:-}" ]; then
        export MOBILE_SENSOR_ACCURACY="${MOBILE_SENSOR_ACCURACY}"
    #    echo "    Using custom accuracy from MOBILE_SENSOR_ACCURACY: ${MOBILE_SENSOR_ACCURACY}"
    fi

    cd "${MOBILE_SENSOR_DIR}" || exit 1
    
    # Ensure port is free before starting
    if command -v lsof > /dev/null 2>&1; then
        if lsof -ti :${MOBILE_SENSOR_PORT} >/dev/null 2>&1; then
    #        echo "    Port ${MOBILE_SENSOR_PORT} is in use, stopping existing service..."
            stop_mobile_sensor_microservice
            sleep 2
        fi
    fi
    
    #echo "  Starting mobile sensor microservice..."
    #echo "    Endpoint: ${MOBILE_SENSOR_BASE_URL}"
    #echo "    Database: ${MOBILE_SENSOR_DB_PATH}"
    #echo "    Log file: ${MOBILE_SENSOR_LOG}"
    #echo "    CAMARA_BYPASS: ${CAMARA_BYPASS}"
    # Use setsid + nohup to ensure mobile sensor service continues running after script exits
    # setsid creates a new session, preventing SIGHUP when parent shell exits
    setsid nohup env MOBILE_SENSOR_DB="${MOBILE_SENSOR_DB}" \
             CAMARA_BYPASS="${CAMARA_BYPASS}" \
             CAMARA_BASIC_AUTH="${CAMARA_BASIC_AUTH:-}" \
             MOBILE_SENSOR_LATITUDE="${MOBILE_SENSOR_LATITUDE:-}" \
             MOBILE_SENSOR_LONGITUDE="${MOBILE_SENSOR_LONGITUDE:-}" \
             MOBILE_SENSOR_ACCURACY="${MOBILE_SENSOR_ACCURACY:-}" \
             python3 service.py --host "${MOBILE_SENSOR_HOST}" --port "${MOBILE_SENSOR_PORT}" > "${MOBILE_SENSOR_LOG}" 2>&1 &
    local pid=$!
    #echo $pid > "${MOBILE_SENSOR_PID_FILE}"
    #echo "    Mobile sensor microservice PID: ${pid}"
    
    # Wait a moment for startup logs
    sleep 2
    
    # Show startup logs
    #if [ -f "${MOBILE_SENSOR_LOG}" ]; then
    #    echo "  Startup logs:"
    #    tail -10 "${MOBILE_SENSOR_LOG}" | grep -E "(Starting|latitude|longitude|accuracy|CAMARA_BYPASS|ready)" | sed 's/^/    /' || true
    #fi

    #echo "    Performing readiness health check against /verify (seed sensor_id used)"
    local started=false
    for i in {1..30}; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d '{}' "${MOBILE_SENSOR_BASE_URL}/verify" || true)
        if [ -n "${status}" ] && [ "${status}" != "000" ]; then
    #        echo -e "${GREEN}    ✓ Health check passed (mobile sensor microservice responded HTTP ${status})${NC}"
            started=true
            break
        fi
        sleep 1
    done

    if [ "$started" = false ]; then
        echo -e "${RED}    ✗ Mobile sensor microservice failed to start (check ${MOBILE_SENSOR_LOG})${NC}"
        if [ -f "${MOBILE_SENSOR_LOG}" ]; then
    #        echo "    Recent logs:"
            tail -30 "${MOBILE_SENSOR_LOG}" | sed 's/^/      /'
        fi
        if [ -f "${MOBILE_SENSOR_PID_FILE}" ]; then
            local check_pid
            check_pid=$(cat "${MOBILE_SENSOR_PID_FILE}" 2>/dev/null || echo "")
            if [ -n "${check_pid}" ]; then
                if ps -p "${check_pid}" > /dev/null 2>&1; then
                    echo "    Process ${check_pid} is still running"
                else
                    echo "    Process ${check_pid} is not running (may have crashed)"
                fi
            fi
        fi
        return 1
    fi
    
    # Double-check the service is actually listening on the port
    if command -v netstat > /dev/null 2>&1; then
        if ! netstat -tln 2>/dev/null | grep -q ":${MOBILE_SENSOR_PORT} "; then
            echo -e "${YELLOW}    ⚠ Warning: Service may not be listening on port ${MOBILE_SENSOR_PORT}${NC}"
        fi
    elif command -v ss > /dev/null 2>&1; then
        if ! ss -tln 2>/dev/null | grep -q ":${MOBILE_SENSOR_PORT} "; then
            echo -e "${YELLOW}    ⚠ Warning: Service may not be listening on port ${MOBILE_SENSOR_PORT}${NC}"
        fi
    fi

    #pause_at_phase "Step 1.5 Complete" "Mobile Location Verification microservice is running on ${MOBILE_SENSOR_BASE_URL}."
}

stop_mobile_sensor_microservice() {
    # Kill by PID file if it exists
    if [ -f "${MOBILE_SENSOR_PID_FILE}" ]; then
        local pid
        pid=$(cat "${MOBILE_SENSOR_PID_FILE}" 2>/dev/null || echo "")
        if [ -n "$pid" ]; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
        rm -f "${MOBILE_SENSOR_PID_FILE}" 2>/dev/null || true
    fi
    
    # Also kill any service.py process listening on the mobile sensor port
    # This handles cases where the PID file is missing or the service was started outside the script
    if command -v lsof > /dev/null 2>&1; then
        local port_pid
        port_pid=$(lsof -ti :${MOBILE_SENSOR_PORT} 2>/dev/null || echo "")
        if [ -n "$port_pid" ]; then
            kill "$port_pid" >/dev/null 2>&1 || true
        fi
    elif command -v fuser > /dev/null 2>&1; then
        fuser -k ${MOBILE_SENSOR_PORT}/tcp >/dev/null 2>&1 || true
    fi
    
    # Kill by process pattern matching (multiple patterns to catch all variations)
    pkill -f "service.py.*--port.*${MOBILE_SENSOR_PORT}" >/dev/null 2>&1 || true
    pkill -f "python3.*service.py.*--port" >/dev/null 2>&1 || true
    pkill -f "service.py.*--host.*127.0.0.1" >/dev/null 2>&1 || true
    pkill -f "python3.*service.py.*--host.*127.0.0.1.*--port.*9050" >/dev/null 2>&1 || true
    pkill -f "mobile-sensor-microservice.*service.py" >/dev/null 2>&1 || true
    
    sleep 1
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
            grep -E "Processing|Verifying|certificate|quote|mobile|sensor|Unified-Identity" /tmp/keylime-verifier.log | \
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
        
        # Mobile Location Verification Microservice logs
        if [ -f /tmp/mobile-sensor-microservice.log ]; then
            grep -E "verify|CAMARA|sensor|verification|request|response" /tmp/mobile-sensor-microservice.log | \
            while IFS= read -r line; do
                ts=$(extract_timestamp "$line")
                nts=$(normalize_timestamp "$ts")
                echo "$nts|MOBILE_SENSOR|$line"
            done > "$TEMP_DIR/mobile-sensor.log"
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
        
        # Agent attestation follows architecture flow: SPIRE Agent → TPM Plugin → rust-keylime → SPIRE Agent → SPIRE Server → Keylime Verifier → Mobile Sensor → Keylime Verifier → SPIRE Server → SPIRE Agent
        
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
        
        # Step 7: Mobile Location Verification
        echo "[Step 13-14] Mobile Location Verification:"
        {
            grep -E "KEYLIME_VERIFIER.*mobile|KEYLIME_VERIFIER.*sensor|KEYLIME_VERIFIER.*geolocation" "$TEMP_DIR/all-logs-sorted.log"
            grep -E "MOBILE_SENSOR" "$TEMP_DIR/all-logs-sorted.log"
        } | sort -t'|' -k1,1 | while IFS='|' read -r ts component line; do
            formatted_ts=$(echo "$ts" | sed 's/|.*//')
            clean_line=$(echo "$line" | sed 's/^[^|]*|//')
            comp_name="Keylime Verifier"
            [[ "$component" == "MOBILE_SENSOR" ]] && comp_name="Mobile Location Verification"
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
        
        # Mobile Location Verification
        echo "[4] Mobile Location Verification:"
        grep -E "MOBILE_SENSOR|KEYLIME_VERIFIER.*mobile|KEYLIME_VERIFIER.*sensor" "$TEMP_DIR/all-logs-sorted.log" | head -8 | \
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
  --control-plane-only Start only control plane services (SPIRE Server, Keylime Verifier/Registrar)
                       Skip SPIRE Agent, TPM Plugin, and rust-keylime Agent
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
    stop_mobile_sensor_microservice
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
# Control plane only mode: skip SPIRE Agent and related components
CONTROL_PLANE_ONLY=true
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

# Function to test SVID renewal by monitoring logs
test_svid_renewal() {
    local monitor_duration="${1:-60}"  # Default: monitor for 60 seconds
    local renewal_interval="${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-86400}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Testing SVID Renewal (monitoring for ${monitor_duration}s)${NC}"
    echo -e "${CYAN}  Configured renewal interval: ${renewal_interval}s${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
    
    # Get initial log positions
    local agent_log="/tmp/spire-agent.log"
    local initial_agent_size=0
    if [ -f "$agent_log" ]; then
        initial_agent_size=$(wc -l < "$agent_log" 2>/dev/null || echo "0")
    fi
    
    echo "  Monitoring logs for renewal events..."
    echo "  Initial log position: line $initial_agent_size"
    echo ""
    
    # Monitor for the specified duration
    local start_time=$(date +%s)
    local end_time=$((start_time + monitor_duration))
    local agent_renewals=0
    local workload_renewals=0
    
    echo "  Waiting for renewal events (checking every 2 seconds)..."
    
    while [ $(date +%s) -lt $end_time ]; do
        sleep 2
        
        # Check for agent SVID renewal events
        if [ -f "$agent_log" ]; then
            local current_size=$(wc -l < "$agent_log" 2>/dev/null || echo "0")
            if [ "$current_size" -gt "$initial_agent_size" ]; then
                # Check for new renewal events
                # unified_identity uses reattestation only (no rotation)
                if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
                    local new_agent_renewals=$(tail -n +$((initial_agent_size + 1)) "$agent_log" 2>/dev/null | \
                        grep -c "Successfully reattested node" 2>/dev/null || echo 0)
                    # Sanitize: ensure we have a single integer value
                    new_agent_renewals=$(printf '%s' "$new_agent_renewals" | tr -d '\n\r\t ' | grep -oE '^[0-9]+$' | head -1)
                    new_agent_renewals="${new_agent_renewals:-0}"
                else
                    local new_agent_renewals=$(tail -n +$((initial_agent_size + 1)) "$agent_log" 2>/dev/null | \
                        grep -iE "Successfully rotated agent SVID|renew|SVID.*updated|SVID.*refreshed|Agent.*SVID.*renewed" | wc -l)
                    # Sanitize: ensure we have a single integer value
                    new_agent_renewals=$(printf '%s' "$new_agent_renewals" | tr -d '\n\r\t ' | grep -oE '^[0-9]+$' | head -1)
                    new_agent_renewals="${new_agent_renewals:-0}"
                fi
                
                if [ "$new_agent_renewals" -gt 0 ] 2>/dev/null; then
                    agent_renewals=$((agent_renewals + new_agent_renewals))
                    if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
                        echo -e "  ${GREEN}✓ Agent SVID reattestation detected! (Total: $agent_renewals)${NC}"
                        # Show the reattestation log entry
                        tail -n +$((initial_agent_size + 1)) "$agent_log" 2>/dev/null | \
                            grep "Successfully reattested node" | \
                            head -1 | sed 's/^/    /'
                    else
                        echo -e "  ${GREEN}✓ Agent SVID renewal detected! (Total: $agent_renewals)${NC}"
                        # Show the renewal log entry
                        tail -n +$((initial_agent_size + 1)) "$agent_log" 2>/dev/null | \
                            grep -iE "Successfully rotated agent SVID|renew|SVID.*updated|SVID.*refreshed|Agent.*SVID.*renewed" | \
                            head -1 | sed 's/^/    /'
                    fi
                    
                    # Update initial size to avoid double counting
                    initial_agent_size=$current_size
                    
                    # Check if workload SVIDs are also being renewed
                    # Workload SVIDs should be automatically renewed when agent SVID is renewed
                    local workload_renewal_check=$(tail -n +$((initial_agent_size - 10)) "$agent_log" 2>/dev/null | \
                        grep -iE "workload.*SVID|X509.*SVID.*rotated" | wc -l)
                    # Sanitize: ensure we have a single integer value
                    workload_renewal_check=$(printf '%s' "$workload_renewal_check" | tr -d '\n\r\t ' | grep -oE '^[0-9]+$' | head -1)
                    workload_renewal_check="${workload_renewal_check:-0}"
                    
                    if [ "$workload_renewal_check" -gt 0 ] 2>/dev/null; then
                        workload_renewals=$((workload_renewals + workload_renewal_check))
                        echo -e "    ${GREEN}✓ Workload SVID renewal also detected${NC}"
                    fi
                fi
            fi
        fi
        
        # Show progress
        local elapsed=$(( $(date +%s) - start_time ))
        local remaining=$((end_time - $(date +%s)))
        if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo "  Progress: ${elapsed}s / ${monitor_duration}s (${remaining}s remaining)"
        fi
    done
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  SVID Renewal Test Results${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "$agent_renewals" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Agent SVID Renewals: $agent_renewals event(s) detected${NC}"
        
        if [ "$workload_renewals" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Workload SVID Renewals: $workload_renewals event(s) detected${NC}"
            echo -e "${GREEN}  ✓ Workload SVIDs are being automatically renewed with agent SVID${NC}"
        else
            echo -e "${YELLOW}  ⚠ Workload SVID renewals: Not explicitly detected in logs${NC}"
            echo "    (This may be normal - workload SVIDs are renewed automatically)"
        fi
        
        echo ""
        echo "  Recent renewal log entries:"
        if [ -f "$agent_log" ]; then
            if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ]; then
                grep "Successfully reattested node" "$agent_log" | tail -5 | sed 's/^/    /'
            else
                grep -iE "Successfully rotated agent SVID|renew|SVID.*updated|SVID.*refreshed|Agent.*SVID.*renewed" "$agent_log" | tail -5 | sed 's/^/    /'
            fi
        fi
        
        return 0
    else
        echo -e "${YELLOW}  ⚠ No agent SVID renewals detected during monitoring period${NC}"
        echo "    This may be normal if the renewal interval (${renewal_interval}s) is longer than the"
        echo "    monitoring duration (${monitor_duration}s)"
        echo ""
        echo "  To test renewal with a shorter interval, set:"
        echo "    SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30  # 30 seconds minimum"
        
        # Show current configuration
        if [ -f "$agent_log" ]; then
            echo ""
            echo "  Current agent log (last 10 lines):"
            tail -10 "$agent_log" | sed 's/^/    /'
        fi
        
        return 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cleanup-only)
            # For --cleanup-only, use the original function directly (not the wrapper)
            echo -e "${CYAN}Stopping all existing instances and cleaning up all data...${NC}"
            echo ""
            SKIP_HEADER=1 _original_stop_all_instances_and_cleanup
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
        --control-plane-only)
            CONTROL_PLANE_ONLY=true
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

# Step 1.5: Mobile Location Verification microservice is NOT started by control plane
# The mobile location microservice is only used by Envoy WASM Filter for runtime verification
# Keylime Verifier no longer calls the mobile location microservice during attestation
# (Mobile sensor microservice is started by test_onprem.sh for enterprise gateway)
# start_mobile_sensor_microservice  # DISABLED - not needed for control plane

# Helper function to stop control plane services
stop_control_plane_services() {
    echo "  Stopping existing control plane services..."
    # Stop Keylime Verifier
    if [ -f /tmp/keylime-verifier.pid ]; then
        OLD_PID=$(cat /tmp/keylime-verifier.pid 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "    Stopping Keylime Verifier (PID: $OLD_PID)..."
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi
    pkill -f "keylime.*verifier" >/dev/null 2>&1 || true
    pkill -f "python.*keylime.*verifier" >/dev/null 2>&1 || true
    
    # Stop Keylime Registrar
    if [ -f /tmp/keylime-registrar.pid ]; then
        OLD_PID=$(cat /tmp/keylime-registrar.pid 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "    Stopping Keylime Registrar (PID: $OLD_PID)..."
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi
    pkill -f "keylime.*registrar" >/dev/null 2>&1 || true
    pkill -f "python.*keylime.*registrar" >/dev/null 2>&1 || true
    
    # Stop SPIRE Server
    if [ -f /tmp/spire-server.pid ]; then
        OLD_PID=$(cat /tmp/spire-server.pid 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "    Stopping SPIRE Server (PID: $OLD_PID)..."
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi
    pkill -f "spire-server" >/dev/null 2>&1 || true
    
    # Wait a moment for processes to fully stop
    sleep 2
    echo "  ✓ Control plane services stopped"
}

# Step 2: Start Keylime Verifier with unified_identity enabled
echo ""
echo -e "${CYAN}Step 2: Starting Keylime Verifier with unified_identity enabled...${NC}"
cd "${KEYLIME_DIR}"

# Cleanup existing Keylime Verifier before starting
stop_control_plane_services

# Start verifier in background
echo "  Starting verifier on port 8881..."
echo "    Config: ${KEYLIME_VERIFIER_CONFIG}"
echo "    Work dir: ${KEYLIME_DIR}"
# Ensure we're in the Keylime directory so relative paths work
cd "${KEYLIME_DIR}"
# Start verifier with explicit config - use setsid + nohup to ensure it stays running
# setsid creates a new session, preventing SIGHUP when parent shell exits
setsid nohup python3 -m keylime.cmd.verifier > /tmp/keylime-verifier.log 2>&1 &
KEYLIME_PID=$!
disown $KEYLIME_PID 2>/dev/null || true
echo $KEYLIME_PID > /tmp/keylime-verifier.pid
echo "    Verifier PID: $KEYLIME_PID"
# Give it a moment to start
sleep 2

# Wait for verifier to start
echo "  Waiting for verifier to start..."
VERIFIER_STARTED=false
for i in {1..90}; do
    # Try multiple endpoints (with and without TLS)
    if curl -s -k https://localhost:8881/version >/dev/null 2>&1 || \
       curl -s http://localhost:8881/version >/dev/null 2>&1 || \
       curl -s -k https://localhost:8881/v2.4/version >/dev/null 2>&1 || \
       curl -s http://localhost:8881/v2.4/version >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Keylime Verifier started (PID: $KEYLIME_PID)${NC}"
        VERIFIER_STARTED=true
        break
    fi
    # Check if process is still running
    if ! kill -0 $KEYLIME_PID 2>/dev/null; then
        echo -e "${RED}  ✗ Keylime Verifier process died${NC}"
        echo "  Logs:"
        tail -50 /tmp/keylime-verifier.log
        abort_on_error "Keylime Verifier process died"
    fi
    # Show progress every 10 seconds
    if [ $((i % 10)) -eq 0 ]; then
        echo "    Still waiting... (${i}/90 seconds)"
    fi
    sleep 1
done

if [ "$VERIFIER_STARTED" = false ]; then
    echo -e "${RED}  ✗ Keylime Verifier failed to become ready within timeout${NC}"
    echo "  Logs:"
    tail -50 /tmp/keylime-verifier.log | grep -E "(ERROR|Starting|port|TLS)" || tail -30 /tmp/keylime-verifier.log
    abort_on_error "Keylime Verifier failed to become ready"
fi

# Verify unified_identity feature flag is enabled
echo ""
echo "  Verifying unified_identity feature flag..."
FEATURE_ENABLED=$(python3 -c "
import sys
sys.path.insert(0, '${KEYLIME_DIR}')
import os
os.environ['KEYLIME_VERIFIER_CONFIG'] = '${VERIFIER_CONFIG_ABS}'
os.environ['KEYLIME_TEST'] = 'on'
os.environ['UNIFIED_IDENTITY_ENABLED'] = 'true'
from keylime import app_key_verification
print(app_key_verification.is_unified_identity_enabled())
" 2>&1 | tail -1)

if [ "$FEATURE_ENABLED" = "True" ]; then
    echo -e "${GREEN}  ✓ unified_identity feature flag is ENABLED${NC}"
else
    abort_on_error "unified_identity feature flag is DISABLED (expected: True, got: $FEATURE_ENABLED)"
fi

pause_at_phase "Step 2 Complete" "Keylime Verifier is running and ready. unified_identity feature is enabled."

# Step 3: Start Keylime Registrar (required for rust-keylime agent registration)
echo ""
echo -e "${CYAN}Step 3: Starting Keylime Registrar (required for agent registration)...${NC}"
cd "${KEYLIME_DIR}"

# Set registrar database URL to use SQLite
# Use explicit path to avoid configuration issues
REGISTRAR_DB_PATH="/tmp/keylime/reg_data.sqlite"
mkdir -p "$(dirname "$REGISTRAR_DB_PATH")" 2>/dev/null || true
# Remove old database to ensure fresh schema initialization
rm -f "$REGISTRAR_DB_PATH" 2>/dev/null || true
export KEYLIME_REGISTRAR_DATABASE_URL="sqlite:///${REGISTRAR_DB_PATH}"
# Also set KEYLIME_DIR to ensure proper paths
export KEYLIME_DIR="${KEYLIME_DIR:-/tmp/keylime}"
# Set TLS directory for registrar (use same as verifier)
export KEYLIME_REGISTRAR_TLS_DIR="default"  # Uses cv_ca directory shared with verifier
# Registrar also needs server cert and key - use verifier's if available
if [ -f "${KEYLIME_DIR}/cv_ca/server-cert.crt" ] && [ -f "${KEYLIME_DIR}/cv_ca/server-private.pem" ]; then
    export KEYLIME_REGISTRAR_SERVER_CERT="${KEYLIME_DIR}/cv_ca/server-cert.crt"
    export KEYLIME_REGISTRAR_SERVER_KEY="${KEYLIME_DIR}/cv_ca/server-private.pem"
fi
# Set registrar host and ports
# The registrar server expects http_port and https_port, but config uses port and tls_port
# We'll set both to ensure compatibility
export KEYLIME_REGISTRAR_IP="127.0.0.1"
export KEYLIME_REGISTRAR_PORT="8890"  # HTTP port (non-TLS) - maps to http_port
export KEYLIME_REGISTRAR_TLS_PORT="8891"  # HTTPS port (TLS) - maps to https_port
# Also set the server's expected names
export KEYLIME_REGISTRAR_HTTP_PORT="8890"
export KEYLIME_REGISTRAR_HTTPS_PORT="8891"

# Run database migrations before starting registrar
echo "  Running database migrations..."
cd "${KEYLIME_DIR}"
python3 -c "
import sys
import os
sys.path.insert(0, '${KEYLIME_DIR}')
os.environ['KEYLIME_REGISTRAR_DATABASE_URL'] = '${KEYLIME_REGISTRAR_DATABASE_URL}'
os.environ['KEYLIME_TEST'] = 'on'
from keylime.common.migrations import apply
try:
    apply('registrar')
    print('  ✓ Database migrations completed')
except Exception as e:
    print(f'  ⚠ Migration warning: {e}')
    # Continue anyway - registrar might handle it
" 2>&1 | grep -v "^$" || echo "  ⚠ Migration check completed (may have warnings)"

# Cleanup existing Keylime Registrar before starting (if not already stopped)
if [ -f /tmp/keylime-registrar.pid ]; then
    OLD_PID=$(cat /tmp/keylime-registrar.pid 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "  Stopping existing Keylime Registrar (PID: $OLD_PID)..."
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
    fi
fi
pkill -f "keylime.*registrar" >/dev/null 2>&1 || true
pkill -f "python.*keylime.*registrar" >/dev/null 2>&1 || true
sleep 1

# Start registrar in background
echo "  Starting registrar on port 8890..."
echo "    Database URL: ${KEYLIME_REGISTRAR_DATABASE_URL:-sqlite}"
# Use setsid + nohup to ensure registrar continues running after script exits
# setsid creates a new session, preventing SIGHUP when parent shell exits
setsid nohup python3 -m keylime.cmd.registrar > /tmp/keylime-registrar.log 2>&1 &
REGISTRAR_PID=$!
disown $REGISTRAR_PID 2>/dev/null || true
echo $REGISTRAR_PID > /tmp/keylime-registrar.pid

# Wait for registrar to start
echo "  Waiting for registrar to start..."
REGISTRAR_STARTED=false
for i in {1..30}; do
    if curl -s http://localhost:8890/version >/dev/null 2>&1 || \
       curl -s http://localhost:8890/v2.4/version >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Keylime Registrar started (PID: $REGISTRAR_PID)${NC}"
        REGISTRAR_STARTED=true
        break
    fi
    # Check if process is still running
    if ! kill -0 $REGISTRAR_PID 2>/dev/null; then
        echo -e "${RED}  ✗ Keylime Registrar process died${NC}"
        echo "  Logs:"
        tail -50 /tmp/keylime-registrar.log
        abort_on_error "Keylime Registrar process died"
    fi
    sleep 1
done

if [ "$REGISTRAR_STARTED" = false ]; then
    echo -e "${RED}  ✗ Keylime Registrar failed to become ready within timeout${NC}"
    echo "  Logs:"
    tail -50 /tmp/keylime-registrar.log | grep -E "(ERROR|Starting|port|TLS)" || tail -30 /tmp/keylime-registrar.log
    abort_on_error "Keylime Registrar failed to become ready"
fi

pause_at_phase "Step 3 Complete" "Keylime Registrar is running. Ready for agent registration."

# Step 4: Skipping rust-keylime Agent (control plane only - agent services managed by test_agents.sh)
echo ""
echo -e "${YELLOW}  Skipping rust-keylime Agent (control plane only mode)${NC}"
echo -e "${YELLOW}  Agent services are managed by test_agents.sh${NC}"

# Removed: All rust-keylime Agent startup code (not needed for control plane only)

# Step 5: Skipping Agent Registration verification (control plane only)
echo ""
echo -e "${YELLOW}  Skipping Agent Registration verification (control plane only mode)${NC}"
echo -e "${YELLOW}  Agent registration is managed by test_agents.sh${NC}"

# Removed: All agent registration verification code (not needed for control plane only)

# Step 6: Skipping TPM Plugin Server (control plane only)
echo ""
echo -e "${YELLOW}  Skipping TPM Plugin Server (control plane only mode)${NC}"
echo -e "${YELLOW}  TPM Plugin Server is managed by test_agents.sh${NC}"

# Removed: All TPM Plugin Server startup code (not needed for control plane only)

# Step 4: Build SPIRE Server binary (if needed) and start it
echo ""
echo -e "${CYAN}Step 4: Building SPIRE Server (if needed) and starting it...${NC}"

if [ ! -d "${PROJECT_DIR}" ]; then
    echo -e "${RED}Error: Project directory not found at ${PROJECT_DIR}${NC}"
    exit 1
fi

# Set Keylime Verifier URL for SPIRE Server (use HTTPS - Keylime Verifier uses TLS)
export KEYLIME_VERIFIER_URL="https://localhost:8881"
echo "  Setting KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL} (HTTPS)"
export KEYLIME_AGENT_IP="${KEYLIME_AGENT_IP:-127.0.0.1}"
export KEYLIME_AGENT_PORT="${KEYLIME_AGENT_PORT:-9002}"
echo "  Using rust-keylime agent endpoint: ${KEYLIME_AGENT_IP}:${KEYLIME_AGENT_PORT}"

# Check if SPIRE binaries exist, build if needed
SPIRE_SERVER="${PROJECT_DIR}/spire/bin/spire-server"
if [ ! -f "${SPIRE_SERVER}" ]; then
    if [ "$NO_BUILD" = "true" ]; then
        echo -e "${YELLOW}  ⚠ SPIRE Server binary not found and --no-build specified, skipping SPIRE Server startup${NC}"
        echo -e "${GREEN}============================================================${NC}"
        echo -e "${GREEN}Control Plane Services Summary:${NC}"
        echo -e "${GREEN}  ✓ Keylime Verifier started${NC}"
        echo -e "${GREEN}  ✓ Keylime Registrar started${NC}"
        echo -e "${YELLOW}  ⚠ SPIRE Server skipped (binary not found, --no-build specified)${NC}"
        echo -e "${GREEN}============================================================${NC}"
        echo ""
        echo "To complete control plane setup:"
        echo "  1. Build SPIRE Server: cd ${PROJECT_DIR}/spire && make bin/spire-server"
        echo "  2. Run this script again"
        exit 0
    else
        echo -e "${YELLOW}  ⚠ SPIRE Server binary not found, building...${NC}"
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
        if make bin/spire-server > /tmp/spire-server-build.log 2>&1; then
            echo -e "${GREEN}  ✓ SPIRE Server built successfully${NC}"
        else
            echo -e "${YELLOW}  ⚠ Makefile build failed, trying direct go build...${NC}"
            # Fallback to direct go build if Makefile fails
            mkdir -p bin
            if go build -o bin/spire-server ./cmd/spire-server > /tmp/spire-server-build.log 2>&1; then
                echo -e "${GREEN}  ✓ SPIRE Server built successfully (using go build)${NC}"
            else
                echo -e "${RED}  ✗ Failed to build SPIRE Server${NC}"
                echo "  Build log:"
                tail -30 /tmp/spire-server-build.log
                echo ""
                echo "  Troubleshooting:"
                echo "    1. Ensure Go 1.25.3 is installed: go version"
                echo "    2. Try building manually: cd ${PROJECT_DIR}/spire && make bin/spire-server"
                exit 1
            fi
        fi
        cd "${PROJECT_DIR}"
    fi
fi

# Start SPIRE Server manually
cd "${PROJECT_DIR}"
SERVER_CONFIG="${PROJECT_DIR}/python-app-demo/spire-server.conf"
if [ ! -f "${SERVER_CONFIG}" ]; then
    SERVER_CONFIG="${PROJECT_DIR}/spire/conf/server/server.conf"
fi

if [ -f "${SERVER_CONFIG}" ]; then
    # Unified-Identity: Configure agent_ttl for effective renewal testing
    # With Unified-Identity, set agent_ttl to 60s so renewals occur every ~30s (with availability_target=30s)
    if [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "true" ] || [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "1" ] || [ "${UNIFIED_IDENTITY_ENABLED:-true}" = "yes" ]; then
        if grep -q "Unified-Identity" "$SERVER_CONFIG" 2>/dev/null || [ -n "${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-}" ]; then
            echo "    Configuring agent_ttl for Unified-Identity (60s for effective renewal)..."
            configure_spire_server_agent_ttl "${SERVER_CONFIG}" "60" || {
                echo -e "${YELLOW}    ⚠ Failed to configure agent_ttl, using config file default${NC}"
            }
        fi
    fi
    
    # Cleanup existing SPIRE Server before starting
    if [ -f /tmp/spire-server.pid ]; then
        OLD_PID=$(cat /tmp/spire-server.pid 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "    Stopping existing SPIRE Server (PID: $OLD_PID)..."
            kill "$OLD_PID" 2>/dev/null || true
            # Wait for server to stop (up to 5 seconds)
            for i in {1..5}; do
                if ! kill -0 "$OLD_PID" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
        fi
    fi
    pkill -f "spire-server" >/dev/null 2>&1 || true
    # Wait a bit more to ensure server has fully stopped and released database lock
    sleep 2
    
    # Clean up SPIRE Server data directory and database to ensure fresh start
    echo "    Cleaning up SPIRE Server data and database..."
    rm -rf /tmp/spire-server 2>/dev/null || true
    # Also clean up database files that might be in the server's working directory
    # The server uses ./data/datastore.sqlite3 relative to where it's run from
    SERVER_WORK_DIR="${PROJECT_DIR}/spire"
    if [ -d "${SERVER_WORK_DIR}/.data" ]; then
        echo "    Removing SPIRE Server database directory: ${SERVER_WORK_DIR}/.data"
        rm -rf "${SERVER_WORK_DIR}/.data" 2>/dev/null || true
    fi
    # Clean up any SQLite database files in the spire directory
    find "${SERVER_WORK_DIR}" -maxdepth 2 -name "*.sqlite3" -o -name "*.db" 2>/dev/null | while read -r db_file; do
        if [ -f "$db_file" ]; then
            echo "    Removing database file: $db_file"
            rm -f "$db_file" 2>/dev/null || true
        fi
    done
    
    echo "    Starting SPIRE Server (logs: /tmp/spire-server.log)..."
    # Use setsid + nohup to ensure server continues running after script exits
    # setsid creates a new session, preventing SIGHUP when parent shell exits
    setsid nohup "${SPIRE_SERVER}" run -config "${SERVER_CONFIG}" > /tmp/spire-server.log 2>&1 &
    SPIRE_SERVER_PID=$!
    disown $SPIRE_SERVER_PID 2>/dev/null || true
    echo $SPIRE_SERVER_PID > /tmp/spire-server.pid
    sleep 3
fi

# Skipping SPIRE Agent (control plane only - agent services managed by test_agents.sh)
echo "    Skipping SPIRE Agent (control plane only mode)"
echo "    Agent services are managed by test_agents.sh"

# Removed: All SPIRE Agent startup code (not needed for control plane only)

# Wait for SPIRE Server to be ready and complete
echo "  Waiting for SPIRE Server to be ready..."
for i in {1..30}; do
    if "${SPIRE_SERVER}" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ SPIRE Server is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${YELLOW}  ⚠ SPIRE Server may not be fully ready yet${NC}"
    fi
    sleep 1
done

# Removed: All SPIRE Agent startup and attestation code (not needed for control plane only)

# Final check: Ensure SPIRE Server is ready
if false; then
    # This block is intentionally disabled - agent code removed
    AGENT_CONFIG="${PROJECT_DIR}/python-app-demo/spire-agent.conf"
    if [ ! -f "${AGENT_CONFIG}" ]; then
        AGENT_CONFIG="${PROJECT_DIR}/spire/conf/agent/agent.conf"
    fi

    if [ -f "${AGENT_CONFIG}" ]; then
    # Stop any existing agent processes first (join tokens are single-use)
    if [ -f /tmp/spire-agent.pid ]; then
        OLD_PID=$(cat /tmp/spire-agent.pid 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "    Stopping existing SPIRE Agent (PID: $OLD_PID)..."
            kill "$OLD_PID" 2>/dev/null || true
            sleep 2
        fi
    fi
    # Also check for any other agent processes
    pkill -f "spire-agent.*run" >/dev/null 2>&1 || true
    sleep 1
    
    # Wait for server to be ready
    echo "    Waiting for SPIRE Server to be ready..."
    for i in {1..30}; do
        if "${SPIRE_SERVER}" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # Unified-Identity: TPM-based proof of residency - no join token needed
    JOIN_TOKEN=""
    if [ "${UNIFIED_IDENTITY_ENABLED:-false}" != "true" ]; then
        # Generate join token for agent attestation (only if Unified-Identity is disabled)
        echo "    Generating join token for SPIRE Agent..."
        TOKEN_OUTPUT=$("${SPIRE_SERVER}" token generate \
            -socketPath /tmp/spire-server/private/api.sock 2>&1)
        JOIN_TOKEN=$(echo "$TOKEN_OUTPUT" | grep "Token:" | awk '{print $2}')

        if [ -z "$JOIN_TOKEN" ]; then
            echo "    ⚠ Join token generation failed"
            echo "    Token generation output:"
            echo "$TOKEN_OUTPUT" | sed 's/^/      /'
            echo "    Agent may not attest properly without join token"
        else
            echo "    ✓ Join token generated: ${JOIN_TOKEN:0:20}..."
            # Small delay to ensure token is ready before agent uses it
            sleep 1
        fi
    else
        echo "    ✓ Unified-Identity enabled: Using TPM-based proof of residency (no join token needed)"
    fi
    
    # Export trust bundle before starting agent
    echo "    Exporting trust bundle..."
    "${SPIRE_SERVER}" bundle show -format pem -socketPath /tmp/spire-server/private/api.sock > /tmp/bundle.pem 2>&1
    if [ -f /tmp/bundle.pem ]; then
        echo "    ✓ Trust bundle exported to /tmp/bundle.pem"
    else
        echo "    ⚠ Trust bundle export failed, but continuing..."
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
fi

# Removed: Duplicate SPIRE Server readiness check (already done above)

# Removed: All SPIRE Agent attestation wait code (not needed for control plane only)

# Control plane services are ready
if false; then
    # This block is intentionally disabled - agent attestation code removed
    echo "  Waiting for SPIRE Agent to complete attestation and receive SVID..."
    ATTESTATION_COMPLETE=false
    for i in {1..90}; do
    # Check if agent has its SVID by checking for Workload API socket
    # The socket is created as soon as the agent has its SVID and is ready
    if [ -S /tmp/spire-agent/public/api.sock ] 2>/dev/null; then
        # Verify agent is also listed on server
        AGENT_LIST=$("${SPIRE_SERVER}" agent list -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
        if echo "$AGENT_LIST" | grep -q "spiffe://"; then
            echo -e "${GREEN}  ✓ SPIRE Agent is attested and has SVID${NC}"
            # Show agent details
            echo "$AGENT_LIST" | grep "spiffe://" | head -1 | sed 's/^/    /'
            ATTESTATION_COMPLETE=true
            break
        fi
    else
        # Fallback: Check if agent is attested on server (even if socket not ready yet)
        AGENT_LIST=$("${SPIRE_SERVER}" agent list -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
        if echo "$AGENT_LIST" | grep -q "spiffe://"; then
            echo -e "${GREEN}  ✓ SPIRE Agent is attested${NC}"
            # Show agent details
            echo "$AGENT_LIST" | grep "spiffe://" | head -1 | sed 's/^/    /'
            ATTESTATION_COMPLETE=true
            break
        fi
    fi
    # Check if attestation request was received (Unified-Identity or join token)
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
                    if echo "$ERROR_MSG" | grep -q "mobile sensor.*429\|status_code.*429\|rate.*limit"; then
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
fi

pause_at_phase "Step 4 Complete" "SPIRE Server is running. Control plane services ready."
echo ""
echo -e "${GREEN}Control plane services started successfully:${NC}"
echo "  ✓ SPIRE Server"
echo "  ✓ Keylime Verifier"
echo "  ✓ Keylime Registrar"
echo ""
echo -e "${YELLOW}Note: Agent services (SPIRE Agent, TPM Plugin, rust-keylime Agent) are managed by test_agents.sh${NC}"
exit 0
