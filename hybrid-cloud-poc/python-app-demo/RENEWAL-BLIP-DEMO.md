# SVID Renewal Blip Demo Guide

This document provides a complete guide for demonstrating automatic SVID renewal with visible renewal blips. It includes setup steps for all components and explains what you'll see in the logs when SVID renewal occurs.

## Prerequisites

- SPIRE Server and Agent binaries built (or use the test_agents.sh script)
- Python 3 with `spiffe` library installed: `pip install spiffe`
- TPM Plugin Server (if using Unified-Identity features)
- Keylime Verifier and Agent (if using Unified-Identity features)

## Complete Setup Steps

### Step 1: Start SPIRE Server

```bash
# Navigate to project directory
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc

# Start SPIRE Server
SPIRE_SERVER="./spire/bin/spire-server"
SERVER_CONFIG="./spire/conf/server/server.conf"

# Or use the Python app demo config
SERVER_CONFIG="./python-app-demo/spire-server.conf"

# Start server in background
nohup "${SPIRE_SERVER}" run -config "${SERVER_CONFIG}" > /tmp/spire-server.log 2>&1 &
echo $! > /tmp/spire-server.pid

# Wait for server to be ready
sleep 3
"${SPIRE_SERVER}" healthcheck -socketPath /tmp/spire-server/private/api.sock
```

**Verify Server is Running:**
```bash
# Check server process
ps aux | grep spire-server

# Check server logs
tail -f /tmp/spire-server.log

# You should see: "SPIRE Server started"
```

### Step 2: Configure SPIRE Agent for SVID Renewal

**Important:** For the demo, we need to configure a short renewal interval (30 seconds minimum when Unified-Identity is enabled).

```bash
# Set renewal interval environment variable (30 seconds for demo)
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30

# Agent config file location
AGENT_CONFIG="./python-app-demo/spire-agent.conf"

# The test script will automatically configure this, or you can manually edit:
# In spire-agent.conf, set:
#   availability_target = "30s"
```

**Manual Configuration (if needed):**
```bash
# Edit the agent config file
vi ./python-app-demo/spire-agent.conf

# Ensure it contains:
# agent {
#     availability_target = "30s"  # 30 seconds for demo
#     experimental {
#         feature_flags = ["Unified-Identity"]  # Required for 30s minimum
#     }
#     ...
# }
```

### Step 3: Start SPIRE Agent

```bash
# Generate join token (required for agent attestation)
SPIRE_SERVER="./spire/bin/spire-server"
TOKEN_OUTPUT=$("${SPIRE_SERVER}" token generate \
    -socketPath /tmp/spire-server/private/api.sock 2>&1)
JOIN_TOKEN=$(echo "$TOKEN_OUTPUT" | grep "Token:" | awk '{print $2}')

echo "Join Token: ${JOIN_TOKEN:0:20}..."

# Export trust bundle
"${SPIRE_SERVER}" bundle show -format pem \
    -socketPath /tmp/spire-server/private/api.sock > /tmp/bundle.pem

# Start SPIRE Agent with renewal configuration
AGENT_CONFIG="./python-app-demo/spire-agent.conf"
SPIRE_AGENT="./spire/bin/spire-agent"

# Configure renewal interval if using environment variable
if [ -n "${SPIRE_AGENT_SVID_RENEWAL_INTERVAL:-}" ]; then
    # The test_agents.sh script handles this automatically
    # Or use the configure_spire_agent_svid_renewal function
    echo "Configuring SVID renewal interval: ${SPIRE_AGENT_SVID_RENEWAL_INTERVAL}s"
fi

# Start agent
export UNIFIED_IDENTITY_ENABLED=true
nohup "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" \
    -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
echo $! > /tmp/spire-agent.pid

# Wait for agent to complete attestation
sleep 5

# Verify agent is running and has SVID
if [ -S /tmp/spire-agent/public/api.sock ]; then
    echo "✓ SPIRE Agent is running and has SVID"
else
    echo "✗ SPIRE Agent failed to start or get SVID"
    tail -20 /tmp/spire-agent.log
    exit 1
fi
```

**Verify Agent SVID Renewal Configuration:**
```bash
# Check agent logs for renewal configuration
grep -i "availability_target" /tmp/spire-agent.log

# Check agent logs for renewal activity
tail -f /tmp/spire-agent.log | grep -i "renew\|svid"

# You should see renewal events every 30 seconds (or your configured interval)
```

### Step 4: Create Registration Entries for Python Apps

```bash
SPIRE_SERVER="./spire/bin/spire-server"

# Create entry for mTLS server app
"${SPIRE_SERVER}" entry create \
    -socketPath /tmp/spire-server/private/api.sock \
    -spiffeID spiffe://example.org/mtls-server \
    -parentID spiffe://example.org/agent \
    -selector unix:uid:$(id -u) \
    -selector unix:gid:$(id -g)

# Create entry for mTLS client app
"${SPIRE_SERVER}" entry create \
    -socketPath /tmp/spire-server/private/api.sock \
    -spiffeID spiffe://example.org/mtls-client \
    -parentID spiffe://example.org/agent \
    -selector unix:uid:$(id -u) \
    -selector unix:gid:$(id -g)

# Verify entries were created
"${SPIRE_SERVER}" entry show \
    -socketPath /tmp/spire-server/private/api.sock
```

### Step 5: Verify SPIRE Agent SVID Renewal is Active

```bash
# Monitor agent logs for renewal events
tail -f /tmp/spire-agent.log | grep -iE "renew|svid.*updated|availability_target"

# Or check renewal count
RENEWAL_COUNT=$(grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | wc -l)
echo "Agent SVID renewals detected: $RENEWAL_COUNT"

# Wait for first renewal (if using 30s interval, wait ~35 seconds)
echo "Waiting for agent SVID renewal (checking every 5 seconds)..."
for i in {1..10}; do
    sleep 5
    NEW_COUNT=$(grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | wc -l)
    if [ "$NEW_COUNT" -gt "$RENEWAL_COUNT" ]; then
        echo "✓ Agent SVID renewal detected! ($NEW_COUNT total)"
        break
    fi
    echo "  Waiting... ($i/10)"
done
```

### Step 6: Start Python mTLS Apps

**Option A: Using the Test Script (Recommended)**
```bash
cd python-app-demo

# Set renewal interval for demo
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30
export TEST_DURATION=120  # 2 minutes

# Run the test script
./test-mtls-renewal.sh
```

**Option B: Manual Start**
```bash
cd python-app-demo

# Terminal 1: Start server
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_PORT="8443"
export SERVER_LOG="/tmp/mtls-server-app.log"
python3 mtls-server-app.py

# Terminal 2: Start client
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="localhost"
export SERVER_PORT="8443"
export CLIENT_LOG="/tmp/mtls-client-app.log"
python3 mtls-client-app.py

# Terminal 3: Monitor logs
tail -f /tmp/mtls-server-app.log /tmp/mtls-client-app.log
```

### Step 7: Monitor for Renewal Blips

**Watch Server Logs:**
```bash
tail -f /tmp/mtls-server-app.log
```

**Watch Client Logs:**
```bash
tail -f /tmp/mtls-client-app.log
```

**Watch Agent Renewal:**
```bash
tail -f /tmp/spire-agent.log | grep -iE "renew|svid"
```

**Expected Timeline:**
- **0-30s**: Apps connect and communicate normally
- **~30s**: Agent SVID renews → Workload SVIDs renew → **RENEWAL BLIP** appears in logs
- **~30-35s**: Apps detect renewal, reconnect with new certificates
- **~60s**: Next renewal cycle (if using 30s interval)

## Quick Start (Using test_agents.sh)

For a complete automated setup:

```bash
# Set renewal interval for demo (30 seconds)
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30

# Run complete test with renewal monitoring
./test_agents.sh --test-renewal --no-pause

# This will:
# 1. Start SPIRE Server
# 2. Configure and start SPIRE Agent with 30s renewal
# 3. Create registration entries
# 4. Start Python mTLS apps
# 5. Monitor for renewal blips
```

## What You'll See

### 1. Initial Startup

**Server Log:**
```
╔════════════════════════════════════════════════════════════════╗
║  mTLS Server Starting with Automatic SVID Renewal              ║
╚════════════════════════════════════════════════════════════════╝
SPIRE Agent socket: /tmp/spire-agent/public/api.sock
Listening on port: 8443

Got initial SVID: spiffe://example.org/mtls-server
  Initial Certificate Serial: 1234567890
  Certificate Expires: 2025-11-25 04:00:00
  Monitoring for automatic SVID renewal...

╔════════════════════════════════════════════════════════════════╗
║  Server Ready - Waiting for mTLS Connections                   ║
╚════════════════════════════════════════════════════════════════╝
  Automatic SVID renewal is active
  Renewal blips will be logged when they occur
```

**Client Log:**
```
╔════════════════════════════════════════════════════════════════╗
║  mTLS Client Starting with Automatic SVID Renewal              ║
╚════════════════════════════════════════════════════════════════╝
SPIRE Agent socket: /tmp/spire-agent/public/api.sock
Server: localhost:8443

Got initial SVID: spiffe://example.org/mtls-client
  Initial Certificate Serial: 9876543210
  Certificate Expires: 2025-11-25 04:00:00
  Monitoring for automatic SVID renewal...

Connecting to localhost:8443...
✓ Connected to server
```

### 2. During Normal Operation

**Client sending messages:**
```
Server response: Echo: Hello from client - Message #1
Server response: Echo: Hello from client - Message #2
Server response: Echo: Hello from client - Message #3
```

### 3. When SVID Renewal Occurs (THE BLIP!)

**Server detects renewal:**
```
╔════════════════════════════════════════════════════════════════╗
║  🔄 SVID RENEWAL DETECTED - RENEWAL BLIP EVENT                  ║
╚════════════════════════════════════════════════════════════════╝
  Old Certificate Serial: 1234567890
  New Certificate Serial: 1234567891
  New Certificate Expires: 2025-11-25 04:00:30
  SPIFFE ID: spiffe://example.org/mtls-server
  ⚠️  RENEWAL BLIP: Existing connections may experience brief interruption
  ✓  New connections will automatically use renewed certificate
```

**Client detects renewal:**
```
╔════════════════════════════════════════════════════════════════╗
║  🔄 SVID RENEWAL DETECTED - RENEWAL BLIP EVENT                  ║
╚════════════════════════════════════════════════════════════════╝
  Old Certificate Serial: 9876543210
  New Certificate Serial: 9876543211
  New Certificate Expires: 2025-11-25 04:00:30
  SPIFFE ID: spiffe://example.org/mtls-client
  ⚠️  RENEWAL BLIP: Current connection will be re-established
  ✓  Reconnecting with renewed certificate...
```

### 4. The Reconnection (Blip Resolution)

**Client reconnecting:**
```
  🔧 Recreating TLS context with renewed SVID...
  ✓ TLS context recreated successfully
  🔌 Reconnecting to server with new certificate...
  ✓ Reconnected to server successfully (renewal blip resolved)
```

**Server accepting new connection:**
```
  ✓ New connection accepted (using renewed certificate)
Client 2 connected from ('127.0.0.1', 54321)
```

### 5. If Renewal Happens During Active Connection

**Client detects renewal mid-connection:**
```
  ⚠️  SVID renewed during active connection!
  ⚠️  RENEWAL BLIP: Current connection will close and reconnect
  🔄 Closing current connection to use renewed certificate...

  ⚠️  RENEWAL BLIP: TLS error detected (certificate renewal)
     Error: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed
     Connection will be re-established with renewed certificate...

  🔄 RENEWAL BLIP: Reconnecting due to certificate renewal...
     Reason: [Errno 104] Connection reset by peer
     This is expected behavior during SVID renewal

  ✓ Reconnected to server successfully (renewal blip resolved)
```

**Server handling the blip:**
```
  ⚠️  RENEWAL BLIP: TLS error detected (certificate renewal in progress)
     Error: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed
     Connection will be retried with renewed certificate...

Client 1 disconnected
  ✓ New connection accepted (using renewed certificate)
Client 2 connected from ('127.0.0.1', 54322)
```

## Key Points for Demo

1. **Automatic Detection**: Both apps automatically detect renewal by monitoring certificate serial numbers
2. **Visible Blip**: The renewal blip is clearly logged with visual separators
3. **Graceful Recovery**: Apps automatically reconnect with renewed certificates
4. **No Manual Intervention**: Everything happens automatically - no manual certificate updates needed
5. **Minimal Disruption**: The blip is brief (typically < 1 second)

## Running the Demo

### Method 1: Complete Automated Setup

```bash
# Set a short renewal interval for demo (30 seconds)
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30

# Run complete test (starts everything and monitors renewal)
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc
./test_agents.sh --test-renewal --no-pause
```

### Method 2: Step-by-Step Manual Setup

Follow Steps 1-7 above, then:

```bash
# In separate terminals, watch the logs:
# Terminal 1: Server logs
tail -f /tmp/mtls-server-app.log

# Terminal 2: Client logs  
tail -f /tmp/mtls-client-app.log

# Terminal 3: Agent renewal activity
tail -f /tmp/spire-agent.log | grep -iE "renew|svid"
```

### Method 3: Using Test Script Only

```bash
# Assumes SPIRE Server and Agent are already running
cd python-app-demo
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30
./test-mtls-renewal.sh
```

## Troubleshooting

### Agent SVID Not Renewing

**Check renewal configuration:**
```bash
# Verify availability_target is set in agent config
grep "availability_target" ./python-app-demo/spire-agent.conf

# Check agent logs for configuration
grep -i "availability_target" /tmp/spire-agent.log

# Verify Unified-Identity feature flag is enabled (required for 30s minimum)
grep -i "Unified-Identity" ./python-app-demo/spire-agent.conf
```

**Verify agent is receiving renewals:**
```bash
# Monitor agent logs for renewal events
tail -f /tmp/spire-agent.log | grep -iE "renew|svid.*updated"

# Check renewal count
grep -iE "renew|SVID.*updated|SVID.*refreshed" /tmp/spire-agent.log | wc -l
```

### Python Apps Not Detecting Renewal

**Check SPIRE Agent socket:**
```bash
# Verify socket exists
ls -l /tmp/spire-agent/public/api.sock

# Check socket permissions
stat /tmp/spire-agent/public/api.sock
```

**Verify registration entries:**
```bash
# List all entries
./spire/bin/spire-server entry show \
    -socketPath /tmp/spire-server/private/api.sock

# Should see entries for:
# - spiffe://example.org/mtls-server
# - spiffe://example.org/mtls-client
```

**Check Python app logs:**
```bash
# Look for SVID fetch errors
grep -i "error\|failed" /tmp/mtls-server-app.log
grep -i "error\|failed" /tmp/mtls-client-app.log
```

### Renewal Interval Too Long

**For faster demos, use shorter intervals:**
```bash
# Minimum is 30 seconds (when Unified-Identity enabled)
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30

# Reconfigure agent (requires restart)
# Edit spire-agent.conf and set: availability_target = "30s"
# Then restart agent
```

## What Makes This a Good Demo

- **Visual Clarity**: Boxed sections make renewal events easy to spot
- **Detailed Information**: Shows old/new certificate serials, expiry times
- **Real-time**: Logs appear as renewal happens
- **Educational**: Explains what's happening at each step
- **Realistic**: Shows actual TLS errors and reconnections that occur

The logs clearly demonstrate that:
1. SVID renewal is automatic (no manual steps)
2. The blip is brief and expected
3. Apps recover automatically
4. New connections use renewed certificates seamlessly

## Verification Checklist

Before starting the demo, verify:

- [ ] SPIRE Server is running (`ps aux | grep spire-server`)
- [ ] SPIRE Agent is running (`ps aux | grep spire-agent`)
- [ ] Agent socket exists (`ls -l /tmp/spire-agent/public/api.sock`)
- [ ] Agent has SVID (check logs for "Node attestation was successful")
- [ ] Renewal interval is configured (`grep availability_target` in agent config)
- [ ] Registration entries exist for both apps (`spire-server entry show`)
- [ ] Python dependencies installed (`pip list | grep spiffe`)

## Expected Demo Flow

1. **Setup Phase (Steps 1-4)**: Start SPIRE components and configure renewal
2. **Verification Phase (Step 5)**: Confirm agent SVID renewal is active
3. **Demo Phase (Steps 6-7)**: Start Python apps and watch for renewal blips
4. **Observation**: Within 30-60 seconds, you'll see:
   - Agent SVID renewal in agent logs
   - Renewal blip events in Python app logs
   - Automatic reconnection with new certificates
   - Continued communication after renewal

## Summary

This demo shows:
- ✅ **Automatic SVID Renewal**: SPIRE Agent automatically renews its SVID
- ✅ **Workload SVID Inheritance**: Python apps automatically get renewed SVIDs
- ✅ **Visible Blips**: Logs clearly show when renewal occurs
- ✅ **Graceful Recovery**: Apps automatically reconnect with new certificates
- ✅ **Zero Downtime**: Brief blips don't disrupt service (new connections work immediately)

The renewal blip is a natural part of certificate rotation and demonstrates that the system handles it automatically without manual intervention.

