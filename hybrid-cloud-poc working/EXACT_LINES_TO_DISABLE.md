# Exact Lines to Disable in test_complete.sh

## The Problem Section (Lines 1405-1423)

This is the **exact code** that starts `tpm2-abrmd` and causes the conflict:

```bash
# Ensure tpm2-abrmd (resource manager) is running for hardware TPM
if [ -c /dev/tpmrm0 ] || [ -c /dev/tpm0 ]; then
    if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
        echo "    Starting tpm2-abrmd resource manager for hardware TPM..."
        # Start tpm2-abrmd in background if not running
        if command -v tpm2-abrmd >/dev/null 2>&1; then
            tpm2-abrmd --tcti=device 2>/dev/null &
            sleep 1
            if pgrep -x tpm2-abrmd >/dev/null 2>&1; then
                echo "    ✓ tpm2-abrmd started"
            else
                echo -e "${YELLOW}    ⚠ tpm2-abrmd may need to be started manually or via systemd${NC}"
            fi
        fi
    else
        echo "    ✓ tpm2-abrmd resource manager is running"
    fi
fi
```

## Answer: NO, This is NOT Required!

### Why It's Not Needed

1. **Kernel Resource Manager**: Linux kernel provides `/dev/tpmrm0` which is sufficient
2. **Direct Quote Mode**: With `USE_TPM2_QUOTE_DIRECT=1`, the agent uses `tpm2_quote` command directly
3. **TSS Library**: The TSS library (tss-esapi) works fine with `/dev/tpmrm0` without `tpm2-abrmd`

### Why It Causes Problems

1. **Locks the device**: `tpm2-abrmd` holds `/dev/tpm0` open
2. **Blocks the agent**: rust-keylime agent can't get exclusive access to `/dev/tpm0`
3. **Creates zombie**: Agent hangs waiting for device access

## How to Fix

### Option 1: Automated Patch (Recommended)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
chmod +x patch-test-complete.sh
./patch-test-complete.sh
```

### Option 2: Manual Edit

```bash
nano test_complete.sh
```

Find line 1405 (search for "Ensure tpm2-abrmd") and comment out the entire section:

**BEFORE:**
```bash
# Ensure tpm2-abrmd (resource manager) is running for hardware TPM
if [ -c /dev/tpmrm0 ] || [ -c /dev/tpm0 ]; then
    if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
        echo "    Starting tpm2-abrmd resource manager for hardware TPM..."
```

**AFTER:**
```bash
# DISABLED: tpm2-abrmd conflicts with USE_TPM2_QUOTE_DIRECT=1
# The kernel resource manager (/dev/tpmrm0) is sufficient
# # Ensure tpm2-abrmd (resource manager) is running for hardware TPM
# if [ -c /dev/tpmrm0 ] || [ -c /dev/tpm0 ]; then
#     if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
#         echo "    Starting tpm2-abrmd resource manager for hardware TPM..."
```

Comment out **all lines from 1405 to 1423** (the entire if block).

### Option 3: Use sed Command

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Backup first
cp test_complete.sh test_complete.sh.backup

# Comment out lines 1405-1423
sed -i '1405,1423 s/^/# DISABLED: /' test_complete.sh

# Verify
sed -n '1405,1415p' test_complete.sh
```

## Additional Sections to Check

There are also references to `tpm2-abrmd` in the TCTI configuration (around lines 1590-1620). These should also be disabled:

```bash
# Around line 1591-1593
elif command -v tpm2-abrmd >/dev/null; then
     export TCTI="tabrmd:bus_name=com.intel.tss2.Tabrmd"
fi
```

**Change to:**
```bash
# DISABLED: Use kernel resource manager instead
# elif command -v tpm2-abrmd >/dev/null; then
#      export TCTI="tabrmd:bus_name=com.intel.tss2.Tabrmd"
# fi
```

## What Should Remain

The **cleanup** section that kills `tpm2-abrmd` should **stay enabled**:

```bash
# Around line 684 - KEEP THIS!
pkill -f "tpm2-abrmd" >/dev/null 2>&1 || true
```

This ensures any existing `tpm2-abrmd` process is stopped before starting the test.

## Verification After Fix

```bash
# Check the file was patched
grep -n "DISABLED" test_complete.sh | grep tpm2-abrmd

# Should show commented lines around 1405-1423
```

## Summary

**Question**: Is the `tpm2-abrmd` startup section required?

**Answer**: **NO!** It's not only unnecessary, it's **harmful** because it creates the TPM resource conflict that causes the agent to become a zombie.

**Action**: Disable/comment out the entire section (lines 1405-1423) and the TCTI fallback references.

**Result**: Agent will use kernel resource manager (`/dev/tpmrm0`) for TSS operations and direct `/dev/tpm0` access for `tpm2_quote` without conflict.
