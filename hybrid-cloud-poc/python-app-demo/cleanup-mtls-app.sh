#!/bin/bash

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Cleanup script for mTLS server and client processes
# Handles background processes, PID files, and port cleanup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
SERVER_PORT="${SERVER_PORT:-9443}"
SERVER_PID_FILE="${SERVER_PID_FILE:-/tmp/mtls-server-app.pid}"
CLIENT_PID_FILE="${CLIENT_PID_FILE:-/tmp/mtls-client-app.pid}"
SERVER_LOG="${SERVER_LOG:-/tmp/mtls-server-app.log}"
CLIENT_LOG="${CLIENT_LOG:-/tmp/mtls-client-app.log}"

# Option to clean log files (set CLEAN_LOGS=0 to disable)
CLEAN_LOGS="${CLEAN_LOGS:-1}"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Cleaning up mTLS Server and Client processes${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

KILLED_COUNT=0

# Function to kill a process by PID
kill_by_pid() {
    local pid=$1
    local name=$2
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo -e "  ${YELLOW}Killing $name (PID: $pid)...${NC}"
        kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
        KILLED_COUNT=$((KILLED_COUNT + 1))
        sleep 0.5
        # Verify it's dead
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  ${YELLOW}Force killing $name (PID: $pid)...${NC}"
            kill -9 "$pid" 2>/dev/null || true
        fi
        echo -e "  ${GREEN}✓ Killed $name${NC}"
    fi
}

# Step 1: Kill processes using PID files
echo -e "${CYAN}Step 1: Checking PID files...${NC}"
if [ -f "$SERVER_PID_FILE" ]; then
    SERVER_PID=$(cat "$SERVER_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$SERVER_PID" ]; then
        kill_by_pid "$SERVER_PID" "mTLS Server"
    fi
    rm -f "$SERVER_PID_FILE"
    echo -e "  ${GREEN}✓ Removed server PID file${NC}"
fi

if [ -f "$CLIENT_PID_FILE" ]; then
    CLIENT_PID=$(cat "$CLIENT_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$CLIENT_PID" ]; then
        kill_by_pid "$CLIENT_PID" "mTLS Client"
    fi
    rm -f "$CLIENT_PID_FILE"
    echo -e "  ${GREEN}✓ Removed client PID file${NC}"
fi

# Step 2: Kill by process name (catches background processes, nohup, etc.)
echo ""
echo -e "${CYAN}Step 2: Killing processes by name...${NC}"

# Find server processes
SERVER_PROCS=$(pgrep -f "mtls-server-app.py" 2>/dev/null || true)
if [ -n "$SERVER_PROCS" ]; then
    for pid in $SERVER_PROCS; do
        kill_by_pid "$pid" "mTLS Server (found by name)"
    done
else
    echo -e "  ${GREEN}✓ No server processes found${NC}"
fi

# Find client processes
CLIENT_PROCS=$(pgrep -f "mtls-client-app.py" 2>/dev/null || true)
if [ -n "$CLIENT_PROCS" ]; then
    for pid in $CLIENT_PROCS; do
        kill_by_pid "$pid" "mTLS Client (found by name)"
    done
else
    echo -e "  ${GREEN}✓ No client processes found${NC}"
fi

# Alternative: Use pkill (more aggressive, catches all variants)
pkill -f "mtls-server-app.py" >/dev/null 2>&1 && {
    echo -e "  ${GREEN}✓ Killed additional server processes via pkill${NC}"
    KILLED_COUNT=$((KILLED_COUNT + 1))
} || true

pkill -f "mtls-client-app.py" >/dev/null 2>&1 && {
    echo -e "  ${GREEN}✓ Killed additional client processes via pkill${NC}"
    KILLED_COUNT=$((KILLED_COUNT + 1))
} || true

# Step 3: Kill processes using the server port
echo ""
echo -e "${CYAN}Step 3: Checking port $SERVER_PORT...${NC}"
if command -v lsof >/dev/null 2>&1; then
    PORT_PIDS=$(lsof -ti:$SERVER_PORT 2>/dev/null || true)
    if [ -n "$PORT_PIDS" ]; then
        for pid in $PORT_PIDS; do
            # Check if it's actually our process
            if ps -p "$pid" -o command= 2>/dev/null | grep -q "mtls"; then
                kill_by_pid "$pid" "Process on port $SERVER_PORT"
            else
                echo -e "  ${YELLOW}⚠ Port $SERVER_PORT is in use by PID $pid (not an mTLS process)${NC}"
            fi
        done
    else
        echo -e "  ${GREEN}✓ Port $SERVER_PORT is free${NC}"
    fi
elif command -v fuser >/dev/null 2>&1; then
    if fuser "$SERVER_PORT/tcp" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Killing process on port $SERVER_PORT...${NC}"
        fuser -k "${SERVER_PORT}/tcp" >/dev/null 2>&1 || true
        echo -e "  ${GREEN}✓ Port $SERVER_PORT cleared${NC}"
        KILLED_COUNT=$((KILLED_COUNT + 1))
    else
        echo -e "  ${GREEN}✓ Port $SERVER_PORT is free${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ Cannot check port (lsof/fuser not available)${NC}"
fi

# Step 4: Verify cleanup
echo ""
echo -e "${CYAN}Step 4: Verifying cleanup...${NC}"
REMAINING_SERVER=$(pgrep -f "mtls-server-app.py" 2>/dev/null || true)
REMAINING_CLIENT=$(pgrep -f "mtls-client-app.py" 2>/dev/null || true)

if [ -z "$REMAINING_SERVER" ] && [ -z "$REMAINING_CLIENT" ]; then
    echo -e "  ${GREEN}✓ All mTLS processes terminated${NC}"
else
    echo -e "  ${RED}⚠ Warning: Some processes may still be running:${NC}"
    [ -n "$REMAINING_SERVER" ] && echo -e "    ${YELLOW}Server PIDs: $REMAINING_SERVER${NC}"
    [ -n "$REMAINING_CLIENT" ] && echo -e "    ${YELLOW}Client PIDs: $REMAINING_CLIENT${NC}"
    echo -e "  ${YELLOW}Attempting force kill...${NC}"
    pkill -9 -f "mtls-server-app.py" 2>/dev/null || true
    pkill -9 -f "mtls-client-app.py" 2>/dev/null || true
    sleep 1
fi

# Step 5: Clean up log files (default behavior, set CLEAN_LOGS=0 to skip)
if [ "$CLEAN_LOGS" = "1" ]; then
    echo ""
    echo -e "${CYAN}Step 5: Cleaning up log files...${NC}"
    [ -f "$SERVER_LOG" ] && rm -f "$SERVER_LOG" && echo -e "  ${GREEN}✓ Removed $SERVER_LOG${NC}"
    [ -f "$CLIENT_LOG" ] && rm -f "$CLIENT_LOG" && echo -e "  ${GREEN}✓ Removed $CLIENT_LOG${NC}"
fi

# Summary
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $KILLED_COUNT -gt 0 ] || [ -z "$REMAINING_SERVER" ] && [ -z "$REMAINING_CLIENT" ]; then
    echo -e "${GREEN}✓ Cleanup complete!${NC}"
    if [ $KILLED_COUNT -gt 0 ]; then
        echo -e "  ${GREEN}Terminated $KILLED_COUNT process(es)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Cleanup attempted. Please verify manually if needed.${NC}"
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
