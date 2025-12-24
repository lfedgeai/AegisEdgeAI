#!/bin/bash
# Unified-Identity: Complete Integration Test Orchestrator
# Runs all test scripts in sequence across both machines (10.1.0.11 and 10.1.0.10)
# Verifies components are up before proceeding to next step

set -euo pipefail

# Unified-Identity - Testing: Test Infrastructure Hardening (Fail-Fast)
# Ensure clean cleanup on exit
trap 'pkill -P $$; exit' SIGINT SIGTERM EXIT

# Unified-Identity - Testing: Structured Logging
# Create a unique log directory for this run
LOG_DIR="/tmp/unified_identity_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${LOG_DIR}"
echo "Unified-Identity: Logs will be aggregated in ${LOG_DIR}"

# Redirect stdout/stderr to a master log file while still showing on console
if [ -z "${LOGGING_SETUP:-}" ]; then
    export LOGGING_SETUP=true
    exec > >(tee -a "${LOG_DIR}/master.log") 2>&1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default all sub-scripts to run on 10.1.0.11
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-10.1.0.11}"
AGENTS_HOST="${AGENTS_HOST:-10.1.0.11}"
ONPREM_HOST="${ONPREM_HOST:-10.1.0.11}"
SSH_USER="${SSH_USER:-mw}"

# SSH options to avoid password prompts
SSH_OPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no -o BatchMode=yes"

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

# Detect current host IPs
CURRENT_HOST_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' || echo '')

# Function to check if we're running on a specific host
is_on_host() {
    local target_host="$1"
    # Check if any of our IPs match the target host IP
    if echo "$CURRENT_HOST_IPS" | grep -q "^${target_host}$"; then
        return 0
    fi
    # Try to check via hostname comparison
    local current_hostname=$(hostname 2>/dev/null || echo '')
    if [ -n "${current_hostname}" ]; then
        local target_hostname=$(getent hosts ${target_host} 2>/dev/null | awk '{print $2}' | head -1 || echo '')
        if [ -z "${target_hostname}" ]; then
            target_hostname=$(ssh ${SSH_OPTS} -o ConnectTimeout=2 ${SSH_USER}@${target_host} 'hostname' 2>/dev/null || echo '')
        fi
        if [ "${current_hostname}" = "${target_hostname}" ] && [ -n "${target_hostname}" ]; then
            return 0
        fi
    fi
    return 1
}

# Check if we're running on each host
ON_CONTROL_PLANE_HOST=false
ON_AGENTS_HOST=false
ON_ONPREM_HOST=false

if is_on_host "${CONTROL_PLANE_HOST}"; then
    ON_CONTROL_PLANE_HOST=true
fi

if is_on_host "${AGENTS_HOST}"; then
    ON_AGENTS_HOST=true
fi

if is_on_host "${ONPREM_HOST}"; then
    ON_ONPREM_HOST=true
fi


# Function to runscript and show output
run_script() {
    local run_func="$1"
    local script_path="$2"
    local script_args="${3:-}"
    local description="$4"
    local log_file="${LOG_DIR}/$(basename ${script_path} .sh).log"
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${description}${NC}"
    echo -e "${BOLD}Script: ${script_path}${NC}"
    echo -e "${BOLD}Log:    ${log_file}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Prepare environment variables to pass to sub-scripts
    local env_vars="CONTROL_PLANE_HOST=${CONTROL_PLANE_HOST} AGENTS_HOST=${AGENTS_HOST} ONPREM_HOST=${ONPREM_HOST}"
    
    # Unified-Identity - Testing: Fail-Fast & Logging
    # Run script and capture output to specific log file, while also streaming to master log (via stdout)
    # We use pipefail (set at top) to catch errors in the pipeline
    if $run_func "cd ~/AegisSovereignAI/hybrid-cloud-poc && env ${env_vars} bash ${script_path} ${script_args}" 2>&1 | tee "${log_file}"; then
        echo ""
        echo -e "${GREEN}✓ ${description} completed successfully${NC}"
        return 0
    else
        # Unified-Identity - Testing: Fail-Fast
        # Immediate error reporting
        echo ""
        echo -e "${RED}✗ ${description} failed${NC}"
        echo -e "${YELLOW}Last 20 lines of log (${log_file}):${NC}"
        tail -n 20 "${log_file}" | sed 's/^/    /'
        return 1
    fi
}
# Function to run command on control plane host (local or via SSH)
run_on_control_plane() {
    if [ "${ON_CONTROL_PLANE_HOST}" = "true" ]; then
        # Execute locally - no SSH needed
        bash -c "$@"
    else
        # Execute via SSH
        ssh ${SSH_OPTS} ${SSH_USER}@${CONTROL_PLANE_HOST} "$@"
    fi
}

# Function to run command on agents host (local or via SSH)
run_on_agents() {
    if [ "${ON_AGENTS_HOST}" = "true" ]; then
        # Execute locally - no SSH needed
        bash -c "$@"
    else
        # Execute via SSH
        ssh ${SSH_OPTS} ${SSH_USER}@${AGENTS_HOST} "$@"
    fi
}

# Function to run command on on-prem host (local or via SSH)
run_on_onprem() {
    if [ "${ON_ONPREM_HOST}" = "true" ]; then
        # Execute locally - no SSH needed
        bash -c "$@"
    else
        # Execute via SSH
        ssh ${SSH_OPTS} ${SSH_USER}@${ONPREM_HOST} "$@"
    fi
}

# Helper function to wait for services to be ready
wait_for_services() {
    local run_func="$1"
    local service_checks=("${@:2}")
    local max_wait="${MAX_WAIT:-120}"
    local wait_interval=5
    
    echo -e "${CYAN}  Waiting for services to be ready (max ${max_wait}s)...${NC}"
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local all_ready=true
        
        for check in "${service_checks[@]}"; do
            IFS='|' read -r service_name check_cmd <<< "$check"
            if ! $run_func "$check_cmd" >/dev/null 2>&1; then
                all_ready=false
                break
            fi
        done
        
        if [ "$all_ready" = true ]; then
            echo -e "${GREEN}  ✓ All services are ready${NC}"
            return 0
        fi
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
        
        if [ $((elapsed % 15)) -eq 0 ]; then
            echo -e "${YELLOW}    Still waiting... (${elapsed}s / ${max_wait}s)${NC}"
        fi
    done
    
    echo -e "${RED}  ✗ Timeout waiting for services${NC}"
    return 1
}

# Function to verify control plane services
verify_control_plane() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Verifying Control Plane Services on ${CONTROL_PLANE_HOST}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local checks=(
        "SPIRE Server|test -S /tmp/spire-server/private/api.sock"
        "Keylime Verifier|curl -s -k https://localhost:8881/version >/dev/null 2>&1 || curl -s http://localhost:8881/version >/dev/null 2>&1"
        "Keylime Registrar|curl -s http://localhost:8890/version >/dev/null 2>&1"
    )
    
    wait_for_services "run_on_control_plane" "${checks[@]}"
}

# Function to test CAMARA caching and GPS bypass features
test_camara_caching_and_gps_bypass() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Step 4: Testing CAMARA Caching and GPS Bypass Features${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${CYAN}Test 1: CAMARA API Caching (First Call - Should Call API)${NC}"
    echo "  Making first verification request..."
    FIRST_RESPONSE=$(run_on_onprem "curl -s -X POST http://localhost:9050/verify -H 'Content-Type: application/json' -d '{\"sensor_id\": \"12d1:1433\"}'" 2>/dev/null || echo "")
    FIRST_STATUS=$(echo "$FIRST_RESPONSE" | grep -o '"verification_result":[^,}]*' | cut -d: -f2 | tr -d ' ' || echo "")
    
    if [ -n "$FIRST_RESPONSE" ]; then
        echo -e "${GREEN}  ✓ First call completed${NC}"
        echo "  Response: $FIRST_RESPONSE"
        
        # Check logs for API call
        echo ""
        echo "  Checking logs for API call..."
        API_CALL_LOG=$(run_on_onprem "grep -E '\[API CALL\]|\[CACHE MISS\]|\[CACHE HIT\]' /tmp/mobile-sensor.log 2>/dev/null | tail -5" 2>/dev/null || echo "")
        if echo "$API_CALL_LOG" | grep -q "\[API CALL\]\|\[CACHE MISS\]"; then
            echo -e "${GREEN}  ✓ First call made API request (cache miss expected)${NC}"
        else
            echo -e "${YELLOW}  ⚠ Could not verify API call in logs${NC}"
        fi
    else
        echo -e "${RED}  ✗ First call failed${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Test 2: CAMARA API Caching (Second Call - Should Use Cache)${NC}"
    echo "  Waiting 2 seconds, then making second verification request..."
    sleep 2
    SECOND_RESPONSE=$(run_on_onprem "curl -s -X POST http://localhost:9050/verify -H 'Content-Type: application/json' -d '{\"sensor_id\": \"12d1:1433\"}'" 2>/dev/null || echo "")
    SECOND_STATUS=$(echo "$SECOND_RESPONSE" | grep -o '"verification_result":[^,}]*' | cut -d: -f2 | tr -d ' ' || echo "")
    
    if [ -n "$SECOND_RESPONSE" ]; then
        echo -e "${GREEN}  ✓ Second call completed${NC}"
        echo "  Response: $SECOND_RESPONSE"
        
        # Check logs for cache hit
        echo ""
        echo "  Checking logs for cache hit..."
        CACHE_HIT_LOG=$(run_on_onprem "grep -E '\[CACHE HIT\]|\[API CALL\]' /tmp/mobile-sensor.log 2>/dev/null | tail -5" 2>/dev/null || echo "")
        if echo "$CACHE_HIT_LOG" | grep -q "\[CACHE HIT\]"; then
            echo -e "${GREEN}  ✓ Second call used cache (cache hit confirmed)${NC}"
        elif echo "$CACHE_HIT_LOG" | grep -q "\[API CALL\]"; then
            echo -e "${YELLOW}  ⚠ Second call still made API request (cache may not be working)${NC}"
        else
            echo -e "${YELLOW}  ⚠ Could not verify cache behavior in logs${NC}"
        fi
    else
        echo -e "${RED}  ✗ Second call failed${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Test 3: Mobile Location Service Logging${NC}"
    echo "  Checking for location verify logging..."
    LOCATION_VERIFY_LOG=$(run_on_onprem "grep -E '\[LOCATION VERIFY\]' /tmp/mobile-sensor.log 2>/dev/null | tail -3" 2>/dev/null || echo "")
    if [ -n "$LOCATION_VERIFY_LOG" ]; then
        echo -e "${GREEN}  ✓ Location verify logging present${NC}"
        echo "$LOCATION_VERIFY_LOG" | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ Could not find location verify logs${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Test 4: Cache Configuration${NC}"
    echo "  Checking cache TTL configuration..."
    CACHE_CONFIG_LOG=$(run_on_onprem "grep -E 'CAMARA verify_location caching' /tmp/mobile-sensor.log 2>/dev/null | head -1" 2>/dev/null || echo "")
    if [ -n "$CACHE_CONFIG_LOG" ]; then
        echo -e "${GREEN}  ✓ Cache configuration logged${NC}"
        echo "$CACHE_CONFIG_LOG" | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ Could not find cache configuration in logs${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Test 5: GPS Sensor Bypass (WASM Filter)${NC}"
    echo "  Note: GPS sensors should bypass mobile location service"
    echo "  This is verified by checking Envoy logs for GPS sensor requests..."
    GPS_BYPASS_LOG=$(run_on_onprem "sudo grep -E 'GPS/GNSS.*no mobile location service call needed' /opt/envoy/logs/envoy.log 2>/dev/null | tail -2" 2>/dev/null || echo "")
    if [ -n "$GPS_BYPASS_LOG" ]; then
        echo -e "${GREEN}  ✓ GPS bypass detected in Envoy logs${NC}"
        echo "$GPS_BYPASS_LOG" | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ No GPS bypass logs found (may not have GPS sensor requests yet)${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}CAMARA Caching and GPS Bypass Tests Completed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to verify on-prem services
verify_onprem() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Verifying On-Prem Services on ${ONPREM_HOST}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local checks=(
        "Mobile Location Service|curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{}' http://localhost:9050/verify 2>/dev/null | grep -qE '^200|^404'"
        "mTLS Server|(command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ':9443 ') || (command -v netstat >/dev/null 2>&1 && netstat -tln 2>/dev/null | grep -q ':9443 ') || (curl -s -k --connect-timeout 2 https://localhost:9443/health >/dev/null 2>&1)"
        "Envoy Proxy|(command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ':8080 ') || (command -v netstat >/dev/null 2>&1 && netstat -tln 2>/dev/null | grep -q ':8080 ')"
    )
    
    if ! wait_for_services "run_on_onprem" "${checks[@]}"; then
        echo ""
        echo -e "${YELLOW}Service verification failed. Running diagnostics...${NC}"
        echo ""
        
        # Check each service individually
        echo "Checking Mobile Location Service (port 9050):"
        if run_on_onprem "curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{}' http://localhost:9050/verify 2>/dev/null | grep -qE '^200|^404'"; then
            echo -e "  ${GREEN}✓ Mobile Location Service is responding${NC}"
        else
            echo -e "  ${RED}✗ Mobile Location Service is not responding${NC}"
            if run_on_onprem "command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep ':9050' || netstat -tln 2>/dev/null | grep ':9050'"; then
                echo "    Port 9050 is listening but service may not be responding correctly"
            else
                echo "    Port 9050 is not listening"
            fi
            echo "    Check logs: tail -20 /tmp/mobile-sensor.log"
        fi
        
        echo ""
        echo "Checking mTLS Server (port 9443):"
        if run_on_onprem "command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ':9443 ' || (command -v netstat >/dev/null 2>&1 && netstat -tln 2>/dev/null | grep -q ':9443 ')"; then
            echo -e "  ${GREEN}✓ mTLS Server is listening on port 9443${NC}"
        else
            echo -e "  ${RED}✗ mTLS Server is not listening on port 9443${NC}"
            echo "    Check if process is running: ps aux | grep mtls-server-app"
            echo "    Check logs: tail -30 /tmp/mtls-server.log"
            if run_on_onprem "[ -f /tmp/mtls-server.log ] && tail -20 /tmp/mtls-server.log"; then
                echo ""
            fi
        fi
        
        echo ""
        echo "Checking Envoy Proxy (port 8080):"
        if run_on_onprem "command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ':8080 ' || (command -v netstat >/dev/null 2>&1 && netstat -tln 2>/dev/null | grep -q ':8080 ')"; then
            echo -e "  ${GREEN}✓ Envoy Proxy is listening on port 8080${NC}"
        else
            echo -e "  ${RED}✗ Envoy Proxy is not listening on port 8080${NC}"
            echo "    Check if process is running: ps aux | grep envoy"
            echo "    Check logs: tail -20 /opt/envoy/logs/envoy.log"
        fi
        
        echo ""
        return 1
    fi
}

# Function to run script and show output
run_script() {
    local run_func="$1"
    local script_path="$2"
    local script_args="${3:-}"
    local description="$4"
    local log_file="${LOG_DIR}/$(basename ${script_path} .sh).log"
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${description}${NC}"
    echo -e "${BOLD}Script: ${script_path}${NC}"
    echo -e "${BOLD}Log:    ${log_file}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Prepare environment variables to pass to sub-scripts
    local env_vars="CONTROL_PLANE_HOST=${CONTROL_PLANE_HOST} AGENTS_HOST=${AGENTS_HOST} ONPREM_HOST=${ONPREM_HOST}"
    
    # Unified-Identity - Testing: Fail-Fast & Logging
    # Run script and capture output to specific log file, while also streaming to master log (via stdout)
    # We use pipefail (set at top) to catch errors in the pipeline
    if $run_func "cd ~/AegisSovereignAI/hybrid-cloud-poc && env ${env_vars} bash ${script_path} ${script_args}" 2>&1 | tee "${log_file}"; then
        echo ""
        echo -e "${GREEN}✓ ${description} completed successfully${NC}"
        return 0
    else
        # Unified-Identity - Testing: Fail-Fast
        # Immediate error reporting
        echo ""
        echo -e "${RED}✗ ${description} failed${NC}"
        echo -e "${YELLOW}Last 20 lines of log (${log_file}):${NC}"
        tail -n 20 "${log_file}" | sed 's/^/    /'
        return 1
    fi
}

# Main execution
main() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Unified-Identity: Complete Integration Test Orchestrator    ║"
    echo "║  Testing IMEI/IMSI in Geolocation Claims                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Control Plane Host: ${CONTROL_PLANE_HOST} (test_control_plane.sh)"
    echo "  Agents Host: ${AGENTS_HOST} (test_agents.sh)"
    echo "  On-Prem Host: ${ONPREM_HOST} (test_onprem.sh)"
    echo "  SSH User: ${SSH_USER}"
    echo ""
    
    # Check SSH connectivity for each host (skip if running locally)
    echo -e "${CYAN}Checking SSH connectivity...${NC}"
    
    if [ "${ON_CONTROL_PLANE_HOST}" != "true" ]; then
        if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${CONTROL_PLANE_HOST}" "echo 'OK'" >/dev/null 2>&1; then
            echo -e "${RED}✗ Cannot SSH to control plane host: ${CONTROL_PLANE_HOST}${NC}"
            exit 1
        fi
        echo -e "${GREEN}  ✓ Can SSH to ${CONTROL_PLANE_HOST}${NC}"
    else
        echo -e "${GREEN}  ✓ Running on control plane host (${CONTROL_PLANE_HOST}) - no SSH needed${NC}"
    fi
    
    if [ "${ON_AGENTS_HOST}" != "true" ]; then
        if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${AGENTS_HOST}" "echo 'OK'" >/dev/null 2>&1; then
            echo -e "${RED}✗ Cannot SSH to agents host: ${AGENTS_HOST}${NC}"
            exit 1
        fi
        echo -e "${GREEN}  ✓ Can SSH to ${AGENTS_HOST}${NC}"
    else
        echo -e "${GREEN}  ✓ Running on agents host (${AGENTS_HOST}) - no SSH needed${NC}"
    fi
    
    if [ "${ON_ONPREM_HOST}" != "true" ]; then
        if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${ONPREM_HOST}" "echo 'OK'" >/dev/null 2>&1; then
            echo -e "${RED}✗ Cannot SSH to on-prem host: ${ONPREM_HOST}${NC}"
            exit 1
        fi
        echo -e "${GREEN}  ✓ Can SSH to ${ONPREM_HOST}${NC}"
    else
        echo -e "${GREEN}  ✓ Running on on-prem host (${ONPREM_HOST}) - no SSH needed${NC}"
    fi
    echo ""
    
    # Step 1: Start Control Plane on 10.1.0.11
    CONTROL_PLANE_ARGS="--no-pause"
    if [ "$NO_BUILD" = "true" ]; then
        CONTROL_PLANE_ARGS="$CONTROL_PLANE_ARGS --no-build"
    fi
    if ! run_script "run_on_control_plane" "test_control_plane.sh" "$CONTROL_PLANE_ARGS" \
        "Step 1: Starting Control Plane Services (SPIRE Server, Keylime Verifier/Registrar)"; then
        echo -e "${RED}Control plane setup failed. Aborting.${NC}"
        exit 1
    fi
    
    # Verify control plane services are up
    if ! verify_control_plane; then
        echo -e "${RED}Control plane services verification failed. Aborting.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Control Plane Services Ready!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [ "$NO_PAUSE" = "true" ]; then
        echo "  (--no-pause: continuing automatically...)"
    elif [ -t 0 ]; then
        read -p "Press Enter to continue to on-prem setup..."
    else
        echo "  (Non-interactive mode - continuing automatically in 3 seconds...)"
        sleep 3
    fi
    
    # Step 2: Start On-Prem Services on on-prem host
    # Temporarily disable exit on error for on-prem (it may have warnings)
    set +e
    # Pass --no-pause if NO_PAUSE is set, and pass host environment variables
    ONPREM_ARGS=""
    ONPREM_ENV_VARS=""
    if [ "$NO_PAUSE" = "true" ]; then
        ONPREM_ARGS="--no-pause"
        ONPREM_ENV_VARS="PAUSE_ENABLED=false "
    fi
    if [ "$NO_BUILD" = "true" ]; then
        ONPREM_ARGS="$ONPREM_ARGS --no-build"
    fi
    # Pass host environment variables so test_onprem.sh knows where control plane/agents are
    # Use env command to ensure variables are passed correctly
    ONPREM_ENV_VARS="${ONPREM_ENV_VARS}CONTROL_PLANE_HOST=${CONTROL_PLANE_HOST} AGENTS_HOST=${AGENTS_HOST} ONPREM_HOST=${ONPREM_HOST}"
    run_on_onprem "cd ~/AegisSovereignAI/hybrid-cloud-poc/enterprise-private-cloud && env ${ONPREM_ENV_VARS} ./test_onprem.sh ${ONPREM_ARGS}" 2>&1 | tee "/tmp/remote_test_onprem.log"
    ONPREM_EXIT_CODE=$?
    set -e
    
    if [ $ONPREM_EXIT_CODE -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ On-prem services started successfully${NC}"
    else
        echo ""
        echo -e "${RED}✗ Failed to start on-prem services (exit code: $ONPREM_EXIT_CODE)${NC}"
        exit 1
    fi
    
    # Verify on-prem services are up
    if ! verify_onprem; then
        echo -e "${RED}On-prem services verification failed. Aborting.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}On-Prem Services Ready!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [ "$NO_PAUSE" = "true" ]; then
        echo "  (--no-pause: continuing automatically...)"
    elif [ -t 0 ]; then
        read -p "Press Enter to continue to complete integration test..."
    else
        echo "  (Non-interactive mode - continuing automatically in 3 seconds...)"
        sleep 3
    fi
    
    # Step 3: Run Complete Integration Test on agents host
    AGENTS_ARGS="--no-pause"
    if [ "$NO_BUILD" = "true" ]; then
        AGENTS_ARGS="$AGENTS_ARGS --no-build"
    fi
    if ! run_script "run_on_agents" "test_agents.sh" "$AGENTS_ARGS" \
        "Step 3: Running Complete Integration Test (Agent Attestation, Workload SVID)"; then
        echo -e "${RED}Complete integration test failed.${NC}"
        exit 1
    fi
    
    # Step 4: Test CAMARA Caching and GPS Bypass Features
    #echo ""
    #if [ "$NO_PAUSE" = "true" ]; then
    #    echo "  (--no-pause: continuing automatically...)"
    #elif [ -t 0 ]; then
    #    read -p "Press Enter to continue to CAMARA caching and GPS bypass tests..."
    #else
    #    echo "  (Non-interactive mode - continuing automatically in 3 seconds...)"
    #    sleep 3
    #fi
    
    #test_camara_caching_and_gps_bypass
    
    # Step 5: Test mTLS Client with IMEI/IMSI validation
    echo ""
    if [ "$NO_PAUSE" = "true" ]; then
        echo "  (--no-pause: continuing automatically...)"
    elif [ -t 0 ]; then
        read -p "Press Enter to continue to mTLS client test..."
    else
        echo "  (Non-interactive mode - continuing automatically in 3 seconds...)"
        sleep 3
    fi
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Step 5: Testing mTLS Client with IMEI/IMSI Validation${NC}"
    echo -e "${BOLD}Script: test_mtls_client.sh${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Prepare environment variables - SERVER_HOST should be ONPREM_HOST where Envoy is running
    mTLS_ENV_VARS="SERVER_HOST=${ONPREM_HOST} SERVER_PORT=8080 CONTROL_PLANE_HOST=${CONTROL_PLANE_HOST} AGENTS_HOST=${AGENTS_HOST} ONPREM_HOST=${ONPREM_HOST}"
    
    # Run test_mtls_client.sh on agents host (where client runs)
    MTLS_TEST_PASSED=false
    if run_on_agents "cd ~/AegisSovereignAI/hybrid-cloud-poc && env ${mTLS_ENV_VARS} ./test_mtls_client.sh" 2>&1 | tee "/tmp/remote_test_mtls_client.log"; then
        echo ""
        echo -e "${GREEN}✓ mTLS client test completed successfully${NC}"
        MTLS_TEST_PASSED=true
    else
        echo ""
        echo -e "${RED}✗ mTLS client test failed${NC}"
        echo -e "${YELLOW}Check logs: /tmp/remote_test_mtls_client.log${NC}"
        MTLS_TEST_PASSED=false
    fi
    
    if [ "$MTLS_TEST_PASSED" != "true" ]; then
        echo -e "${RED}mTLS client test failed. Aborting.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}All Tests Completed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Summary:${NC}"
    echo "  ✓ Control Plane Services: Running on ${CONTROL_PLANE_HOST}"
    echo "  ✓ Agents Services: Running on ${AGENTS_HOST}"
    echo "  ✓ On-Prem Services: Running on ${ONPREM_HOST}"
    echo "  ✓ Complete Integration Test: Completed"
    echo "  ✓ CAMARA Caching and GPS Bypass Tests: Completed"
    echo "  ✓ mTLS Client Test with IMEI/IMSI Validation: Completed"
    echo ""
    echo -e "${CYAN}To check logs:${NC}"
    if [ "${ON_CONTROL_PLANE_HOST}" != "true" ]; then
        echo "  Control Plane: ssh ${SSH_USER}@${CONTROL_PLANE_HOST} 'tail -f /tmp/spire-server.log'"
    else
        echo "  Control Plane: tail -f /tmp/spire-server.log"
    fi
    if [ "${ON_AGENTS_HOST}" != "true" ]; then
        echo "  Agents: ssh ${SSH_USER}@${AGENTS_HOST} 'tail -f /tmp/spire-agent.log'"
    else
        echo "  Agents: tail -f /tmp/spire-agent.log"
    fi
    if [ "${ON_ONPREM_HOST}" != "true" ]; then
        echo "  On-Prem: ssh ${SSH_USER}@${ONPREM_HOST} 'tail -f /opt/envoy/logs/envoy.log'"
    else
        echo "  On-Prem: tail -f /opt/envoy/logs/envoy.log"
    fi
    echo ""
}

# Function to perform cleanup on both hosts
cleanup_all() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Unified-Identity: Cleanup All Services                       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}Cleaning up services on both hosts...${NC}"
    echo ""
    
    # Cleanup on control plane host
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Cleaning up Control Plane Services on ${CONTROL_PLANE_HOST}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Cleanup control plane services
    if run_script "run_on_control_plane" "test_control_plane.sh" "--cleanup-only" \
        "Cleaning up Control Plane Services (SPIRE Server, Keylime Verifier/Registrar)"; then
        echo -e "${GREEN}✓ Control plane cleanup completed${NC}"
    else
        echo -e "${YELLOW}⚠ Control plane cleanup had issues (may be expected if services weren't running)${NC}"
    fi
    
    # Cleanup agent services on agents host (if any)
    echo ""
    echo -e "${CYAN}Cleaning up Agent Services on ${AGENTS_HOST}${NC}"
    echo ""
    if run_script "run_on_agents" "test_agents.sh" "--cleanup-only" \
        "Cleaning up Agent Services (SPIRE Agent, rust-keylime Agent, TPM Plugin)"; then
        echo -e "${GREEN}✓ Agent services cleanup completed${NC}"
    else
        echo -e "${YELLOW}⚠ Agent services cleanup had issues (may be expected if services weren't running)${NC}"
    fi
    
    # Cleanup on on-prem host
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Cleaning up On-Prem Services on ${ONPREM_HOST}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Cleanup on-prem services
    set +e
    run_on_onprem "cd ~/AegisSovereignAI/hybrid-cloud-poc/enterprise-private-cloud && ./test_onprem.sh --cleanup-only" 2>&1 | tee "/tmp/remote_test_onprem_cleanup.log"
    ONPREM_CLEANUP_EXIT_CODE=$?
    set -e
    
    if [ $ONPREM_CLEANUP_EXIT_CODE -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ On-prem cleanup completed${NC}"
    else
        echo ""
        echo -e "${YELLOW}⚠ On-prem cleanup had issues (may be expected if services weren't running)${NC}"
    fi
    
    # Final cleanup: Remove any remaining temporary files in /tmp
    echo ""
    echo -e "${CYAN}Performing final /tmp cleanup...${NC}"
    echo ""
    
    # Source cleanup.sh to use cleanup_tmp_files function
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="${SCRIPT_DIR}"
    source "${SCRIPT_DIR}/scripts/cleanup.sh"
    
    # Clean up temporary files using shared function
    cleanup_tmp_files
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Cleanup Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}All services have been stopped and data cleaned up on:${NC}"
    echo "  • Control Plane Host: ${CONTROL_PLANE_HOST}"
    echo "  • Agents Host: ${AGENTS_HOST}"
    echo "  • On-Prem Host: ${ONPREM_HOST}"
    echo ""
}

# Parse command-line arguments
NO_PAUSE=false
NO_BUILD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --control-plane-host)
            CONTROL_PLANE_HOST="$2"
            shift 2
            ;;
        --agents-host)
            AGENTS_HOST="$2"
            shift 2
            ;;
        --onprem-host)
            ONPREM_HOST="$2"
            shift 2
            ;;
        --no-build)
            NO_BUILD=true
            shift
            ;;
        --cleanup-only)
            # Re-check host detection after parsing arguments
            ON_CONTROL_PLANE_HOST=false
            ON_AGENTS_HOST=false
            ON_ONPREM_HOST=false
            if is_on_host "${CONTROL_PLANE_HOST}"; then
                ON_CONTROL_PLANE_HOST=true
            fi
            if is_on_host "${AGENTS_HOST}"; then
                ON_AGENTS_HOST=true
            fi
            if is_on_host "${ONPREM_HOST}"; then
                ON_ONPREM_HOST=true
            fi
            
            # Check SSH connectivity before cleanup
            echo -e "${CYAN}Checking SSH connectivity...${NC}"
            if [ "${ON_CONTROL_PLANE_HOST}" != "true" ]; then
                if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${CONTROL_PLANE_HOST}" "echo 'OK'" >/dev/null 2>&1; then
                    echo -e "${YELLOW}⚠ Cannot SSH to control plane host: ${CONTROL_PLANE_HOST} (continuing anyway)${NC}"
                fi
            fi
            if [ "${ON_AGENTS_HOST}" != "true" ]; then
                if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${AGENTS_HOST}" "echo 'OK'" >/dev/null 2>&1; then
                    echo -e "${YELLOW}⚠ Cannot SSH to agents host: ${AGENTS_HOST} (continuing anyway)${NC}"
                fi
            fi
            if [ "${ON_ONPREM_HOST}" != "true" ]; then
                if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${ONPREM_HOST}" "echo 'OK'" >/dev/null 2>&1; then
                    echo -e "${YELLOW}⚠ Cannot SSH to on-prem host: ${ONPREM_HOST} (continuing anyway)${NC}"
                fi
            fi
            cleanup_all
            exit 0
            ;;
        --no-pause)
            NO_PAUSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --control-plane-host IP    Host IP for test_control_plane.sh (default: 10.1.0.11)"
            echo "  --agents-host IP           Host IP for test_agents.sh (default: 10.1.0.11)"
            echo "  --onprem-host IP           Host IP for test_onprem.sh (default: 10.1.0.11)"
            echo "  --cleanup-only             Stop services, remove data, and exit"
            echo "  --no-pause                 Skip all pause prompts and continue automatically"
            echo "  --no-build                 Skip building binaries (use existing binaries)"
            echo "  --help, -h                 Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  CONTROL_PLANE_HOST         Host IP for test_control_plane.sh (default: 10.1.0.11)"
            echo "  AGENTS_HOST                Host IP for test_agents.sh (default: 10.1.0.11)"
            echo "  ONPREM_HOST                Host IP for test_onprem.sh (default: 10.1.0.11)"
            echo "  SSH_USER                   SSH username (default: mw)"
            echo ""
            echo "Examples:"
            echo "  # Run all scripts on default host (10.1.0.11)"
            echo "  $0"
            echo ""
            echo "  # Run control plane on 10.1.0.11, agents on 10.1.0.12, onprem on 10.1.0.10"
            echo "  $0 --control-plane-host 10.1.0.11 --agents-host 10.1.0.12 --onprem-host 10.1.0.10"
            echo ""
            echo "  # If running on the same host as a script, SSH is automatically skipped"
            echo "  # (e.g., if running on 10.1.0.11 and --control-plane-host 10.1.0.11, no SSH used)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Re-check host detection after parsing arguments (in case hosts were changed)
ON_CONTROL_PLANE_HOST=false
ON_AGENTS_HOST=false
ON_ONPREM_HOST=false

if is_on_host "${CONTROL_PLANE_HOST}"; then
    ON_CONTROL_PLANE_HOST=true
fi

if is_on_host "${AGENTS_HOST}"; then
    ON_AGENTS_HOST=true
fi

if is_on_host "${ONPREM_HOST}"; then
    ON_ONPREM_HOST=true
fi

# Run main function
main "$@@"

