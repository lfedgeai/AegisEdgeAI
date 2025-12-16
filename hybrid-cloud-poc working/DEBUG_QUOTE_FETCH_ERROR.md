# Debug: Quote Fetch Error - Agent Retrieval Failed

## The Error

```
keylime verification failed: keylime verifier returned status 400: 
{"code": 400, "status": "missing required field: data.quote (agent retrieval failed)", "results": {}}
```

## What This Means

The Keylime Verifier tried to fetch a TPM quote from the rust-keylime agent but failed. This could be because:

1. ❌ Agent is not running (zombie/crashed)
2. ❌ Agent is not responding (hung)
3. ❌ Network/connection issue
4. ❌ SSL/TLS certificate mismatch
5. ❌ Timeout too short

## Diagnostic Commands

Run these on your Linux machine to diagnose:

### 1. Check if Agent is Running

```bash
# Check process
ps aux | grep keylime_agent
# Should show running process

# Check if it's responding
curl -k https://localhost:9002/v2.2/agent/version
# Should return version info

# If connection refused, agent is dead
```

### 2. Check Agent Logs

```bash
tail -100 /tmp/rust-keylime-agent.log

# Look for:
# - "Listening on https://..." (agent started)
# - "Switching from tpmrm0 to tpm0" (TPM access)
# - Any ERROR messages
# - Does log just stop? (agent crashed/exited)
```

### 3. Check Verifier Logs

```bash
tail -100 /tmp/keylime-verifier.log | grep -A 5 "quote"

# Look for:
# - "Requesting quote from agent"
# - HTTP error codes (599, 400, etc.)
# - SSL/TLS errors
# - Timeout errors
```

### 4. Check for tpm2-abrmd Conflict

```bash
# Should show NOTHING
ps aux | grep tpm2-abrmd

# If it's running, kill it:
sudo pkill -9 tpm2-abrmd
```

### 5. Test Agent Quote Endpoint Directly

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
./test-agent-quote-endpoint.sh

# Should show: ✅ SUCCESS
# If fails, shows what's wrong
```

## Common Causes & Fixes

### Cause 1: Agent Became Zombie (Most Likely)

**Symptoms:**
- `ps aux | grep keylime_agent` shows process
- `curl` to agent fails with "Connection refused"
- Agent logs stop after "Switching from tpmrm0 to tpm0"

**Fix:**
```bash
# Check if tpm2-abrmd is running (conflict)
ps aux | grep tpm2-abrmd

# If running, kill it
sudo pkill -9 tpm2-abrmd

# Restart agent
pkill keylime_agent
sleep 2

# Start agent manually to watch logs
cd ~/dhanush/hybrid-cloud-poc-backup
export KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_KEYLIME_DIR="/tmp/keylime-agent"
export USE_TPM2_QUOTE_DIRECT=1
export TCTI="device:/dev/tpmrm0"
export UNIFIED_IDENTITY_ENABLED=true

# Run in foreground to see what happens
./rust-keylime/target/release/keylime_agent

# Watch for:
# - Does it start?
# - Does it stay running?
# - Does it crash after "Switching from tpmrm0 to tpm0"?
```

### Cause 2: SSL Certificate Mismatch

**Symptoms:**
- Agent is running
- Verifier logs show SSL errors
- "certificate verify failed" in logs

**Fix:**
Already done - you cleaned state and regenerated certificates.

### Cause 3: Timeout Too Short

**Symptoms:**
- Agent is running
- Verifier logs show "timeout" or "599"
- Hardware TPM is slow

**Fix:**
Already done - increased timeout to 300s in verifier.conf.minimal.

### Cause 4: Agent Not Listening on Correct Port

**Symptoms:**
- Agent is running
- But not on port 9002

**Check:**
```bash
netstat -tln | grep 9002
# Should show: tcp ... 127.0.0.1:9002 ... LISTEN

# Or check what port agent is using
netstat -tlnp | grep keylime_agent
```

## Quick Fix Sequence

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# 1. Check if agent is alive
if ps aux | grep -q "[k]eylime_agent"; then
    echo "Agent process exists"
    if curl -k https://localhost:9002/v2.2/agent/version 2>/dev/null; then
        echo "✓ Agent is responding"
    else
        echo "✗ Agent is zombie (not responding)"
        pkill keylime_agent
    fi
else
    echo "✗ Agent is not running"
fi

# 2. Check for tpm2-abrmd conflict
if ps aux | grep -q "[t]pm2-abrmd"; then
    echo "✗ tpm2-abrmd is running (CONFLICT!)"
    sudo pkill -9 tpm2-abrmd
    echo "✓ Killed tpm2-abrmd"
fi

# 3. Check agent logs
echo "Last 20 lines of agent log:"
tail -20 /tmp/rust-keylime-agent.log

# 4. Restart agent
echo "Restarting agent..."
pkill keylime_agent
sleep 2

# Start agent (from test_complete.sh environment)
export KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_KEYLIME_DIR="/tmp/keylime-agent"
export USE_TPM2_QUOTE_DIRECT=1
export TCTI="device:/dev/tpmrm0"
export UNIFIED_IDENTITY_ENABLED=true

nohup ./rust-keylime/target/release/keylime_agent > /tmp/rust-keylime-agent.log 2>&1 &
AGENT_PID=$!
echo "Agent started with PID: $AGENT_PID"

# Wait and check
sleep 5
if ps -p $AGENT_PID > /dev/null; then
    echo "✓ Agent is running"
    if curl -k https://localhost:9002/v2.2/agent/version 2>/dev/null; then
        echo "✓ Agent is responding"
    else
        echo "✗ Agent not responding yet, check logs"
    fi
else
    echo "✗ Agent died immediately, check logs:"
    tail -30 /tmp/rust-keylime-agent.log
fi
```

## Most Likely Issue

Based on the error and our previous analysis, the **most likely issue** is:

**The rust-keylime agent is becoming a zombie** (process exists but doesn't respond) due to the TPM resource conflict with tpm2-abrmd.

## Verification

After fixing, verify:

```bash
# Agent is running
ps aux | grep keylime_agent

# Agent responds
curl -k https://localhost:9002/v2.2/agent/version

# No tpm2-abrmd
ps aux | grep tpm2-abrmd

# Test quote endpoint
./test-agent-quote-endpoint.sh

# If all pass, retry SPIRE Agent
pkill spire-agent
sleep 2
# SPIRE Agent will be restarted by test_complete.sh or start it manually
```

## Next Steps

1. Run the diagnostic commands above
2. Check agent logs
3. Check for tpm2-abrmd conflict
4. Restart agent if needed
5. Retry SPIRE Agent attestation

Let me know what you find in the logs!
