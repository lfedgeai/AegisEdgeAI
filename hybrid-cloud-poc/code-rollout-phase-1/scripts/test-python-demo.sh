#!/bin/bash
# Unified-Identity - Phase 1: Automated end-to-end test for Python demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_DEMO_DIR="${PROJECT_ROOT}/python-app-demo"

SERVER_CONFIG="${SERVER_CONFIG:-${PYTHON_DEMO_DIR}/spire-server.conf}"
AGENT_CONFIG="${AGENT_CONFIG:-${PYTHON_DEMO_DIR}/spire-agent.conf}"
AGENT_SPIFFE_ID="${AGENT_SPIFFE_ID:-spiffe://example.org/host/python-demo-agent}"

# ANSI color codes
BOLD='\033[1m'
CYAN='\033[0;36m'
RESET='\033[0m'

fail() {
    echo "✗ $1" >&2
    exit 1
}

step() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${RESET}"
}

wait_for_log() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    local timeout="${4:-30}"

    for _ in $(seq 1 "$timeout"); do
        if [ -f "$file" ] && grep -qi "$pattern" "$file"; then
            echo "  ✓ $description"
            return 0
        fi
        sleep 1
    done
    grep -i "$pattern" "$file" || true
    fail "Timed out waiting for $description"
}

step "Cleaning up any previous runs"
"${PYTHON_DEMO_DIR}/cleanup.sh" || true

# Verify clean state (no entries, no processes)
SPIRE_DIR="${PROJECT_ROOT}/spire"
SERVER_SOCKET="/tmp/spire-server/private/api.sock"
if [ -S "$SERVER_SOCKET" ] && [ -f "${SPIRE_DIR}/bin/spire-server" ]; then
    ENTRY_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list -socketPath "$SERVER_SOCKET" 2>/dev/null || echo "")
    if [ -n "$ENTRY_LIST" ] && echo "$ENTRY_LIST" | grep -q "Entry ID"; then
        echo "  ⚠ WARNING: Registration entries still exist after cleanup"
        echo "  ⚠ This may cause test failures - entries should be cleaned up"
    else
        echo "  ✓ Verified: No registration entries (clean state)"
    fi
else
    echo "  ✓ Verified: SPIRE server not running (clean state)"
fi

step "Ensuring Python dependencies"
if ! python3 -c "import spiffe.workloadapi" 2>/dev/null || ! python3 -c "import grpc" 2>/dev/null; then
    python3 -m pip install -r "${PYTHON_DEMO_DIR}/requirements.txt" || fail "Failed to install Python dependencies"
fi

if [ -f "${PYTHON_DEMO_DIR}/fetch-sovereign-svid-grpc.py" ] && [ ! -f "${PYTHON_DEMO_DIR}/generated/spiffe/workload/workload_pb2.py" ]; then
    if [ -f "${PYTHON_DEMO_DIR}/generate-proto-stubs.sh" ]; then
        (cd "${PYTHON_DEMO_DIR}" && ./generate-proto-stubs.sh) || fail "Failed to generate protobuf stubs"
    fi
fi

step "Starting SPIRE stack"
SERVER_CONFIG="$SERVER_CONFIG" AGENT_CONFIG="$AGENT_CONFIG" AGENT_SPIFFE_ID="$AGENT_SPIFFE_ID" \
    "${PROJECT_ROOT}/scripts/start-unified-identity.sh"

step "Verifying agent bootstrap AttestedClaims"
# Check for SovereignAttestation being received during bootstrap
wait_for_log /tmp/spire-server.log "Received SovereignAttestation in agent bootstrap request" "Server received SovereignAttestation during bootstrap" 60
# Check for AttestedClaims being attached to agent bootstrap SVID
wait_for_log /tmp/spire-server.log "AttestedClaims attached to agent bootstrap SVID" "Server attached AttestedClaims to agent bootstrap SVID" 60
# Check for Keylime processing
wait_for_log /tmp/keylime-stub.log "Returning stubbed AttestedClaims response" "Keylime stub returned claims during bootstrap" 60
# Check for agent receiving AttestedClaims
wait_for_log /tmp/spire-agent.log "Received AttestedClaims during agent bootstrap" "Agent received AttestedClaims during bootstrap" 60

echo "  ↪ Server bootstrap log (SovereignAttestation received):"
grep -i "Received SovereignAttestation in agent bootstrap request" /tmp/spire-server.log | tail -1 | sed 's/^/    /' || echo "    (not found)"

echo "  ↪ Server bootstrap log (AttestedClaims attached):"
BOOTSTRAP_CLAIMS=$(grep -i "AttestedClaims attached to agent bootstrap SVID" /tmp/spire-server.log | tail -1 || true)
if [ -n "$BOOTSTRAP_CLAIMS" ]; then
    echo "    ${BOOTSTRAP_CLAIMS}" | sed 's/^/    /'
else
    fail "Server did not attach AttestedClaims to agent bootstrap SVID"
fi

echo "  ↪ Agent bootstrap log:"
AGENT_BOOTSTRAP=$(grep -i "Received AttestedClaims during agent bootstrap" /tmp/spire-agent.log | tail -1 || true)
if [ -n "$AGENT_BOOTSTRAP" ]; then
    echo "    ${AGENT_BOOTSTRAP}" | sed 's/^/    /'
else
    fail "Agent did not receive AttestedClaims during bootstrap"
fi

step "Creating registration entry for Python app"
"${PYTHON_DEMO_DIR}/create-registration-entry.sh" > /tmp/python-demo-registration.log

step "Fetching sovereign SVID via gRPC"
python3 "${PYTHON_DEMO_DIR}/fetch-sovereign-svid-grpc.py" > /tmp/python-demo-fetch.log

step "Validating SVID outputs"
[ -f /tmp/svid-dump/svid.pem ] || fail "Missing SVID certificate output"
[ -f /tmp/svid-dump/attested_claims.json ] || fail "Missing AttestedClaims output"

python3 - <<'PY'
import json
from pathlib import Path

claims = json.loads(Path("/tmp/svid-dump/attested_claims.json").read_text())
required = ["geolocation", "host_integrity_status", "gpu_metrics_health"]
missing = [key for key in required if key not in claims]
if missing:
    raise SystemExit(f"Missing expected AttestedClaims fields: {missing}")

gpu = claims.get("gpu_metrics_health", {})
for key in ("status", "utilization_pct", "memory_mb"):
    if key not in gpu:
        raise SystemExit(f"Missing gpu_metrics_health field: {key}")
print("AttestedClaims JSON looks valid")
PY

step "Verifying Unified-Identity logs after workload SVID fetch"
# Verify server processed SovereignAttestation for workload
wait_for_log /tmp/spire-server.log "Processing SovereignAttestation" "Server processed SovereignAttestation for workload" 60
# Verify server added AttestedClaims to workload response
wait_for_log /tmp/spire-server.log "Added AttestedClaims to response" "Server added AttestedClaims to workload SVID response" 60
# Verify agent fetched workload SVID
wait_for_log /tmp/spire-agent.log "Fetched X.509 SVID" "Agent fetched workload SVID" 60
wait_for_log /tmp/spire-agent.log "python-app" "Agent log references python app" 60
# Verify policy evaluation
wait_for_log /tmp/spire-server.log "Policy evaluation passed" "Server log indicates policy success" 60
# Verify Keylime stub was called
wait_for_log /tmp/keylime-stub.log "Returning stubbed AttestedClaims response" "Keylime stub returned claims" 60

echo "  ↪ Server workload log (SovereignAttestation processed):"
grep -i "python-app" /tmp/spire-server.log | grep -i "Processing SovereignAttestation" | tail -1 | sed 's/^/    /' || echo "    (not found)"

echo "  ↪ Server workload log (AttestedClaims added):"
SERVER_WORKLOAD=$(grep -i "python-app" /tmp/spire-server.log | grep -i "Added AttestedClaims" | tail -1 || true)
if [ -n "$SERVER_WORKLOAD" ]; then
    echo "    ${SERVER_WORKLOAD}" | sed 's/^/    /'
else
    fail "Server did not add AttestedClaims to workload SVID response"
fi

echo "  ↪ Agent workload log:"
AGENT_WORKLOAD=$(grep -i "python-app" /tmp/spire-agent.log | grep -i "Fetched X.509 SVID" | tail -1 || true)
if [ -n "$AGENT_WORKLOAD" ]; then
    echo "    ${AGENT_WORKLOAD}" | sed 's/^/    /'
else
    fail "Agent did not fetch workload SVID for python-app"
fi

step "Dumping SVID for inspection"
"${PROJECT_ROOT}/scripts/dump-svid" -cert /tmp/svid-dump/svid.pem -attested /tmp/svid-dump/attested_claims.json > /tmp/python-demo-dump.log

echo "\nAll checks passed ✅"

step "Cleaning up"
"${PYTHON_DEMO_DIR}/cleanup.sh"

echo "Test completed successfully"

