#!/bin/bash
# Unified-Identity - Phase 1: Wrapper script retained for backwards compatibility

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVER_CONFIG="${SERVER_CONFIG:-${SCRIPT_DIR}/spire-server.conf}"
AGENT_CONFIG="${AGENT_CONFIG:-${SCRIPT_DIR}/spire-agent.conf}"

SERVER_CONFIG="$SERVER_CONFIG" AGENT_CONFIG="$AGENT_CONFIG" "${PROJECT_ROOT}/scripts/start-unified-identity.sh" "$@"

