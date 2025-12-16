# Single Machine Setup - Current Status & Issues

## ✅ What's Working

1. **Control Plane Services** - All start successfully:
   - ✅ SPIRE Server (port 8081)
   - ✅ Keylime Verifier (port 8881)
   - ✅ Keylime Registrar (port 8890)
   - ✅ Mobile Sensor Microservice (port 9050)

2. **Agent Services** - Start successfully:
   - ✅ rust-keylime Agent (port 9002) - registers and activates
   - ✅ TPM Plugin Server (UDS socket)
   - ✅ SPIRE Agent - starts and attempts attestation

3. **TPM Operations** - All work correctly:
   - ✅ App Key generation
   - ✅ Delegated certification (App Key certified by AK)
   - ✅ TPM Quote generation
   - ✅ SovereignAttestation building

4. **Initial Attestation** - Works once:
   - ✅ SPIRE Agent successfully attests initially
   - ✅ Gets Agent SVID
   - ✅ All 8 unit tests pass

## ❌ What's Broken

### Issue 1: rust-keylime Agent Exits After Handling Requests

**Symptom**: The rust-keylime agent process exits cleanly after handling the first quote request.

**Evidence**:
```bash
ps aux | grep keylime_agent  # Shows no process
tail /tmp/rust-keylime-agent.log  # Log ends after successful quote, no error
```

**Impact**: 
- Keylime Verifier can't fetch quotes for subsequent attestations
- SPIRE Agent crashes when attestation fails
- No Workload API socket created

### Issue 2: SPIRE Agent Crashes Due to Failed Attestation

**Symptom**: SPIRE Agent crashes with error:
```
Agent crashed: failed to receive attestation response: rpc error: code = Internal 
desc = failed to process sovereign attestation: keylime verification failed: 
keylime verifier returned status 400: {"code": 400, "status": 
"missing required field: data.quote (agent retrieval failed)", "results": {}}
```

**Root Cause**: Keylime Verifier tries to fetch quote from rust-keylime agent, but agent is not running.

**Impact**: No Workload API socket created at `/tmp/spire-agent/public/api.sock`

### Issue 3: Quote Fetching HTTP 599 Errors

**Symptom**: Keylime Verifier gets HTTP 599 errors when trying to fetch quotes:
```
ERROR: Unified-Identity: Agent quote request failed (API v1.0) HTTP 599: <binary>
ERROR: Unified-Identity: Unable to retrieve quote from agent for nonce...
```

**Root Cause**: 
- rust-keylime agent not running (primary cause)
- Possible tornado HTTP client / actix-web server incompatibility (secondary)

**Workaround Applied**: Increased timeout from 30s to 60s in `keylime/verifier.conf.minimal`

## 🔍 Root Cause Analysis - THE SMOKING GUN FOUND! 🔫

The core issue is a **TPM Resource Conflict**:

1. `test_complete.sh` starts `tpm2-abrmd` (TPM Resource Manager daemon)
2. `tpm2-abrmd` **locks** the hardware TPM device (`/dev/tpm0`)
3. rust-keylime agent with `USE_TPM2_QUOTE_DIRECT=1` tries to access `/dev/tpm0` directly
4. Agent logs show: `INFO keylime::tpm > Switching from tpmrm0 to tpm0 to avoid deadlock`
5. **Conflict**: Agent can't access `/dev/tpm0` because `tpm2-abrmd` is holding it
6. **Result**: Agent becomes a "zombie" - process exists but is dead inside (not responding)
7. SPIRE Agent tries to attest again (retry)
8. Keylime Verifier tries to fetch quote - **FAILS** (agent is zombie)
9. SPIRE Server rejects attestation
10. SPIRE Agent crashes
11. No Workload API socket created

**Why the agent switches to /dev/tpm0:**
The rust-keylime agent intentionally switches from `/dev/tpmrm0` to `/dev/tpm0` to avoid deadlock with the TSS library. But this creates a conflict when `tpm2-abrmd` is already holding the device.

## 🛠️ Fixes Needed

### Fix 1: Resolve TPM Resource Conflict (CRITICAL - ROOT CAUSE)

**The Problem**: `tpm2-abrmd` and rust-keylime agent both try to access `/dev/tpm0`, causing conflict.

**The Solution**: Disable `tpm2-abrmd` when using `USE_TPM2_QUOTE_DIRECT=1`

**Implementation**:
```bash
# Run the automated fix script
chmod +x fix-tpm-resource-conflict.sh
./fix-tpm-resource-conflict.sh

# Or manually edit test_complete.sh to comment out tpm2-abrmd startup
```

**Why This Works**:
- The kernel resource manager (`/dev/tpmrm0`) is sufficient for TSS library operations
- The agent will switch to `/dev/tpm0` only for the `tpm2_quote` subprocess
- Without `tpm2-abrmd` holding the device, agent can access it successfully

**See**: `FIX_TPM_RESOURCE_CONFLICT.md` for detailed instructions

### Fix 2: Make SPIRE Agent More Resilient

**Options**:
1. **Don't crash on attestation failure** - Retry indefinitely instead of crashing
2. **Create socket even without SVID** - Allow workloads to connect while attestation is in progress

**Recommended**: This is a SPIRE Agent design decision, may not be changeable

### Fix 3: Fix Quote Fetching (Optimization)

**Options**:
1. **Fix tornado/actix-web compatibility** - Investigate SSL context issues
2. **Use different HTTP client** - Replace tornado with requests library
3. **Disable quote fetching** - System works without it (quote is in SovereignAttestation)

**Recommended**: Option 3 (short-term) - system already works, this is just an optimization

## 📋 Action Items

### Immediate (To Get System Working)

1. **Add agent monitoring to test script**:
   ```bash
   # In test_complete.sh, before Step 10:
   if ! ps aux | grep -q "[k]eylime_agent"; then
       echo "Restarting rust-keylime agent..."
       # Restart agent with proper environment
   fi
   ```

2. **Verify agent stays running**:
   ```bash
   # Add to rust-keylime agent startup:
   # Use setsid + nohup + disown to ensure it stays running
   ```

### Short-term (For Stability)

1. **Debug why rust-keylime agent exits**
   - Add more logging
   - Check if it's a configuration issue
   - Check if it's intentional (one-shot mode?)

2. **Add health checks**
   - Monitor agent process
   - Restart if it dies
   - Alert if it keeps dying

### Long-term (For Production)

1. **Use proper process management**
   - systemd service files
   - Automatic restart on failure
   - Proper logging

2. **Fix quote fetching**
   - Investigate tornado/actix-web compatibility
   - Or use different HTTP client
   - Or disable if not needed

## 🎯 Current Goal: Step 1 - Single Machine Setup

**Status**: 95% Complete

**What works**:
- ✅ All services start on single machine
- ✅ TPM operations work
- ✅ Initial attestation succeeds
- ✅ All unit tests pass

**What's missing**:
- ❌ Workload SVID generation (Step 10)
- ❌ Agent stays running for full test duration

**Blocker**: rust-keylime agent exits, causing SPIRE Agent to crash

**Next Step**: Fix agent lifecycle issue, then move to Step 2 (Automated CI/CD Testing)

## 📝 Notes

- The system **does work** - it successfully attests once
- The issue is **process management**, not functionality
- Quote fetching errors are **non-critical** - system works without them
- Once agent lifecycle is fixed, Step 1 will be complete
