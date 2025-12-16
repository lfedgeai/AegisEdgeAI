# Single Machine Setup - Complete Step-by-Step Guide

## 🎯 Objective
Run the entire Hybrid Cloud POC on a single machine and fix the TPM Plugin communication error.

---

## 📋 Prerequisites

- TPM-enabled machine (Dell with TPM 2.0)
- Ubuntu/Debian Linux
- Root/sudo access
- Git repository cloned: `~/dhanush/hybrid-cloud-poc-backup`

---

## 🚀 Phase 1: Fix Current TPM Plugin Communication Error

### Step 1.1: Copy the diagnostic script

Copy `fix-tpm-plugin-communication.sh` to your remote machine:

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
# Paste the content of fix-tpm-plugin-communication.sh here
nano fix-tpm-plugin-communication.sh
# Paste content, then Ctrl+X, Y, Enter

# Make it executable
chmod +x fix-tpm-plugin-communication.sh
```

### Step 1.2: Run the diagnostic

```bash
./fix-tpm-plugin-communication.sh
```

**Expected Output:**
- Shows status of TPM Plugin Server
- Tests UDS socket communication
- Identifies the root cause of the error

### Step 1.3: Fix based on diagnostic results

**If TPM Plugin Server is not responding:**

```bash
# Check if it's running
ps aux | grep tpm_plugin_server

# If not running, check logs
tail -50 /tmp/tpm-plugin-server.log

# Restart TPM Plugin Server
cd ~/dhanush/hybrid-cloud-poc-backup
pkill -f tpm_plugin_server
./test_complete.sh --no-pause
```

**If SPIRE Agent cannot connect to TPM Plugin:**

```bash
# Stop SPIRE Agent
pkill -f spire-agent

# Verify TPM Plugin Server is running
ps aux | grep tpm_plugin_server
ls -la /tmp/spire-data/tpm-plugin/tpm-plugin.sock

# Restart SPIRE Agent with correct environment
cd ~/dhanush/hybrid-cloud-poc-backup/spire
export TPM_PLUGIN_ENDPOINT="unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
export UNIFIED_IDENTITY_ENABLED="true"

# Start SPIRE Agent
nohup ./bin/spire-agent run -config ./conf/agent/agent.conf > /tmp/spire-agent.log 2>&1 &

# Wait 10 seconds
sleep 10

# Check if Workload API socket is created
ls -la /tmp/spire-agent/public/api.sock
```

**If Keylime Verifier is rejecting attestation:**

```bash
# Check Keylime Verifier logs
tail -100 /tmp/keylime-verifier.log | grep -i "error\|failed"

# Check SPIRE Server logs
tail -100 /tmp/spire-server.log | grep -i "keylime\|verification"

# Common issue: Stub data being sent instead of real TPM data
# This means SPIRE Agent is not getting real data from TPM Plugin
```

---

## 🔧 Phase 2: Configure Single Machine Setup

### Step 2.1: Copy the configuration script

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
# Paste the content of configure-single-machine.sh here
nano configure-single-machine.sh
# Paste content, then Ctrl+X, Y, Enter

# Make it executable
chmod +x configure-single-machine.sh
```

### Step 2.2: Run the configuration script

```bash
./configure-single-machine.sh
```

**Interactive prompts:**
1. Select option 1 (localhost) - Recommended
2. Script will automatically:
   - Detect your username
   - Update IP addresses in test_complete_integration.sh
   - Create backup of original file
   - Setup SSH if needed

### Step 2.3: Verify the configuration

```bash
# Check what was changed
diff test_complete_integration.sh.backup test_complete_integration.sh

# Should show:
# - CONTROL_PLANE_HOST changed to 127.0.0.1
# - ONPREM_HOST changed to 127.0.0.1
# - SSH_USER changed to your username
```

### Step 2.4: Manual modification for on-prem section

Since both control plane and on-prem are on the same machine, we need to avoid SSH to localhost.

**Find the on-prem section in test_complete_integration.sh:**

```bash
nano test_complete_integration.sh
```

**Search for the on-prem setup section (around line 100-200):**

Look for something like:
```bash
echo "Setting up on-prem services..."
ssh ${SSH_USER}@${ONPREM_HOST} "cd ~/path && ./test_onprem.sh"
```

**Replace with:**
```bash
echo "Setting up on-prem services..."

# Single machine detection - avoid SSH to localhost
if [ "$CONTROL_PLANE_HOST" == "$ONPREM_HOST" ]; then
    echo "  Running on-prem setup locally (same machine as control plane)..."
    cd ~/dhanush/hybrid-cloud-poc-backup/enterprise-private-cloud
    ./test_onprem.sh --no-pause
else
    echo "  Running on-prem setup via SSH..."
    ssh ${SSH_USER}@${ONPREM_HOST} "cd ~/dhanush/hybrid-cloud-poc-backup/enterprise-private-cloud && ./test_onprem.sh --no-pause"
fi
```

**Save and exit:** Ctrl+X, Y, Enter

---

## 🧪 Phase 3: Test the Setup

### Step 3.1: Clean up previous runs

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Stop all services
pkill -f spire-agent
pkill -f spire-server
pkill -f keylime
pkill -f tpm_plugin_server

# Clean up data directories
rm -rf /tmp/spire-agent
rm -rf /tmp/spire-server
rm -rf /tmp/keylime-agent
rm -rf /tmp/spire-data/tpm-plugin
rm -rf /tmp/svid-dump

# Clean up logs
rm -f /tmp/spire-*.log
rm -f /tmp/keylime-*.log
rm -f /tmp/tpm-plugin-*.log
```

### Step 3.2: Run control plane setup

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
./test_complete_control_plane.sh --no-pause
```

**Wait for completion and verify:**
```bash
# Check services are running
ps aux | grep -E "spire-server|keylime.cmd.verifier|keylime.cmd.registrar"

# Check health
./spire/bin/spire-server healthcheck -socketPath /tmp/spire-server/private/api.sock
curl -k https://localhost:8881/version
curl http://localhost:8890/version
```

### Step 3.3: Run agent setup

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
./test_complete.sh --no-pause
```

**Monitor the output carefully:**
- Step 4: rust-keylime Agent should start successfully
- Step 5: Agent should register with Keylime
- Step 6: TPM Plugin Server should start and create socket
- Step 7: SPIRE Agent should start
- Step 9: **CRITICAL** - Check if TPM operations succeed (no stub data)

**If you see "stub data" warnings:**
```bash
# Stop and diagnose
pkill -f spire-agent

# Run diagnostic again
./fix-tpm-plugin-communication.sh

# Check TPM Plugin Server logs
tail -50 /tmp/tpm-plugin-server.log

# Check SPIRE Agent logs
tail -50 /tmp/spire-agent.log | grep -i "tpm\|plugin"
```

### Step 3.4: Verify Workload API socket

```bash
# This socket should exist after successful attestation
ls -la /tmp/spire-agent/public/api.sock

# If it exists, test it
cd ~/dhanush/hybrid-cloud-poc-backup/python-app-demo
python3 fetch-sovereign-svid-grpc.py
```

### Step 3.5: Run on-prem setup (if needed)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/enterprise-private-cloud
./test_onprem.sh --no-pause
```

### Step 3.6: Run full integration test

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
./test_complete_integration.sh --no-pause
```

---

## 🔍 Troubleshooting Guide

### Issue 1: "TPM plugin not available, using stub data"

**Cause:** SPIRE Agent cannot connect to TPM Plugin Server

**Fix:**
```bash
# 1. Verify TPM Plugin Server is running
ps aux | grep tpm_plugin_server

# 2. Verify socket exists
ls -la /tmp/spire-data/tpm-plugin/tpm-plugin.sock

# 3. Test socket directly
curl --unix-socket /tmp/spire-data/tpm-plugin/tpm-plugin.sock \
  -X POST -H "Content-Type: application/json" -d '{}' \
  http://localhost/get-app-key

# 4. Check SPIRE Agent environment
ps aux | grep spire-agent
cat /proc/$(pgrep spire-agent)/environ | tr '\0' '\n' | grep TPM_PLUGIN_ENDPOINT

# 5. If TPM_PLUGIN_ENDPOINT is not set, restart SPIRE Agent:
pkill -f spire-agent
cd ~/dhanush/hybrid-cloud-poc-backup
export TPM_PLUGIN_ENDPOINT="unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
export UNIFIED_IDENTITY_ENABLED="true"
./spire/bin/spire-agent run -config ./spire/conf/agent/agent.conf > /tmp/spire-agent.log 2>&1 &
```

### Issue 2: "Workload API socket not found"

**Cause:** SPIRE Agent attestation failed

**Fix:**
```bash
# 1. Check SPIRE Agent logs
tail -100 /tmp/spire-agent.log | grep -i "error\|attestation"

# 2. Check SPIRE Server logs
tail -100 /tmp/spire-server.log | grep -i "attestation\|keylime"

# 3. Check Keylime Verifier logs
tail -100 /tmp/keylime-verifier.log | grep -i "error\|verification"

# 4. Common issue: Keylime verification failed
# Look for: "app key certificate signature verification failed"
# This means stub data was sent instead of real TPM data
```

### Issue 3: "Keylime verification failed"

**Cause:** Keylime Verifier rejected the attestation

**Fix:**
```bash
# 1. Check if stub data was sent
grep "stub" /tmp/spire-agent.log

# 2. If stub data was sent, fix TPM Plugin communication (see Issue 1)

# 3. Check Keylime Verifier logs for specific error
tail -100 /tmp/keylime-verifier.log

# 4. Common errors:
#    - "Failed to parse TPM attestation structure" = stub data sent
#    - "App Key certificate signature verification failed" = stub data sent
#    - "Mobile sensor location verification failed" = CAMARA API issue
```

### Issue 4: SSH to localhost fails

**Cause:** Trying to SSH to same machine

**Fix:**
Already handled in Step 2.4 - make sure you added the same-machine detection logic.

### Issue 5: CAMARA API rate limiting

**Cause:** Too many requests to CAMARA API

**Fix:**
```bash
# Bypass CAMARA API for testing
export CAMARA_BYPASS=true

# Restart the test
./test_complete.sh --no-pause
```

---

## 📊 Success Criteria

After completing all steps, you should have:

✅ **Control Plane Running:**
- SPIRE Server (port 8081)
- Keylime Verifier (port 8881)
- Keylime Registrar (port 8890)

✅ **Agent Services Running:**
- rust-keylime Agent (port 9002)
- TPM Plugin Server (UDS socket)
- SPIRE Agent (with Workload API socket)

✅ **No Errors:**
- No "stub data" warnings in SPIRE Agent logs
- No "TPM plugin not available" errors
- Workload API socket exists: `/tmp/spire-agent/public/api.sock`

✅ **Successful Attestation:**
- SPIRE Agent has SPIFFE ID
- Keylime Verifier accepted attestation
- Workload SVID can be fetched

✅ **Single Machine:**
- All services running on same machine
- No SSH errors
- All IP addresses point to 127.0.0.1 or your machine IP

---

## 🎓 Quick Reference Commands

```bash
# Check all services
ps aux | grep -E "spire-server|spire-agent|keylime|tpm_plugin"

# Check all sockets
ls -la /tmp/spire-server/private/api.sock
ls -la /tmp/spire-agent/public/api.sock
ls -la /tmp/spire-data/tpm-plugin/tpm-plugin.sock

# Check all logs
tail -f /tmp/spire-server.log
tail -f /tmp/spire-agent.log
tail -f /tmp/keylime-verifier.log
tail -f /tmp/tpm-plugin-server.log

# Test TPM Plugin
curl --unix-socket /tmp/spire-data/tpm-plugin/tpm-plugin.sock \
  -X POST -H "Content-Type: application/json" -d '{}' \
  http://localhost/get-app-key

# Test Workload API
cd ~/dhanush/hybrid-cloud-poc-backup/python-app-demo
python3 fetch-sovereign-svid-grpc.py

# Clean restart
pkill -f "spire\|keylime\|tpm_plugin"
rm -rf /tmp/spire-* /tmp/keylime-* /tmp/svid-dump
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

---

## 📞 Getting Help

If you encounter issues:

1. **Run the diagnostic:** `./fix-tpm-plugin-communication.sh`
2. **Check logs:** Look at the specific error messages
3. **Search for patterns:** `grep -i "error\|failed" /tmp/*.log`
4. **Verify services:** Make sure all required services are running
5. **Check environment:** Verify environment variables are set correctly

---

## 🎯 Next Steps After Success

Once single machine setup is working:

1. ✅ **Verify end-to-end flow** - Run complete integration test
2. ✅ **Build CI/CD automation** - Create automated test suite
3. ✅ **Integrate Keylime optimization** - Apply your optimized code
4. ✅ **Test Kubernetes integration** - Use SPIRE CSI Driver

Good luck! 🚀
