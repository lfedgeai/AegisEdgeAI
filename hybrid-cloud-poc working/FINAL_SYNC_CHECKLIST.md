# Final Sync Checklist - Local & Remote

## Status: Files Updated ✅

Your local Windows files are now in sync with the **good changes** from your remote machine, plus the TPM conflict fix.

## Changes Summary

### ✅ Good Changes (Applied to Local Files)

| File | Change | Status |
|------|--------|--------|
| `keylime/verifier.conf.minimal` | Added `[revocations]` section | ✅ Done |
| `keylime/verifier.conf.minimal` | Increased timeouts to 300s | ✅ Done |
| `test_complete.sh` | Disabled tpm2-abrmd startup | ✅ Done |
| `python-app-demo/fetch-sovereign-svid-grpc.py` | Increased timeouts to 300s | ✅ Done |

### ❌ Bad Change (Needs Revert on Remote)

| File | Change | Status | Action |
|------|--------|--------|--------|
| `keylime/keylime/cloud_verifier_tornado.py` | Added `validate_cert=False` | ❌ Breaks Verifier | **REVERT on remote** |

## Next Steps

### Step 1: Copy Files to Remote Machine

**Files to copy from Windows to Linux:**
- `keylime/verifier.conf.minimal`
- `test_complete.sh`
- `python-app-demo/fetch-sovereign-svid-grpc.py`
- `FIX_VALIDATE_CERT_ERROR.md`
- `REMOTE_MACHINE_COMMANDS.md`
- `FINAL_SYNC_CHECKLIST.md`

**How to copy:**

```bash
# On Windows (Git Bash or WSL)
cd /path/to/hybrid-cloud-poc

# Create tar file
tar -czf sync-files.tar.gz \
    keylime/verifier.conf.minimal \
    test_complete.sh \
    python-app-demo/fetch-sovereign-svid-grpc.py \
    FIX_VALIDATE_CERT_ERROR.md \
    REMOTE_MACHINE_COMMANDS.md \
    FINAL_SYNC_CHECKLIST.md

# Copy to USB or network share
# Then transfer to Linux machine
```

### Step 2: On Remote Linux Machine

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Extract files
tar -xzf sync-files.tar.gz

# CRITICAL: Revert the broken change
git checkout keylime/keylime/cloud_verifier_tornado.py

# Verify it's reverted
grep -n "validate_cert" keylime/keylime/cloud_verifier_tornado.py
# Should show NOTHING

# Clean ALL state
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db /tmp/*.log

# Restart everything
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

## Verification Checklist

After running the commands above, verify:

### ✅ Control Plane Services

```bash
# All services running
netstat -tln | grep -E "8081|8881|8890|9050"
# Should show 4 ports listening

# Verifier started without errors
tail -50 /tmp/keylime-verifier.log | grep -E "Starting Cloud Verifier|ERROR"
# Should see "Starting Cloud Verifier"
# Should NOT see "validate_cert" error
# Should NOT see "enabled_revocation_notifications" error
```

### ✅ Agent Services

```bash
# Agent is running (not zombie)
ps aux | grep keylime_agent
# Should show running process

# Agent responds
curl -k https://localhost:9002/v2.2/agent/version
# Should return version info

# No tpm2-abrmd conflict
ps aux | grep tpm2-abrmd
# Should show nothing (or only grep)

# Agent logs show success
tail -50 /tmp/rust-keylime-agent.log | grep -E "Listening|Switching from tpmrm0"
# Should see "Listening on https://127.0.0.1:9002"
# Should see "Switching from tpmrm0 to tpm0"
# Should NOT hang after switching
```

### ✅ SPIRE Agent

```bash
# SPIRE Agent running
ps aux | grep spire-agent
# Should show running process

# Agent has SVID
tail -50 /tmp/spire-agent.log | grep -i "agent svid"
# Should see "Agent SVID updated"

# Workload API socket exists
ls -la /tmp/spire-agent/public/api.sock
# Should show socket file
```

### ✅ End-to-End Test

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/python-app-demo
python3 fetch-sovereign-svid-grpc.py

# Expected output:
# ✓ SVID fetched successfully
# ✓ Certificate chain received
# ✓ AttestedClaims present
# ✓ Workload SVID contains grc.workload claims
```

## What Each Fix Addresses

| Fix | Problem Solved |
|-----|----------------|
| Added `[revocations]` section | Verifier crash: "No option 'enabled_revocation_notifications'" |
| Increased timeouts to 300s | Slow hardware TPM needs more time |
| Disabled tpm2-abrmd | TPM resource conflict → zombie agent |
| Reverted validate_cert | Verifier crash: "unexpected keyword argument" |
| Clean state | Certificate mismatch after SPIRE data cleanup |

## Expected Final Result

✅ All services start successfully  
✅ No crashes or errors  
✅ Agent stays running (no zombie)  
✅ Agent responds to requests  
✅ SPIRE Agent completes attestation  
✅ Workload API socket created  
✅ Workload SVID generated  
✅ **Step 1 (Single Machine Setup) COMPLETE!**

## If Something Goes Wrong

See these documents:
- `FIX_VALIDATE_CERT_ERROR.md` - How to revert the validate_cert change
- `REMOTE_MACHINE_COMMANDS.md` - Detailed troubleshooting
- `FIX_TPM_RESOURCE_CONFLICT.md` - TPM conflict details
- `SYNC_AND_FIX_GUIDE.md` - Complete explanation

## Files Reference

### Documentation Created
- ✅ `FINAL_SYNC_CHECKLIST.md` (this file)
- ✅ `FIX_VALIDATE_CERT_ERROR.md`
- ✅ `REMOTE_MACHINE_COMMANDS.md`
- ✅ `SYNC_AND_FIX_GUIDE.md`
- ✅ `QUICK_START_SYNC_AND_FIX.md`
- ✅ `FIX_TPM_RESOURCE_CONFLICT.md`
- ✅ `EXACT_LINES_TO_DISABLE.md`

### Files Updated
- ✅ `keylime/verifier.conf.minimal`
- ✅ `test_complete.sh`
- ✅ `python-app-demo/fetch-sovereign-svid-grpc.py`

### Files to Revert (on Remote)
- ❌ `keylime/keylime/cloud_verifier_tornado.py`

## Ready to Proceed?

1. Copy files to remote machine (tar file or manual)
2. Revert cloud_verifier_tornado.py
3. Clean state
4. Restart everything
5. Verify success

Good luck! 🚀
