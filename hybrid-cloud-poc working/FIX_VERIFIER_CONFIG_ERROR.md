# Fix: Keylime Verifier Configuration Error

## Problem

The Keylime Verifier crashes on startup with this error:

```
ERROR:keylime.verifier:No option 'enabled_revocation_notifications' in section: 'revocations'
configparser.NoOptionError: No option 'enabled_revocation_notifications' in section: 'revocations'
```

## Root Cause

The Keylime config parser's `getlist()` function doesn't handle empty values correctly. It needs an empty list `[]` instead of an empty string or missing value.

## Solution

### On Your Linux Machine (dell@vso)

1. **Navigate to your project directory:**
   ```bash
   cd ~/dhanush/hybrid-cloud-poc-backup
   ```

2. **Verify the config file has the correct content:**
   ```bash
   # Check if the [revocations] section exists and has the right value
   grep -A 5 "\[revocations\]" keylime/verifier.conf.minimal
   ```

   You should see:
   ```
   [revocations]
   # Revocation notifications configuration
   # Empty list means no revocation notifications enabled
   enabled_revocation_notifications = []
   zmq_port = 5556
   ```

3. **If it's missing or wrong, fix it:**
   ```bash
   # Run the verification script
   chmod +x verify-and-fix-config.sh
   ./verify-and-fix-config.sh
   ```

   OR manually edit the file:
   ```bash
   nano keylime/verifier.conf.minimal
   ```

   Make sure the `[revocations]` section at the end looks exactly like this:
   ```
   [revocations]
   # Revocation notifications configuration
   # Empty list means no revocation notifications enabled
   enabled_revocation_notifications = []
   zmq_port = 5556
   ```

4. **Save and test:**
   ```bash
   # Start control plane services
   ./test_complete_control_plane.sh --no-pause
   
   # If successful, start agent services
   ./test_complete.sh --no-pause
   ```

## What This Fixes

- ✅ Keylime Verifier will start successfully
- ✅ SPIRE Server can communicate with Keylime Verifier
- ✅ Agent attestation can proceed
- ✅ System moves closer to full functionality

## What's Next (After This Fix)

Once the verifier starts successfully, you'll still need to address:

1. **rust-keylime agent lifecycle** - Agent exits after handling requests (see SUMMARY_SINGLE_MACHINE_STATUS.md)
2. **SPIRE Agent socket creation** - Depends on agent staying running
3. **Workload SVID generation** - Final step of the workflow

## Understanding "Single Machine Configuration"

**Simple Explanation:**

"Configure in single machine" means running ALL these services on ONE computer (your Dell machine at 172.26.1.77):

- **Control Plane Services** (managed by `test_complete_control_plane.sh`):
  - SPIRE Server (port 8081)
  - Keylime Verifier (port 8881) ← **This is what's crashing**
  - Keylime Registrar (port 8890)
  - Mobile Sensor Microservice (port 9050)

- **Agent Services** (managed by `test_complete.sh`):
  - rust-keylime Agent (port 9002)
  - TPM Plugin Server (Unix socket)
  - SPIRE Agent (creates Workload API socket)

Instead of having these spread across multiple machines (which would be "distributed configuration"), everything runs on localhost (127.0.0.1) on your single Dell machine.

**Why Single Machine First?**

Your mentor's 3-step plan:
1. **Step 1 (Current):** Get single machine working - easier to debug, faster iteration
2. **Step 2 (Next):** Build automated CI/CD testing
3. **Step 3 (Later):** Expand to Kubernetes with multiple machines

## Verification

After applying the fix, you should see:

```bash
# Control plane services running
netstat -tln | grep -E "8081|8881|8890|9050"

# Expected output:
tcp  0  0 127.0.0.1:8081  0.0.0.0:*  LISTEN  # SPIRE Server
tcp  0  0 127.0.0.1:8881  0.0.0.0:*  LISTEN  # Keylime Verifier ← Should work now!
tcp  0  0 127.0.0.1:8890  0.0.0.0:*  LISTEN  # Keylime Registrar
tcp  0  0 127.0.0.1:9050  0.0.0.0:*  LISTEN  # Mobile Sensor
```

And in the verifier logs:
```bash
tail -f /tmp/keylime-verifier.log

# Should see:
INFO:keylime.verifier:Starting Cloud Verifier (tornado) on port 8881
INFO:keylime.verifier:Current API version 2.4
# NO ERROR about enabled_revocation_notifications
```

## Files Modified

- `keylime/verifier.conf.minimal` - Fixed `[revocations]` section
- `verify-and-fix-config.sh` - New script to verify and fix config automatically

## Related Issues

- See `SUMMARY_SINGLE_MACHINE_STATUS.md` for overall system status
- See `TROUBLESHOOT_QUOTE_FETCHING.md` for quote fetching issues (non-critical)
- See `FIX_SPIRE_AGENT_SOCKET.md` for socket creation issues (blocked by agent lifecycle)
