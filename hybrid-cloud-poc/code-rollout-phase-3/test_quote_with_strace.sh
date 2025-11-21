#!/usr/bin/env bash
# Test quote endpoint with strace tracing
# This script attaches strace to the agent and makes a quote request

set -euo pipefail

AGENT_PID=$(cat /tmp/rust-keylime-agent-debug.pid 2>/dev/null || lsof -ti :9002 | head -1)

if [ -z "$AGENT_PID" ]; then
    echo "Error: Agent not running. Start it with: bash start_agent_debug.sh"
    exit 1
fi

echo "Agent PID: $AGENT_PID"
echo ""

CLIENT_CERT="/tmp/keylime-agent/cv_ca/client-cert.crt"
CLIENT_KEY="/tmp/keylime-agent/cv_ca/client-private.pem"
CA_CERT="/tmp/keylime-agent/cv_ca/cacert.crt"
NONCE=$(uuidgen | tr -d '-')
STRACE_LOG="/tmp/agent-strace-$$.log"

echo "=== Starting strace on agent ==="
echo "Strace log: $STRACE_LOG"
echo ""

# Start strace in background
# Trace system calls that might be relevant for TPM operations
sudo strace -f -e trace=read,write,poll,select,ioctl,epoll_wait,epoll_pwait,openat,close,futex \
    -e trace=file -e trace=desc \
    -p $AGENT_PID -o "$STRACE_LOG" 2>&1 &
STRACE_PID=$!

echo "Strace started (PID: $STRACE_PID)"
echo "Waiting 2 seconds for strace to attach..."
sleep 2

echo ""
echo "=== Making quote request ==="
echo "Nonce: $NONCE"
echo ""

# Make the curl request
# Use --insecure to bypass hostname verification (cert is self-signed for testing)
# or use 127.0.0.1 instead of localhost
timeout 12 curl --max-time 10 -v \
    --cert "$CLIENT_CERT" \
    --key "$CLIENT_KEY" \
    --cacert "$CA_CERT" \
    --insecure \
    "https://127.0.0.1:9002/v2.2/quotes/identity?nonce=$NONCE" \
    2>&1 | tee /tmp/curl-quote-output.log

CURL_EXIT=$?

echo ""
echo "=== Stopping strace ==="
sleep 1
kill $STRACE_PID 2>/dev/null || true
wait $STRACE_PID 2>/dev/null || true

echo ""
echo "=== Strace Summary ==="
echo "Strace log: $STRACE_LOG"
echo "Curl exit code: $CURL_EXIT"
echo ""

if [ -f "$STRACE_LOG" ]; then
    echo "TPM-related operations (filtered):"
    tail -200 "$STRACE_LOG" | grep -E "(/dev/tpm|tpmrm|ioctl.*0x|read.*=.*-1|write.*=.*-1|poll.*=.*0)" | tail -40 || echo "No obvious TPM operations found"
    echo ""
    echo "Last blocking operations (poll/select/epoll):"
    tail -200 "$STRACE_LOG" | grep -E "(poll|select|epoll_wait|epoll_pwait|futex)" | tail -20 || echo "No blocking operations found"
    echo ""
    echo "Last 30 lines of strace output:"
    tail -30 "$STRACE_LOG"
    echo ""
    echo "Full strace log available at: $STRACE_LOG"
    echo "To search for specific patterns:"
    echo "  grep -E 'tpm|TPM|Esys' $STRACE_LOG"
    echo "  grep -E 'ioctl.*0x' $STRACE_LOG"
fi

echo ""
echo "=== Agent log (last 20 lines) ==="
tail -20 /tmp/rust-keylime-agent-debug.log

