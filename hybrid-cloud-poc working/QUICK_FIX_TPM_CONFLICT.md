# Quick Fix: TPM Resource Conflict

## TL;DR - The Smoking Gun 🔫

**Problem**: rust-keylime agent becomes a zombie (process exists but doesn't respond)

**Root Cause**: `tpm2-abrmd` and rust-keylime agent both try to access `/dev/tpm0` → conflict

**Fix**: Disable `tpm2-abrmd` when using direct quote mode

## Quick Commands (Copy & Paste)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Step 1: Run automated fix
chmod +x fix-tpm-resource-conflict.sh
./fix-tpm-resource-conflict.sh

# Step 2: Test agent manually (in current terminal)
export KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_KEYLIME_DIR="/tmp/keylime-agent"
export USE_TPM2_QUOTE_DIRECT=1
export TCTI="device:/dev/tpmrm0"
export UNIFIED_IDENTITY_ENABLED=true
./rust-keylime/target/release/keylime_agent

# Expected: Agent starts and shows "Listening on https://127.0.0.1:9002"
# Agent should STAY RUNNING (not exit)

# Step 3: In NEW terminal, test the agent
cd ~/dhanush/hybrid-cloud-poc-backup
./test-agent-quote-endpoint.sh

# Expected: ✅ SUCCESS: Agent responded with quote

# Step 4: If manual test works, stop agent (Ctrl+C) and run full test
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

## What This Fixes

✅ Agent stays running (no more zombie process)  
✅ Agent responds to quote requests  
✅ SPIRE Agent can complete attestation  
✅ Workload API socket gets created  
✅ Step 1 (Single Machine Setup) completes!

## Technical Explanation

The rust-keylime agent has logic to avoid deadlock:
- It switches from `/dev/tpmrm0` (resource manager) to `/dev/tpm0` (direct hardware)
- This requires **exclusive access** to `/dev/tpm0`
- If `tpm2-abrmd` is running, it holds `/dev/tpm0` → conflict → agent hangs

**Solution**: Don't run `tpm2-abrmd`. The kernel resource manager is sufficient.

## Files Modified

- `test_complete.sh` - Comments out `tpm2-abrmd` startup
- `fix-tpm-resource-conflict.sh` - Automated fix script (NEW)
- `FIX_TPM_RESOURCE_CONFLICT.md` - Detailed documentation (NEW)

## Verification

After fix, you should see:

```bash
# Agent stays running
ps aux | grep keylime_agent
# Shows running process

# No tpm2-abrmd conflict
ps aux | grep tpm2-abrmd
# Shows nothing (or only grep)

# Agent responds
curl -k https://localhost:9002/v2.2/agent/version
# Returns version info
```

## If It Doesn't Work

1. **Check if tpm2-abrmd is still running:**
   ```bash
   ps aux | grep tpm2-abrmd
   sudo pkill -9 tpm2-abrmd
   ```

2. **Check agent logs:**
   ```bash
   tail -f /tmp/rust-keylime-agent.log
   # Look for "Switching from tpmrm0 to tpm0"
   # Should NOT see "Device busy" or hang after this
   ```

3. **Verify TPM device access:**
   ```bash
   ls -la /dev/tpm*
   # Should show /dev/tpm0 and /dev/tpmrm0
   ```

## Related Documents

- `FIX_TPM_RESOURCE_CONFLICT.md` - Full technical details
- `SUMMARY_SINGLE_MACHINE_STATUS.md` - Overall system status
- `FIX_VERIFIER_CONFIG_ERROR.md` - Previous fix (also needed)
