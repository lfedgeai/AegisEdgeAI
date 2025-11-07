#!/bin/bash
# Unified-Identity - Phase 1: Automated end-to-end test for Python demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_DEMO_DIR="${PROJECT_ROOT}/python-app-demo"

SERVER_CONFIG="${SERVER_CONFIG:-${PYTHON_DEMO_DIR}/spire-server.conf}"
AGENT_CONFIG="${AGENT_CONFIG:-${PYTHON_DEMO_DIR}/spire-agent.conf}"
AGENT_SPIFFE_ID="${AGENT_SPIFFE_ID:-spiffe://example.org/host/python-demo-agent}"

fail() {
    echo "✗ $1" >&2
    exit 1
}

step() {
    echo "\n=== $1 ==="
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
QUIET=1 "${PYTHON_DEMO_DIR}/cleanup.sh" || true

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
QUIET=1 SERVER_CONFIG="$SERVER_CONFIG" AGENT_CONFIG="$AGENT_CONFIG" AGENT_SPIFFE_ID="$AGENT_SPIFFE_ID" \
    "${PROJECT_ROOT}/scripts/start-unified-identity.sh"

step "Verifying agent bootstrap AttestedClaims"
wait_for_log /tmp/spire-server.log "Added AttestedClaims to response" "Server recorded AttestedClaims for host/python-demo-agent" 60
grep -qi "host/python-demo-agent" /tmp/spire-server.log || fail "Server log missing host/python-demo-agent entry"
wait_for_log /tmp/keylime-stub.log "Returning stubbed AttestedClaims response" "Keylime stub returned claims during bootstrap" 60
wait_for_log /tmp/spire-agent.log "Creating X509-SVID" "Agent created host/python-demo-agent SVID" 60

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

step "Verifying Unified-Identity logs after SVID fetch"
wait_for_log /tmp/spire-agent.log "Fetched X.509 SVID" "Agent log contains workload SVID fetch"
wait_for_log /tmp/spire-agent.log "python-app" "Agent log references python app"
wait_for_log /tmp/spire-server.log "Policy evaluation passed" "Server log indicates policy success" 60
wait_for_log /tmp/keylime-stub.log "Returning stubbed AttestedClaims response" "Keylime stub returned claims" 60

step "Dumping SVID for inspection"
"${PROJECT_ROOT}/scripts/dump-svid" -cert /tmp/svid-dump/svid.pem -attested /tmp/svid-dump/attested_claims.json > /tmp/python-demo-dump.log

echo "\nAll checks passed ✅"

step "Cleaning up"
QUIET=1 "${PYTHON_DEMO_DIR}/cleanup.sh"

echo "Test completed successfully"

