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

# Watch all service logs in separate tmux panes
# Usage: ./scripts/watch-all-logs.sh
#
# This creates a tmux session with 3 panes:
# - Top: Envoy logs
# - Middle: mTLS server logs
# - Bottom: Mobile sensor service logs

SESSION_NAME="demo-logs"

# Check if tmux is available
if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is not installed"
    echo "Install it with: sudo apt-get install tmux"
    echo ""
    echo "Alternatively, run the individual watch scripts in separate terminals:"
    echo "  Terminal 1: ./scripts/watch-envoy-logs.sh"
    echo "  Terminal 2: ./scripts/watch-mtls-server-logs.sh"
    echo "  Terminal 3: ./scripts/watch-mobile-sensor-logs.sh"
    exit 1
fi

# Kill existing session if it exists
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# Create new tmux session with 3 panes
tmux new-session -d -s "$SESSION_NAME" -x 120 -y 40

# Split into 3 panes (horizontal splits)
tmux split-window -v -t "$SESSION_NAME"
tmux split-window -v -t "$SESSION_NAME"

# Set pane titles and run watch commands
tmux send-keys -t "$SESSION_NAME:0.0" "echo '=== Envoy Logs ===' && tail -f /opt/envoy/logs/envoy.log" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "echo '=== mTLS Server Logs ===' && tail -f /tmp/mtls-server.log" C-m
tmux send-keys -t "$SESSION_NAME:0.2" "echo '=== Mobile Sensor Service Logs ===' && tail -f /tmp/mobile-sensor.log" C-m

# Select the first pane
tmux select-pane -t "$SESSION_NAME:0.0"

# Attach to session
echo "Created tmux session '$SESSION_NAME' with 3 panes"
echo ""
echo "To attach: tmux attach -t $SESSION_NAME"
echo "To detach: Press Ctrl+B then D"
echo "To kill: tmux kill-session -t $SESSION_NAME"
echo ""
echo "Attaching now..."
sleep 1
tmux attach -t "$SESSION_NAME"
