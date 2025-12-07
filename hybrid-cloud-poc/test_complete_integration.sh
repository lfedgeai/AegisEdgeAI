#!/bin/bash
# Unified-Identity: Complete Integration Test Orchestrator
# Runs all test scripts in sequence across both machines (10.1.0.11 and 10.1.0.10)
# Verifies components are up before proceeding to next step

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-10.1.0.11}"
ONPREM_HOST="${ONPREM_HOST:-10.1.0.10}"
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

# Detect if we're running on the control plane host
CURRENT_HOST_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' || echo '')
ON_CONTROL_PLANE_HOST=false

# Check if any of our IPs match the control plane host IP
if echo "$CURRENT_HOST_IPS" | grep -q "^${CONTROL_PLANE_HOST}$"; then
    ON_CONTROL_PLANE_HOST=true
else
    # Try to check via hostname comparison
    CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo '')
    if [ -n "${CURRENT_HOSTNAME}" ]; then
        CONTROL_PLANE_HOSTNAME=$(getent hosts ${CONTROL_PLANE_HOST} 2>/dev/null | awk '{print $2}' | head -1 || echo '')
        if [ -z "${CONTROL_PLANE_HOSTNAME}" ]; then
            CONTROL_PLANE_HOSTNAME=$(ssh ${SSH_OPTS} -o ConnectTimeout=2 ${SSH_USER}@${CONTROL_PLANE_HOST} 'hostname' 2>/dev/null || echo '')
        fi
        if [ "${CURRENT_HOSTNAME}" = "${CONTROL_PLANE_HOSTNAME}" ] && [ -n "${CONTROL_PLANE_HOSTNAME}" ]; then
            ON_CONTROL_PLANE_HOST=true
        fi
    fi
fi

# Function to run command on control plane host (local or via SSH)
run_on_control_plane() {
    if [ "${ON_CONTROL_PLANE_HOST}" = "true" ]; then
        # Execute locally on 10.1.0.11 - no SSH needed
        bash -c "$@"
    else
        # Execute via SSH
        ssh ${SSH_OPTS} ${SSH_USER}@${CONTROL_PLANE_HOST} "$@"
    fi
}

# Function to run command on on-prem host (always via SSH)
run_on_onprem() {
    ssh ${SSH_OPTS} ${SSH_USER}@${ONPREM_HOST} "$@"
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
        "Mobile Sensor Service|curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{}' http://localhost:9050/verify | grep -q '200\|404'"
    )
    
    wait_for_services "run_on_control_plane" "${checks[@]}"
}

# Function to verify on-prem services
verify_onprem() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Verifying On-Prem Services on ${ONPREM_HOST}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local checks=(
        "Mobile Location Service|curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{}' http://localhost:5000/verify | grep -q '200\|404'"
        "mTLS Server|curl -s -k https://localhost:9443/health >/dev/null 2>&1 || ss -tln 2>/dev/null | grep -q ':9443' || netstat -tln 2>/dev/null | grep -q ':9443'"
        "Envoy Proxy|ss -tln 2>/dev/null | grep -q ':8080' || netstat -tln 2>/dev/null | grep -q ':8080'"
    )
    
    wait_for_services "run_on_onprem" "${checks[@]}"
}

# Function to run script and show output
run_script() {
    local run_func="$1"
    local script_path="$2"
    local script_args="${3:-}"
    local description="$4"
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${description}${NC}"
    echo -e "${BOLD}Script: ${script_path}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Run script (local or via SSH depending on run_func)
    if $run_func "cd ~/AegisEdgeAI/hybrid-cloud-poc && bash ${script_path} ${script_args}" 2>&1 | tee "/tmp/remote_$(basename ${script_path}).log"; then
        echo ""
        echo -e "${GREEN}✓ ${description} completed successfully${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}✗ ${description} failed${NC}"
        echo -e "${YELLOW}Check logs: /tmp/remote_$(basename ${script_path}).log${NC}"
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
    echo "  Control Plane Host: ${CONTROL_PLANE_HOST}"
    echo "  On-Prem Host: ${ONPREM_HOST}"
    echo "  SSH User: ${SSH_USER}"
    echo ""
    
    # Check if we can SSH to on-prem host (control plane may be local)
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
    
    if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${ONPREM_HOST}" "echo 'OK'" >/dev/null 2>&1; then
        echo -e "${RED}✗ Cannot SSH to on-prem host: ${ONPREM_HOST}${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ Can SSH to ${ONPREM_HOST}${NC}"
    echo ""
    
    # Step 1: Start Control Plane on 10.1.0.11
    if ! run_script "run_on_control_plane" "test_complete_control_plane.sh" "--no-pause" \
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
    
    # Step 2: Start On-Prem Services on 10.1.0.10
    # Temporarily disable exit on error for on-prem (it may have warnings)
    set +e
    run_on_onprem "cd ~/AegisEdgeAI/hybrid-cloud-poc/enterprise-private-cloud && ./test_onprem.sh" 2>&1 | tee "/tmp/remote_test_onprem.log"
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
    
    # Step 3: Run Complete Integration Test on 10.1.0.11
    if ! run_script "run_on_control_plane" "test_complete.sh" "--no-pause" \
        "Step 3: Running Complete Integration Test (Agent Attestation, Workload SVID)"; then
        echo -e "${RED}Complete integration test failed.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}All Tests Completed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Summary:${NC}"
    echo "  ✓ Control Plane Services: Running on ${CONTROL_PLANE_HOST}"
    echo "  ✓ On-Prem Services: Running on ${ONPREM_HOST}"
    echo "  ✓ Complete Integration Test: Completed"
    echo ""
    echo -e "${CYAN}To check logs:${NC}"
    echo "  Control Plane: ssh ${SSH_USER}@${CONTROL_PLANE_HOST} 'tail -f /tmp/spire-server.log'"
    echo "  On-Prem: ssh ${SSH_USER}@${ONPREM_HOST} 'tail -f /opt/envoy/logs/envoy.log'"
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
    if run_script "run_on_control_plane" "test_complete_control_plane.sh" "--cleanup-only" \
        "Cleaning up Control Plane Services (SPIRE Server, Keylime Verifier/Registrar)"; then
        echo -e "${GREEN}✓ Control plane cleanup completed${NC}"
    else
        echo -e "${YELLOW}⚠ Control plane cleanup had issues (may be expected if services weren't running)${NC}"
    fi
    
    # Cleanup agent services on control plane (if any)
    echo ""
    echo -e "${CYAN}Cleaning up Agent Services on ${CONTROL_PLANE_HOST}${NC}"
    echo ""
    if run_script "run_on_control_plane" "test_complete.sh" "--cleanup-only" \
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
    run_on_onprem "cd ~/AegisEdgeAI/hybrid-cloud-poc/enterprise-private-cloud && ./test_onprem.sh --cleanup-only" 2>&1 | tee "/tmp/remote_test_onprem_cleanup.log"
    ONPREM_CLEANUP_EXIT_CODE=$?
    set -e
    
    if [ $ONPREM_CLEANUP_EXIT_CODE -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ On-prem cleanup completed${NC}"
    else
        echo ""
        echo -e "${YELLOW}⚠ On-prem cleanup had issues (may be expected if services weren't running)${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Cleanup Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}All services have been stopped and data cleaned up on:${NC}"
    echo "  • Control Plane Host: ${CONTROL_PLANE_HOST}"
    echo "  • On-Prem Host: ${ONPREM_HOST}"
    echo ""
}

# Parse command-line arguments
NO_PAUSE=false
for arg in "$@"; do
    case $arg in
        --cleanup-only)
            # Check SSH connectivity before cleanup
            echo -e "${CYAN}Checking SSH connectivity...${NC}"
            if [ "${ON_CONTROL_PLANE_HOST}" != "true" ]; then
                if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${CONTROL_PLANE_HOST}" "echo 'OK'" >/dev/null 2>&1; then
                    echo -e "${YELLOW}⚠ Cannot SSH to control plane host: ${CONTROL_PLANE_HOST} (continuing anyway)${NC}"
                fi
            fi
            if ! ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${ONPREM_HOST}" "echo 'OK'" >/dev/null 2>&1; then
                echo -e "${YELLOW}⚠ Cannot SSH to on-prem host: ${ONPREM_HOST} (continuing anyway)${NC}"
            fi
            cleanup_all
            exit 0
            ;;
        --no-pause)
            NO_PAUSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--cleanup-only] [--no-pause]"
            echo ""
            echo "Options:"
            echo "  --cleanup-only Stop services, remove data, and exit"
            echo "  --no-pause     Skip all pause prompts and continue automatically"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
        *)
            # Unknown option, pass through
            ;;
    esac
done

# Run main function
main "$@"

