# Fix: TPM Resource Conflict - The Smoking Gun

## The Problem (Excellent Diagnosis!)

### What's Happening

1. **Zombie Agent Process**: The rust-keylime agent process exists but is "dead inside" - it's not responding to requests
2. **The Smoking Gun**: Agent logs show:
   ```
   INFO keylime::tpm > Switching from tpmrm0 to tpm0 to avoid deadlock
   ```
3. **The Conflict**:
   - `test_complete.sh` starts `tpm2-abrmd` (TPM Resource Manager daemon)
   - `tpm2-abrmd` **locks** the hardware TPM device (`/dev/tpm0`)
   - rust-keylime agent with `USE_TPM2_QUOTE_DIRECT=1` tries to access `/dev/tpm0` directly
   - **Result**: Device busy → Agent hangs/crashes after first quote

### Why This Happens

The rust-keylime agent has logic to avoid deadlock with the TSS library by switching from the resource manager (`/dev/tpmrm0`) to direct hardware access (`/dev/tpm0`). But if `tpm2-abrmd` is already holding `/dev/tpm0`, the agent can't access it.

**From rust-keylime/keylime/src/tpm.rs:**
```rust
// If using resource manager, try direct device instead to avoid deadlock
let tcti = if tcti.contains("tpmrm0") {
    log::info!("Switching from tpmrm0 to tpm0 to avoid deadlock with TSS context");
    "device:/dev/tpm0".to_string()
} else {
    tcti
};
```

## The Solution

We have **two options**:

### Option 1: Disable tpm2-abrmd (Recommended for Direct Quote Mode)

When using `USE_TPM2_QUOTE_DIRECT=1`, the agent needs exclusive access to the hardware.

### Option 2: Disable Direct Quote Mode (Use TSS Library Instead)

Use the kernel resource manager (`/dev/tpmrm0`) and TSS library instead of direct tpm2_quote.

## Implementation

### Option 1: Disable tpm2-abrmd (Recommended)

This is the **correct fix** for your current configuration with `USE_TPM2_QUOTE_DIRECT=1`.

#### Step 1: Patch test_complete.sh

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Backup the original
cp test_complete.sh test_complete.sh.backup

# Comment out tpm2-abrmd startup
sed -i 's/^[[:space:]]*tpm2-abrmd/# &/' test_complete.sh
sed -i 's/^[[:space:]]*if pgrep -x tpm2-abrmd/# &/' test_complete.sh

# Verify the changes
grep -n "tpm2-abrmd" test_complete.sh | head -10
```

#### Step 2: Kill Existing Conflicts

```bash
# Stop everything
pkill keylime_agent
pkill tpm2-abrmd
pkill spire-agent

# Clean corrupted state
rm -rf /tmp/keylime-agent
mkdir -p /tmp/keylime-agent
```

#### Step 3: Test Agent Manually (Foreground)

```bash
# Set environment variables
export KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_KEYLIME_DIR="/tmp/keylime-agent"
export USE_TPM2_QUOTE_DIRECT=1
export TCTI="device:/dev/tpmrm0"  # Agent will switch to tpm0 internally
export UNIFIED_IDENTITY_ENABLED=true

# Start agent in foreground to see logs
cd ~/dhanush/hybrid-cloud-poc-backup
./rust-keylime/target/release/keylime_agent
```

**Expected Output:**
```
INFO keylime_agent > Agent UUID: ...
INFO keylime_agent > Listening on https://127.0.0.1:9002
INFO keylime::tpm > Switching from tpmrm0 to tpm0 to avoid deadlock
```

**Agent should stay running!**

#### Step 4: Test in New Terminal

Open a new terminal and test:

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
./test-agent-quote-endpoint.sh
```

**Expected:** `✅ SUCCESS: Agent responded with quote`

#### Step 5: Run Full Test

If manual test works, stop the agent (Ctrl+C) and run the full test:

```bash
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

### Option 2: Disable Direct Quote Mode (Alternative)

If you want to use the TSS library instead of direct tpm2_quote:

#### Modify test_complete.sh

Find these lines (around line 1560):
```bash
export USE_TPM2_QUOTE_DIRECT=1
```

Change to:
```bash
export USE_TPM2_QUOTE_DIRECT=0
```

And ensure TCTI uses resource manager:
```bash
export TCTI="device:/dev/tpmrm0"
```

**Note:** This may reintroduce the deadlock issue that `USE_TPM2_QUOTE_DIRECT=1` was meant to solve.

## Automated Fix Script

I'll create a script to automate Option 1:

```bash
chmod +x fix-tpm-resource-conflict.sh
./fix-tpm-resource-conflict.sh
```

## Why This Matters

This is the **root cause** of:
- ✅ Agent exits after handling first quote
- ✅ SPIRE Agent crashes (can't get quotes from dead agent)
- ✅ No Workload API socket created
- ✅ Step 1 (Single Machine Setup) blocked at 95%

## Verification

After applying the fix, you should see:

```bash
# Agent stays running
ps aux | grep keylime_agent
# Should show running process

# Agent responds to health checks
curl -k https://localhost:9002/v2.2/agent/version
# Should return version info

# No tpm2-abrmd conflict
ps aux | grep tpm2-abrmd
# Should show NO process (or only grep itself)

# Agent logs show successful quotes
tail -f /tmp/rust-keylime-agent.log
# Should show repeated quote requests without crashes
```

## Technical Details

### The Deadlock Problem

The rust-keylime agent uses the TSS library (tss-esapi) which maintains a context lock. When using `tpm2_quote` subprocess with the same resource manager, both try to access the TPM simultaneously, causing deadlock.

**Solution in rust-keylime:**
- Use `USE_TPM2_QUOTE_DIRECT=1` to call `tpm2_quote` directly
- Switch from `/dev/tpmrm0` to `/dev/tpm0` to bypass resource manager
- This requires **exclusive access** to `/dev/tpm0`

### The Conflict

When `tpm2-abrmd` is running:
- It holds `/dev/tpm0` open
- Agent can't get exclusive access
- Agent hangs or crashes with "Device busy"

### The Fix

**Don't run tpm2-abrmd when using direct quote mode.** The kernel resource manager (`/dev/tpmrm0`) is sufficient for the TSS library operations, and the agent will switch to `/dev/tpm0` only for the `tpm2_quote` subprocess.

## Related Files

- `test_complete.sh` - Needs modification to not start tpm2-abrmd
- `rust-keylime/keylime/src/tpm.rs` - Contains the deadlock avoidance logic
- `SUMMARY_SINGLE_MACHINE_STATUS.md` - Overall status (this fixes the main blocker)

## Credits

This diagnosis correctly identified the "smoking gun" - the TPM resource conflict that causes the agent to become a zombie process. Excellent detective work!
