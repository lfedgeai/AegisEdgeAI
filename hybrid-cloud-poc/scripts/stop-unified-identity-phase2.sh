#!/bin/bash
# Unified-Identity - Phase 1 & Phase 2: Shared teardown script for SPIRE Server, Agent, and Real Keylime Verifier

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Unified-Identity - Phase 1 & Phase 2: Stopping SPIRE stack and Keylime Verifier"
echo ""

# Stop SPIRE Server
if [ -f /tmp/spire-server.pid ]; then
    SERVER_PID=$(cat /tmp/spire-server.pid)
    if ps -p $SERVER_PID > /dev/null 2>&1; then
        echo "Stopping SPIRE Server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
        sleep 2
        if ps -p $SERVER_PID > /dev/null 2>&1; then
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
        echo "✓ SPIRE Server stopped"
    fi
    rm -f /tmp/spire-server.pid
fi

# Stop SPIRE Agent
if [ -f /tmp/spire-agent.pid ]; then
    AGENT_PID=$(cat /tmp/spire-agent.pid)
    if ps -p $AGENT_PID > /dev/null 2>&1; then
        echo "Stopping SPIRE Agent (PID: $AGENT_PID)..."
        kill $AGENT_PID 2>/dev/null || true
        sleep 2
        if ps -p $AGENT_PID > /dev/null 2>&1; then
            kill -9 $AGENT_PID 2>/dev/null || true
        fi
        echo "✓ SPIRE Agent stopped"
    fi
    rm -f /tmp/spire-agent.pid
fi

# Stop Keylime Verifier
if [ -f /tmp/keylime-verifier.pid ]; then
    KEYLIME_PID=$(cat /tmp/keylime-verifier.pid)
    if ps -p $KEYLIME_PID > /dev/null 2>&1; then
        echo "Stopping Keylime Verifier (PID: $KEYLIME_PID)..."
        kill $KEYLIME_PID 2>/dev/null || true
        sleep 2
        if ps -p $KEYLIME_PID > /dev/null 2>&1; then
            kill -9 $KEYLIME_PID 2>/dev/null || true
        fi
        echo "✓ Keylime Verifier stopped"
    fi
    rm -f /tmp/keylime-verifier.pid
fi

# Kill any remaining processes
pkill -f "spire-server" >/dev/null 2>&1 || true
pkill -f "spire-agent" >/dev/null 2>&1 || true
pkill -f "keylime_verifier" >/dev/null 2>&1 || true
pkill -f "keylime_verifier_tornado" >/dev/null 2>&1 || true

# Wait for processes to fully terminate
echo "Waiting for processes to terminate..."
for i in {1..5}; do
    if ! pgrep -f "spire-server|spire-agent|keylime_verifier" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Force kill any stubborn processes
if pgrep -f "spire-server|spire-agent|keylime_verifier" >/dev/null 2>&1; then
    echo "Force killing remaining processes..."
    pkill -9 -f "spire-server" >/dev/null 2>&1 || true
    pkill -9 -f "spire-agent" >/dev/null 2>&1 || true
    pkill -9 -f "keylime_verifier" >/dev/null 2>&1 || true
fi

echo ""
echo "✓ All processes stopped"
echo ""
echo "Log files are preserved:"
echo "  SPIRE Server:  /tmp/spire-server.log"
echo "  SPIRE Agent:   /tmp/spire-agent.log"
echo "  Keylime Verifier: /tmp/keylime-verifier.log"

