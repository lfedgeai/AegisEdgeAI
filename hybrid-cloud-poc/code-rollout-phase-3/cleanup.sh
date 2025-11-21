#!/usr/bin/env bash
# Unified-Identity - Phase 3: Cleanup Script
# Stops all services and cleans up all data directories, logs, and temporary files
# Use this script to reset the environment after running tests or deployments

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE1_DIR="${SCRIPT_DIR}/../code-rollout-phase-1"
PHASE2_DIR="${SCRIPT_DIR}/../code-rollout-phase-2"
PHASE3_DIR="${SCRIPT_DIR}"
KEYLIME_DIR="${PHASE2_DIR}/keylime"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    BOLD=""
    NC=""
fi

# Only show header when executed directly, not when sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Unified-Identity - Phase 3: Cleanup                           ║"
    echo "║  Stopping all services and cleaning up data                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
fi

# Function to stop all existing instances and clean up all data
# If SKIP_HEADER is set, don't print the header message (for use in test scripts)
stop_all_instances_and_cleanup() {
    if [ -z "${SKIP_HEADER:-}" ]; then
        echo -e "${CYAN}Stopping all existing instances and cleaning up all data...${NC}"
        echo ""
    fi
    
    # Step 1: Stop all processes
    echo "  1. Stopping all processes..."
    
    # Stop SPIRE processes
    echo "     Stopping SPIRE Server and Agent..."
    pkill -f "spire-server" >/dev/null 2>&1 || true
    pkill -f "spire-agent" >/dev/null 2>&1 || true
    
    # Stop Keylime processes
    echo "     Stopping Keylime Verifier and Registrar..."
    pkill -f "keylime_verifier" >/dev/null 2>&1 || true
    pkill -f "keylime\.cmd\.verifier" >/dev/null 2>&1 || true
    pkill -f "keylime_registrar" >/dev/null 2>&1 || true
    pkill -f "keylime\.cmd\.registrar" >/dev/null 2>&1 || true
    pkill -f "python.*keylime" >/dev/null 2>&1 || true
    
    # Stop rust-keylime Agent
    echo "     Stopping rust-keylime Agent..."
    pkill -f "keylime_agent" >/dev/null 2>&1 || true
    pkill -f "rust-keylime" >/dev/null 2>&1 || true
    pkill -f "target/release/keylime_agent" >/dev/null 2>&1 || true
    
    # Stop TPM Plugin Server
    echo "     Stopping TPM Plugin Server..."
    pkill -f "tpm_plugin_server" >/dev/null 2>&1 || true

    # Stop mobile location verification microservice
    echo "     Stopping Mobile Location Verification microservice..."
    pkill -f "mobile-sensor-microservice" >/dev/null 2>&1 || true
    pkill -f "mobile_sensor_service" >/dev/null 2>&1 || true
    pkill -f "mobile-sensor-microservice/service.py" >/dev/null 2>&1 || true

    # Wait a moment for processes to stop before unmounting
    sleep 1
    
    # Unmount tmpfs secure directory if mounted (try multiple methods)
    SECURE_DIR="/tmp/keylime-agent/secure"
    KEYLIME_AGENT_DIR="/tmp/keylime-agent"
    if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
        echo "     Unmounting tmpfs secure directory..."
        # Try multiple unmount methods
        sudo umount "$SECURE_DIR" 2>/dev/null || \
        sudo umount -l "$SECURE_DIR" 2>/dev/null || \
        sudo umount -f "$SECURE_DIR" 2>/dev/null || true
        # Verify it's unmounted
        if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
            echo -e "${YELLOW}     ⚠ Warning: tmpfs still mounted, may need manual cleanup${NC}"
        else
            echo -e "${GREEN}     ✓ tmpfs unmounted successfully${NC}"
        fi
    fi
    
    # Also check for any other tmpfs mounts in keylime-agent directory
    if mount | grep -q "$KEYLIME_AGENT_DIR"; then
        echo "     Unmounting any remaining mounts in keylime-agent directory..."
        mount | grep "$KEYLIME_AGENT_DIR" | awk '{print $3}' | while read -r mount_point; do
            sudo umount "$mount_point" 2>/dev/null || \
            sudo umount -l "$mount_point" 2>/dev/null || true
        done
    fi
    
    # Stop TPM resource manager and any software TPM emulators
    pkill -f "tpm2-abrmd" >/dev/null 2>&1 || true
    pkill -f "swtpm" >/dev/null 2>&1 || true
    
    # Clear and initialize TPM state
    echo "     Clearing and initializing TPM state..."
    if [ -c /dev/tpm0 ] || [ -c /dev/tpmrm0 ]; then
        # Ensure tpm2-abrmd is running for TPM operations (if using tpmrm0)
        if [ -c /dev/tpmrm0 ]; then
            if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
                echo "       Starting tpm2-abrmd for TPM operations..."
                if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet tpm2-abrmd 2>/dev/null; then
                    sudo systemctl start tpm2-abrmd 2>/dev/null || true
                    sleep 2
                elif command -v tpm2-abrmd >/dev/null 2>&1; then
                    tpm2-abrmd --tcti=device 2>/dev/null &
                    sleep 2
                fi
            fi
        fi
        
        if command -v tpm2_clear >/dev/null 2>&1 && command -v tpm2_startup >/dev/null 2>&1; then
            # Use tpmrm0 if available (resource manager), otherwise tpm0
            TPM_DEVICE="/dev/tpmrm0"
            if [ ! -c "$TPM_DEVICE" ]; then
                TPM_DEVICE="/dev/tpm0"
            fi
            # Clear TPM state (resets TPM to clean state, fixes quote hang issues)
            # This is safe and doesn't require platform authorization on most systems
            echo "       Clearing TPM..."
            if timeout 10 env TCTI="device:${TPM_DEVICE}" tpm2_clear 2>/dev/null; then
                echo "       ✓ TPM cleared"
            else
                echo "       ⚠ TPM clear failed or timed out (continuing anyway)"
            fi
            # Initialize TPM after clear
            if TCTI="device:${TPM_DEVICE}" tpm2_startup -c 2>/dev/null; then
                echo "       ✓ TPM initialized"
            else
                echo "       ⚠ TPM initialization skipped"
            fi
        elif command -v tpm2_startup >/dev/null 2>&1; then
            # Fallback to just startup if clear is not available
            TPM_DEVICE="/dev/tpmrm0"
            if [ ! -c "$TPM_DEVICE" ]; then
                TPM_DEVICE="/dev/tpm0"
            fi
            if TCTI="device:${TPM_DEVICE}" tpm2_startup -c 2>/dev/null; then
                echo "     TPM initialized (clear not available)"
            else
                echo "     TPM initialization skipped"
            fi
        fi
    fi
    
    # Kill processes using ports
    if command -v lsof >/dev/null 2>&1; then
        echo "     Freeing up ports..."
        lsof -ti:8881 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:9002 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:8080 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:8081 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:8890 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:8891 | xargs kill -9 >/dev/null 2>&1 || true
    fi
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 8881/tcp >/dev/null 2>&1 || true
        fuser -k 9002/tcp >/dev/null 2>&1 || true
        fuser -k 8080/tcp >/dev/null 2>&1 || true
        fuser -k 8081/tcp >/dev/null 2>&1 || true
        fuser -k 8890/tcp >/dev/null 2>&1 || true
        fuser -k 8891/tcp >/dev/null 2>&1 || true
    fi
    
    # Wait for processes to fully stop
    sleep 2
    
    # Force kill any remaining processes
    RUNNING_COUNT=0
    if pgrep -f "spire-server|spire-agent|keylime|tpm_plugin" >/dev/null 2>&1; then
        RUNNING_COUNT=$(pgrep -f "spire-server|spire-agent|keylime|tpm_plugin" | wc -l)
        if [ "$RUNNING_COUNT" -gt 0 ]; then
            echo "     Force killing $RUNNING_COUNT remaining process(es)..."
            pkill -9 -f "spire-server" >/dev/null 2>&1 || true
            pkill -9 -f "spire-agent" >/dev/null 2>&1 || true
            pkill -9 -f "keylime" >/dev/null 2>&1 || true
            pkill -9 -f "tpm_plugin" >/dev/null 2>&1 || true
            sleep 1
        fi
    fi
    
    # Step 2: Clean up all data directories and databases
    echo "  2. Cleaning up all data directories and databases..."
    
    # Clean up SPIRE data directories
    echo "     Removing SPIRE data directories..."
    sudo rm -rf /opt/spire/data 2>/dev/null || true
    rm -rf /tmp/spire-server 2>/dev/null || true
    rm -rf /tmp/spire-agent 2>/dev/null || true
    rm -rf /tmp/spire-data 2>/dev/null || true
    
    # Clean up Keylime databases and persistent data
    echo "     Removing Keylime databases and persistent data..."
    if [ -n "${KEYLIME_DIR:-}" ] && [ -d "${KEYLIME_DIR}" ]; then
        rm -f "${KEYLIME_DIR}/verifier.db" 2>/dev/null || true
        rm -f "${KEYLIME_DIR}/verifier.sqlite" 2>/dev/null || true
        rm -f "${KEYLIME_DIR}/cv_data.sqlite" 2>/dev/null || true
        rm -f "${KEYLIME_DIR}"/*.db 2>/dev/null || true
        rm -f "${KEYLIME_DIR}"/*.sqlite 2>/dev/null || true
    fi
    # Clean up /tmp/keylime directory (contains registrar database)
    rm -rf /tmp/keylime 2>/dev/null || true
    # Clean up any Keylime data in user home directory
    rm -rf "$HOME/.keylime" 2>/dev/null || true
    rm -rf "$HOME/.local/share/keylime" 2>/dev/null || true
    # Clean up any Keylime data in /var/lib/keylime (if accessible)
    sudo rm -rf /var/lib/keylime 2>/dev/null || true
    
    # Clean up Phase 3 TPM data
    echo "     Removing Phase 3 TPM data..."
    rm -rf /tmp/phase3-demo-tpm 2>/dev/null || true
    rm -rf "$HOME/.spire/data/agent/tpm-plugin" 2>/dev/null || true
    rm -rf "$HOME/.spire" 2>/dev/null || true
    rm -rf /tmp/spire-data/tpm-plugin 2>/dev/null || true
    rm -rf /tmp/tpm-plugin-* 2>/dev/null || true
    rm -rf /tmp/rust-keylime-data 2>/dev/null || true
    # Clean up any TPM plugin state files
    rm -f /tmp/tpm-plugin*.pid 2>/dev/null || true
    rm -f /tmp/tpm-plugin*.log 2>/dev/null || true
    rm -f /tmp/tpm-plugin*.sock 2>/dev/null || true

    # Clean up mobile location verification microservice data
    echo "     Removing mobile location verification microservice data..."
    rm -rf /tmp/mobile-sensor-service 2>/dev/null || true
    rm -f /tmp/mobile-sensor-microservice.pid 2>/dev/null || true

    # Clean up rust-keylime agent directory (after ensuring tmpfs is unmounted)
    echo "     Removing rust-keylime agent data directory..."
    # Make sure it's not mounted before removing
    if mountpoint -q "/tmp/keylime-agent/secure" 2>/dev/null; then
        echo -e "${YELLOW}     ⚠ Warning: /tmp/keylime-agent/secure still mounted, skipping directory removal${NC}"
    else
        rm -rf /tmp/keylime-agent 2>/dev/null || true
    fi
    
    # Clean up SVID dump directory
    echo "     Removing SVID dump directory..."
    rm -rf /tmp/svid-dump 2>/dev/null || true
    
    # Clean up TLS certificates
    if [ -n "${KEYLIME_DIR:-}" ] && [ -d "${KEYLIME_DIR}" ]; then
        echo "     Removing TLS certificates..."
        rm -rf "${KEYLIME_DIR}/cv_ca" 2>/dev/null || true
        rm -rf "${KEYLIME_DIR}/reg_ca" 2>/dev/null || true
    fi
    
    # Step 3: Clean up all PID files
    echo "  3. Removing PID files..."
    rm -f /tmp/keylime-verifier.pid 2>/dev/null || true
    rm -f /tmp/keylime-registrar.pid 2>/dev/null || true
    rm -f /tmp/keylime-agent.pid 2>/dev/null || true
    rm -f /tmp/rust-keylime-agent.pid 2>/dev/null || true
    rm -f /tmp/spire-server.pid 2>/dev/null || true
    rm -f /tmp/spire-agent.pid 2>/dev/null || true
    rm -f /tmp/tpm-plugin-server.pid 2>/dev/null || true
    
    # Step 4: Clean up all log files
    echo "  4. Removing log files..."
    rm -f /tmp/keylime-test.log 2>/dev/null || true
    rm -f /tmp/keylime-verifier.log 2>/dev/null || true
    rm -f /tmp/keylime-registrar.log 2>/dev/null || true
    rm -f /tmp/keylime-agent.log 2>/dev/null || true
    rm -f /tmp/rust-keylime-agent.log 2>/dev/null || true
    rm -f /tmp/spire-server.log 2>/dev/null || true
    rm -f /tmp/spire-agent.log 2>/dev/null || true
    rm -f /tmp/spire-agent-test.log 2>/dev/null || true
    rm -f /tmp/tpm-plugin-server.log 2>/dev/null || true
    rm -f /tmp/bundle.pem 2>/dev/null || true
    rm -f /tmp/phase3_complete_workflow_logs.txt 2>/dev/null || true
    rm -f /tmp/phase3_*.log 2>/dev/null || true
    rm -f /tmp/test_phase3_*.log 2>/dev/null || true
    rm -f /tmp/mobile-sensor-microservice.log 2>/dev/null || true
    # Clean up temporary config files
    rm -f /tmp/keylime-agent-*.conf 2>/dev/null || true
    rm -f /tmp/*.conf.tmp 2>/dev/null || true
    
    # Step 5: Clean up sockets
    echo "  5. Removing socket files..."
    rm -f /tmp/spire-server/private/api.sock 2>/dev/null || true
    rm -f /tmp/spire-agent/public/api.sock 2>/dev/null || true
    rm -f /var/run/keylime/keylime-agent-certify.sock 2>/dev/null || true
    rm -f "$HOME/.keylime/run/keylime-agent-certify.sock" 2>/dev/null || true
    rm -f /tmp/keylime-agent.sock 2>/dev/null || true
    rm -f /tmp/spire-data/tpm-plugin/tpm-plugin.sock 2>/dev/null || true
    rm -f /tmp/mobile-sensor.sock 2>/dev/null || true
    # Clean up any other socket files
    find /tmp -name "*.sock" -type s 2>/dev/null | grep -E "(keylime|spire|tpm)" | xargs rm -f 2>/dev/null || true
    rm -rf /tmp/spire-server 2>/dev/null || true
    rm -rf /tmp/spire-agent 2>/dev/null || true
    
    # Step 6: Recreate clean data directories (optional - comment out if you don't want this)
    echo "  6. Creating clean data directories..."
    sudo mkdir -p /opt/spire/data/server /opt/spire/data/agent 2>/dev/null || true
    sudo chown -R "$(whoami):$(whoami)" /opt/spire/data 2>/dev/null || true
    mkdir -p /tmp/spire-server/private 2>/dev/null || true
    mkdir -p /tmp/spire-agent/public 2>/dev/null || true
    mkdir -p /tmp/spire-data/server /tmp/spire-data/agent 2>/dev/null || true
    mkdir -p /tmp/rust-keylime-data 2>/dev/null || true
    mkdir -p ~/.keylime/run 2>/dev/null || true
    
    # Ensure keylime-agent directory is clean and ready (but don't mount tmpfs yet)
    mkdir -p /tmp/keylime-agent 2>/dev/null || true
    # Remove secure subdirectory if it exists (will be recreated and mounted by agent)
    if [ -d "/tmp/keylime-agent/secure" ] && ! mountpoint -q "/tmp/keylime-agent/secure" 2>/dev/null; then
        rm -rf /tmp/keylime-agent/secure 2>/dev/null || true
    fi
    
    # Final verification
    echo ""
    if ! pgrep -f "spire-server|spire-agent|keylime|tpm_plugin" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ All existing instances stopped and all data cleaned up${NC}"
        return 0
    else
        echo -e "${YELLOW}  ⚠ Some processes may still be running:${NC}"
        pgrep -f "spire-server|spire-agent|keylime|tpm_plugin" || true
        return 1
    fi
}

# Usage helper
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -h, --help    Show this help message.

This script stops all Unified-Identity Phase 3 services and cleans up:
  - All running processes (SPIRE Server/Agent, Keylime Verifier/Registrar/Agent, TPM Plugin)
  - All data directories and databases
  - All log files and PID files
  - All socket files
  - TPM state (if accessible)
  - tmpfs mounts

After cleanup, clean data directories are recreated for the next run.

Examples:
  $0              # Run full cleanup
  $0 --help       # Show this help message
EOF
}

# Check if script is being sourced or executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being executed directly - parse arguments and run cleanup
    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    # Run cleanup
    stop_all_instances_and_cleanup

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Cleanup Complete                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "All services have been stopped and data has been cleaned up."
    echo "You can now run setup.sh and test scripts again."
    echo ""
fi
# If script is sourced, functions are available but cleanup doesn't run automatically

