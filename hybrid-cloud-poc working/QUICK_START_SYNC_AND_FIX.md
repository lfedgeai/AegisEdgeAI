# Quick Start: Sync Files & Fix Errors

## TL;DR

You made changes on remote Linux machine that aren't in local files, AND introduced a bug. Here's how to fix it:

## On Windows (This Machine)

### 1. Files Already Updated ✅

I've already updated these files in your IDE:
- `keylime/verifier.conf.minimal` - Increased timeouts to 300s
- `python-app-demo/fetch-sovereign-svid-grpc.py` - Increased timeouts to 300s
- Created fix scripts: `patch-test-complete.sh`, `fix-tpm-resource-conflict.sh`

### 2. Copy Files to Linux

**Option A: Create TAR file**
```bash
# In Git Bash or WSL
chmod +x copy-updated-files-to-remote.sh
./copy-updated-files-to-remote.sh
# This creates a .tar.gz file
# Copy it to your Linux machine via USB/network
```

**Option B: Manual copy**
Copy these files to Linux machine:
- `keylime/verifier.conf.minimal`
- `test_complete.sh`
- `python-app-demo/fetch-sovereign-svid-grpc.py`
- `patch-test-complete.sh`
- `fix-tpm-resource-conflict.sh`
- `REMOTE_MACHINE_COMMANDS.md`

## On Linux (Remote Machine)

### Quick Commands (Copy & Paste)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# 1. Revert the broken change
git checkout keylime/keylime/cloud_verifier_tornado.py
# Or manually remove the 'validate_cert': False line

# 2. Extract updated files (if using tar)
tar -xzf updated-files-*.tar.gz

# 3. Make scripts executable
chmod +x patch-test-complete.sh fix-tpm-resource-conflict.sh

# 4. Apply TPM conflict fix
./patch-test-complete.sh

# 5. Clean ALL state (important!)
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db /tmp/*.log

# 6. Restart control plane
./test_complete_control_plane.sh --no-pause

# 7. Start agent services
./test_complete.sh --no-pause

# 8. Verify success
ps aux | grep keylime_agent  # Should show running process
curl -k https://localhost:9002/v2.2/agent/version  # Should return version
ls -la /tmp/spire-agent/public/api.sock  # Should exist
```

## What This Fixes

✅ **validate_cert error** - Reverted broken code  
✅ **Files out of sync** - Updated local files, copied to remote  
✅ **TPM conflict** - Disabled tpm2-abrmd  
✅ **Certificate mismatch** - Cleaned state, regenerated certificates  
✅ **Zombie agent** - Agent stays running  
✅ **SPIRE Agent crash** - Attestation succeeds  
✅ **Missing socket** - Workload API socket created  

## Expected Result

```bash
# All services running
netstat -tln | grep -E "8081|8881|8890|9002|9050"
# Shows 5 ports listening

# Agent alive and responding
ps aux | grep keylime_agent
curl -k https://localhost:9002/v2.2/agent/version

# No tpm2-abrmd conflict
ps aux | grep tpm2-abrmd
# Shows nothing

# Workload SVID works
cd python-app-demo
python3 fetch-sovereign-svid-grpc.py
# Shows: ✓ SVID fetched successfully
```

## If Something Goes Wrong

See `REMOTE_MACHINE_COMMANDS.md` for detailed troubleshooting.

## Files Reference

- `SYNC_AND_FIX_GUIDE.md` - Detailed explanation
- `REMOTE_MACHINE_COMMANDS.md` - Step-by-step Linux commands
- `EXACT_LINES_TO_DISABLE.md` - What to change in test_complete.sh
- `FIX_TPM_RESOURCE_CONFLICT.md` - Technical details on TPM conflict
