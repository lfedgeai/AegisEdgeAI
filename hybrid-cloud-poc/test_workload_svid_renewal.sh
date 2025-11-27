#!/bin/bash
#
# Workload SVID renewal demo (Python mTLS client/server)
# Requires test_complete.sh to have been executed so that SPIRE, Keylime, etc.
# are already running in the background.
#
# Usage:
#   ./test_workload_svid_renewal.sh                    # Run in background (default)
#   ./test_workload_svid_renewal.sh --foreground       # Run in foreground
#   ./test_workload_svid_renewal.sh -f                 # Run in foreground (short form)
#   WORKLOAD_RENEWAL_MONITOR_SECONDS=3600 ./test_workload_svid_renewal.sh  # 1 hour test in background

set -euo pipefail

# Parse arguments - default is background mode
RUN_IN_BACKGROUND=true
if [[ "${1:-}" == "--foreground" ]] || [[ "${1:-}" == "-f" ]]; then
    RUN_IN_BACKGROUND=false
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_APPS_DIR="${PROJECT_DIR}/python-app-demo"
SERVER_APP="${PYTHON_APPS_DIR}/mtls-server-app.py"
CLIENT_APP="${PYTHON_APPS_DIR}/mtls-client-app.py"
SERVER_LOG="/tmp/mtls-server-app.log"
CLIENT_LOG="/tmp/mtls-client-app.log"
DEFAULT_SERVER_PORT="${PYTHON_MTLS_SERVER_PORT:-9443}"
SPIRE_SERVER_BIN="${PROJECT_DIR}/spire/bin/spire-server"

export UNIFIED_IDENTITY_ENABLED="${UNIFIED_IDENTITY_ENABLED:-true}"
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL="${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-30}"

log() {
    printf '%s %s\n' "[workload-renewal]" "$*"
}

abort() {
    log "ERROR: $*"
    exit 1
}

require_file() {
    local f="$1"
    [ -f "$f" ] || abort "Missing file: $f"
}

ensure_prereqs() {
    require_file "$SPIRE_SERVER_BIN"
    [ -S /tmp/spire-agent/public/api.sock ] || abort "SPIRE Agent socket not found. Run ./test_complete.sh first."
    "${SPIRE_SERVER_BIN}" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1 || \
        abort "SPIRE Server healthcheck failed. Make sure ./test_complete.sh is running services."
    require_file "$SERVER_APP"
    require_file "$CLIENT_APP"
    python3 - <<'PY' >/dev/null || abort "Python spiffe library not installed (pip install spiffe)"
from spiffe.workloadapi.x509_source import X509Source  # noqa: F401
PY
}

find_available_port() {
    local port="${1:-9443}"
    local max_attempts=20
    for _ in $(seq 1 "$max_attempts"); do
        if ! ss -tln 2>/dev/null | grep -q ":$port "; then
            echo "$port"
            return
        fi
        port=$((port + 1))
    done
    abort "Unable to find free port starting at $1"
}

ensure_registration_entries() {
    local agent_id
    agent_id=$("${SPIRE_SERVER_BIN}" agent list -socketPath /tmp/spire-server/private/api.sock 2>/dev/null | \
        awk -F': +' '/SPIFFE ID/{print $2; exit}')
    [ -n "$agent_id" ] || abort "Could not determine agent SPIFFE ID"

    local ensure_entry
    ensure_entry() {
        local spiffe_id="$1"
        local existing
        existing=$("${SPIRE_SERVER_BIN}" entry show -socketPath /tmp/spire-server/private/api.sock -spiffeID "$spiffe_id" 2>/dev/null | \
            awk -F': +' '/Entry ID/{print $2; exit}')
        if [ -n "$existing" ]; then
            "${SPIRE_SERVER_BIN}" entry delete -entryID "$existing" -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1 || true
            sleep 0.5
        fi
        if ! "${SPIRE_SERVER_BIN}" entry create \
            -parentID "$agent_id" \
            -spiffeID "$spiffe_id" \
            -selector "unix:uid:$(id -u)" \
            -x509SVIDTTL 60 \
            -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
            abort "Failed to create entry for $spiffe_id"
        fi
    }

    ensure_entry "spiffe://example.org/python-app"
    ensure_entry "spiffe://example.org/mtls-server"
    ensure_entry "spiffe://example.org/mtls-client"
    log "Registration entries ensured with 60s TTL"
}

cleanup_python_apps() {
    pkill -9 -f "mtls-server-app.py" >/dev/null 2>&1 || true
    pkill -9 -f "mtls-client-app.py" >/dev/null 2>&1 || true
    [ -f /tmp/mtls-server-app.pid ] && kill -9 "$(cat /tmp/mtls-server-app.pid)" >/dev/null 2>&1 || true
    [ -f /tmp/mtls-client-app.pid ] && kill -9 "$(cat /tmp/mtls-client-app.pid)" >/dev/null 2>&1 || true
    rm -f "$SERVER_LOG" "$CLIENT_LOG" /tmp/mtls-server-app.pid /tmp/mtls-client-app.pid || true
}

sanitize_count() {
    local val="${1:-0}"
    val="${val//[^0-9]/}"
    if [ -z "$val" ]; then
        echo 0
    else
        echo "$val"
    fi
}

cleanup_existing_instances() {
    cleanup_python_apps
    local port
    for port in "$DEFAULT_SERVER_PORT" $((DEFAULT_SERVER_PORT + 1)) $((DEFAULT_SERVER_PORT + 2)) $((DEFAULT_SERVER_PORT + 3)) $((DEFAULT_SERVER_PORT + 4)); do
        if command -v lsof >/dev/null 2>&1; then
            lsof -ti:$port 2>/dev/null | xargs kill -9 2>/dev/null || true
        fi
        if command -v fuser >/dev/null 2>&1; then
            fuser -k "${port}/tcp" >/dev/null 2>&1 || true
        fi
    done
}

start_server() {
    SERVER_PORT=$(find_available_port "$DEFAULT_SERVER_PORT")
    log "Starting mTLS server on port $SERVER_PORT ..."
    nohup python3 "$SERVER_APP" \
        --socket-path /tmp/spire-agent/public/api.sock \
        --port "$SERVER_PORT" \
        --log-file "$SERVER_LOG" > "$SERVER_LOG" 2>&1 &
    SERVER_PID=$!
    disown $SERVER_PID 2>/dev/null || true
    echo "$SERVER_PID" > /tmp/mtls-server-app.pid
    sleep 3
    kill -0 "$SERVER_PID" 2>/dev/null || (tail -20 "$SERVER_LOG"; abort "mTLS server failed to start")
    log "Server PID: $SERVER_PID (log: $SERVER_LOG)"
}

start_client() {
    log "Starting mTLS client ..."
    nohup python3 "$CLIENT_APP" \
        --socket-path /tmp/spire-agent/public/api.sock \
        --server-host localhost \
        --server-port "$SERVER_PORT" \
        --log-file "$CLIENT_LOG" > "$CLIENT_LOG" 2>&1 &
    CLIENT_PID=$!
    disown $CLIENT_PID 2>/dev/null || true
    echo "$CLIENT_PID" > /tmp/mtls-client-app.pid
    sleep 2
    kill -0 "$CLIENT_PID" 2>/dev/null || (tail -20 "$CLIENT_LOG"; abort "mTLS client failed to start")
    log "Client PID: $CLIENT_PID (log: $CLIENT_LOG)"
}

monitor_loop() {
    local duration="${1:-180}"
    log "Monitoring renewals for ${duration}s (Ctrl+C to exit early)..."
    local start end server_count client_count blips
    start=$(date +%s)
    end=$((start + duration))
    server_count=0
    client_count=0
    blips=0

    while [ "$(date +%s)" -lt "$end" ]; do
        sleep 2
        if [ -f "$SERVER_LOG" ]; then
            local new
            new=$(grep -c "SVID RENEWAL DETECTED" "$SERVER_LOG" 2>/dev/null || printf '0')
            new=$(sanitize_count "$new")
            if (( new > server_count )); then
                server_count=$new
                log "Server renewal detected (total $server_count)"
            fi
        fi
        if [ -f "$CLIENT_LOG" ]; then
            local new
            new=$(grep -c "SVID RENEWAL DETECTED" "$CLIENT_LOG" 2>/dev/null || printf '0')
            new=$(sanitize_count "$new")
            if (( new > client_count )); then
                client_count=$new
                log "Client renewal detected (total $client_count)"
            fi
            local blip_count
            blip_count=$(grep -ci "RENEWAL BLIP" "$CLIENT_LOG" 2>/dev/null || printf '0')
            blip_count=$(sanitize_count "$blip_count")
            if (( blip_count > blips )); then
                blips=$blip_count
                log "Renewal blip observed (total $blips)"
            fi
        fi
        kill -0 "$SERVER_PID" 2>/dev/null || abort "Server process exited unexpectedly"
        kill -0 "$CLIENT_PID" 2>/dev/null || abort "Client process exited unexpectedly"
    done

    echo ""
    log "Summary:"
    log "  Agent renewals (check /tmp/spire-agent.log)"
    log "  Server renewals: $server_count"
    log "  Client renewals: $client_count"
    log "  Renewal blips:   $blips"
    echo ""
    log "Python apps continue running. Tail logs to observe live activity:"
    log "  tail -f /tmp/spire-agent.log"
    log "  tail -f $SERVER_LOG"
    log "  tail -f $CLIENT_LOG"
}

trap 'log "Stopping Python apps..."; cleanup_python_apps' INT TERM

main() {
    log "Workload SVID renewal demo starting..."
    ensure_prereqs
    ensure_registration_entries
    log "Cleaning up any existing Python demo instances..."
    cleanup_existing_instances
    start_server
    start_client
    
    if [ "$RUN_IN_BACKGROUND" = true ]; then
        log "Running in background mode..."
        log "Monitoring for ${WORKLOAD_RENEWAL_MONITOR_SECONDS:-180} seconds"
        log "Server PID: $SERVER_PID (log: $SERVER_LOG)"
        log "Client PID: $CLIENT_PID (log: $CLIENT_LOG)"
        log ""
        log "To monitor progress:"
        log "  tail -f /tmp/test_workload_svid_renewal.log"
        log "  tail -f $SERVER_LOG"
        log "  tail -f $CLIENT_LOG"
        log ""
        log "To stop:"
        log "  pkill -f 'mtls-(server|client)-app.py'"
        log "  or: kill $SERVER_PID $CLIENT_PID"
        log ""
        
        # Run monitor loop in background and redirect all output to log file
        (
            monitor_loop "${WORKLOAD_RENEWAL_MONITOR_SECONDS:-180}"
        ) >> /tmp/test_workload_svid_renewal.log 2>&1 &
        MONITOR_PID=$!
        disown $MONITOR_PID 2>/dev/null || true
        echo $MONITOR_PID > /tmp/test_workload_svid_renewal.pid
        echo $SERVER_PID > /tmp/mtls-server-app.pid
        echo $CLIENT_PID > /tmp/mtls-client-app.pid
        
        log "Background monitoring started (PID: $MONITOR_PID)"
        log "All processes running in background. Script exiting - you can safely disconnect."
        log "Check /tmp/test_workload_svid_renewal.log for monitoring output."
    else
        log "Running in foreground mode..."
        monitor_loop "${WORKLOAD_RENEWAL_MONITOR_SECONDS:-180}"
    fi
}

main "$@"

