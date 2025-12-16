# Commands to Run on Remote Linux Machine

## Current Problem

You made changes on the remote machine that aren't in your local files, AND you introduced a bug (`validate_cert` error).

## Solution: Revert, Sync, and Fix

### Step 1: Revert the Broken Change

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Check if you have git
git status

# If git is available, revert the broken file
git checkout keylime/keylime/cloud_verifier_tornado.py

# If no git, manually edit the file
nano keylime/keylime/cloud_verifier_tornado.py
# Find line ~2143 and remove: 'validate_cert': False
# The line should look like:
#   request_kwargs = {'timeout': agent_quote_timeout}
# NOT:
#   request_kwargs = {'timeout': 300.0, 'validate_cert': False}
```

### Step 2: Copy Updated Files from Windows

After running `copy-updated-files-to-remote.sh` on Windows, the files should be on your Linux machine.

If you created a tar file:
```bash
cd ~/dhanush/hybrid-cloud-poc-backup
tar -xzf updated-files-*.tar.gz
```

### Step 3: Make Scripts Executable

```bash
chmod +x patch-test-complete.sh
chmod +x fix-tpm-resource-conflict.sh
chmod +x verify-and-fix-config.sh
```

### Step 4: Apply the TPM Conflict Fix

```bash
# This will comment out tpm2-abrmd startup in test_complete.sh
./patch-test-complete.sh
```

### Step 5: Clean ALL State (Important!)

Since you cleaned SPIRE data, you need to clean Keylime data too so certificates match:

```bash
# Stop everything
pkill keylime_agent 2>/dev/null || true
pkill spire-agent 2>/dev/null || true
pkill keylime-verifier 2>/dev/null || true
pkill keylime-registrar 2>/dev/null || true
pkill spire-server 2>/dev/null || true
pkill tpm2-abrmd 2>/dev/null || true

# Clean ALL state
rm -rf /tmp/keylime-agent
rm -rf /tmp/spire-*
rm -rf /opt/spire/data/*
rm -rf keylime/cv_ca  # Keylime CA certificates
rm -rf keylime/*.db   # Keylime databases

# Clean logs for fresh start
rm -f /tmp/*.log
```

### Step 6: Restart Control Plane

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Start control plane services (regenerates certificates)
./test_complete_control_plane.sh --no-pause
```

**Expected output:**
```
✓ SPIRE Server started (port 8081)
✓ Keylime Verifier started (port 8881)
✓ Keylime Registrar started (port 8890)
✓ Mobile Sensor Microservice started (port 9050)
```

**Check for errors:**
```bash
# Verifier should NOT crash
tail -50 /tmp/keylime-verifier.log

# Should see:
# INFO:keylime.verifier:Starting Cloud Verifier (tornado) on port 8881
# Should NOT see:
# ERROR:keylime.verifier:No option 'enabled_revocation_notifications'
# WARNING:keylime.verifier:...validate_cert...
```

### Step 7: Start Agent Services

```bash
# Start agent services
./test_complete.sh --no-pause
```

**Expected output:**
```
✓ rust-keylime Agent started (port 9002)
✓ TPM Plugin Server started
✓ SPIRE Agent started
✓ Agent attestation successful
✓ Workload SVID generated
```

**Check for errors:**
```bash
# Agent should stay running (not become zombie)
ps aux | grep keylime_agent

# Should show running process, not just grep

# Agent should respond
curl -k https://localhost:9002/v2.2/agent/version

# Should return version info, not "Connection refused"

# No tpm2-abrmd should be running
ps aux | grep tpm2-abrmd

# Should show nothing (or only grep itself)
```

### Step 8: Verify Success

```bash
# Check all services are running
netstat -tln | grep -E "8081|8881|8890|9002|9050"

# Should show all 5 ports listening

# Check SPIRE Agent has SVID
tail -50 /tmp/spire-agent.log | grep -i "agent svid"

# Should show "Agent SVID updated"

# Check Workload API socket exists
ls -la /tmp/spire-agent/public/api.sock

# Should show socket file

# Test workload SVID fetch
cd ~/dhanush/hybrid-cloud-poc-backup/python-app-demo
python3 fetch-sovereign-svid-grpc.py

# Should show:
# ✓ SVID fetched successfully
# ✓ Certificate chain received
# ✓ AttestedClaims present
```

## Troubleshooting

### If Verifier Still Crashes

```bash
# Check config file
cat keylime/verifier.conf.minimal | grep -A 3 "\[revocations\]"

# Should show:
# [revocations]
# enabled_revocation_notifications = []

# If missing, run:
./verify-and-fix-config.sh
```

### If Agent Becomes Zombie

```bash
# Check if tpm2-abrmd is running
ps aux | grep tpm2-abrmd

# If it's running, kill it:
sudo pkill -9 tpm2-abrmd

# Check agent logs
tail -50 /tmp/rust-keylime-agent.log

# Should see:
# "Listening on https://127.0.0.1:9002"
# "Switching from tpmrm0 to tpm0 to avoid deadlock"
# Should NOT hang after this
```

### If Certificate Errors Persist

```bash
# The issue is mismatched certificates
# Solution: Clean ALL state and regenerate

# Stop everything
pkill -f keylime
pkill -f spire

# Clean everything
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db

# Restart
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

## Summary of Changes

### Files Updated (from Windows)

1. ✅ `keylime/verifier.conf.minimal` - Increased timeouts to 300 seconds
2. ✅ `test_complete.sh` - Commented out tpm2-abrmd startup (via patch script)
3. ✅ `python-app-demo/fetch-sovereign-svid-grpc.py` - Increased timeouts to 300 seconds

### Files Reverted (on Linux)

1. ❌ `keylime/keylime/cloud_verifier_tornado.py` - Removed invalid `validate_cert` parameter

### State Cleaned

1. ✅ `/tmp/keylime-agent` - Agent data
2. ✅ `/tmp/spire-*` - SPIRE data
3. ✅ `/opt/spire/data/*` - SPIRE persistent data
4. ✅ `keylime/cv_ca` - Keylime CA certificates
5. ✅ `keylime/*.db` - Keylime databases

## Expected Result

After following these steps:

✅ Verifier starts without crashing  
✅ Agent stays running (no zombie)  
✅ Agent responds to quote requests  
✅ SPIRE Agent completes attestation  
✅ Workload API socket created  
✅ Workload SVID generated successfully  
✅ **Step 1 (Single Machine Setup) COMPLETE!**

## Next Steps

Once everything works:
1. Document the working configuration
2. Move to Step 2: Automated CI/CD Testing
3. Eventually: Step 3: Kubernetes Integration
