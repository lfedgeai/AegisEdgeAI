# Sync Local Files & Fix validate_cert Error

## Current Situation

You have **two problems**:

1. **Files Out of Sync**: Changes made on remote Linux machine aren't in your local Windows files
2. **New Error**: `validate_cert` is not a valid argument - causing Verifier to crash

## Problem Analysis

### The validate_cert Error

**What you tried on remote machine:**
```python
request_kwargs = {'timeout': 300.0, 'validate_cert': False}
```

**Why it fails:**
- `validate_cert` is **not a valid parameter** for tornado's HTTP client
- The correct way is to modify the **SSL context** to not verify certificates

### The Real Issue

The Verifier is rejecting the Agent's self-signed certificate. This happens because:
1. You cleaned `/tmp/spire-*` and `/opt/spire/data/*`
2. SPIRE regenerated fresh keys (new Root CA, new Agent Key)
3. The rust-keylime agent has a **new self-signed certificate**
4. The Verifier doesn't trust it

## Solution Strategy

We have **two options**:

### Option A: Fix Certificate Trust (Recommended - Proper Security)

Make the Verifier trust the Agent's certificate by using the correct CA.

### Option B: Disable Certificate Validation (Quick Fix - Less Secure)

Modify the SSL context to not verify certificates.

## Implementation

### Option A: Fix Certificate Trust (Recommended)

The proper fix is to ensure the Verifier trusts the Agent's CA certificate.

#### Step 1: Update Local Files First

On your **Windows machine** (this IDE), update these files to match your remote changes:

1. **keylime/verifier.conf.minimal** - Add timeout settings
2. **test_complete.sh** - Comment out tpm2-abrmd
3. **python-app-demo/fetch-sovereign-svid-grpc.py** - Increase timeouts

#### Step 2: Fix the Certificate Trust Issue

The issue is that after cleaning SPIRE data, the certificates changed. You need to:

**On your remote Linux machine:**

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Step 1: Stop everything
pkill keylime_agent
pkill spire-agent
pkill keylime-verifier

# Step 2: Clean ALL state (including Keylime)
rm -rf /tmp/keylime-agent
rm -rf /tmp/spire-*
rm -rf /opt/spire/data/*
rm -rf keylime/cv_ca  # This is the Keylime CA directory

# Step 3: Restart from clean state
./test_complete_control_plane.sh --no-pause
# This will regenerate Keylime CA certificates

# Step 4: Start agent services
./test_complete.sh --no-pause
```

This ensures the Verifier and Agent are using matching certificates.

### Option B: Disable Certificate Validation (Quick Fix)

If you want to disable certificate validation temporarily for testing:

#### Fix for cloud_verifier_tornado.py

**WRONG (what you tried):**
```python
request_kwargs = {'timeout': 300.0, 'validate_cert': False}  # ❌ Invalid parameter
```

**CORRECT:**
```python
import ssl

# Create SSL context that doesn't verify certificates
if use_https:
    ssl_context_no_verify = ssl.create_default_context()
    ssl_context_no_verify.check_hostname = False
    ssl_context_no_verify.verify_mode = ssl.CERT_NONE
    request_kwargs['context'] = ssl_context_no_verify
else:
    request_kwargs = {'timeout': agent_quote_timeout}
```

## Step-by-Step: Sync and Fix

### On Windows Machine (This IDE)

#### 1. Update keylime/verifier.conf.minimal

Add these lines to the `[verifier]` section:

```ini
# Timeout for fetching quotes from agent (in seconds)
agent_quote_timeout_seconds = 300
request_timeout = 300
connect_timeout = 300
```

#### 2. Update test_complete.sh

Comment out lines 1405-1423 (tpm2-abrmd startup):

```bash
# Run the patch script
chmod +x patch-test-complete.sh
./patch-test-complete.sh
```

Or manually:
```bash
# DISABLED: tpm2-abrmd conflicts with USE_TPM2_QUOTE_DIRECT=1
# if [ -c /dev/tpmrm0 ] || [ -c /dev/tpm0 ]; then
#     if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
#         echo "    Starting tpm2-abrmd resource manager for hardware TPM..."
#         ...
#     fi
# fi
```

#### 3. Update python-app-demo/fetch-sovereign-svid-grpc.py

Change timeouts:
```python
max_wait = 300  # Changed from 30
max_wait_seconds = 300  # Changed from 30
```

#### 4. Fix cloud_verifier_tornado.py (Option B - if needed)

Find the section around line 2143 and replace with proper SSL context handling.

### On Linux Machine (Remote)

#### 1. Revert the Broken Change

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/keylime/keylime

# Restore original file
git checkout cloud_verifier_tornado.py

# Or manually remove the validate_cert line
nano cloud_verifier_tornado.py
# Remove: 'validate_cert': False
```

#### 2. Clean State and Restart

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Stop everything
pkill keylime_agent
pkill spire-agent  
pkill keylime-verifier
pkill keylime-registrar
pkill spire-server

# Clean ALL state
rm -rf /tmp/keylime-agent
rm -rf /tmp/spire-*
rm -rf /opt/spire/data/*
rm -rf keylime/cv_ca

# Restart control plane (regenerates certificates)
./test_complete_control_plane.sh --no-pause

# Start agent services
./test_complete.sh --no-pause
```

## Files to Update

### Local Windows Machine (This IDE)

1. ✅ `keylime/verifier.conf.minimal` - Add timeout settings
2. ✅ `test_complete.sh` - Comment out tpm2-abrmd (use patch-test-complete.sh)
3. ✅ `python-app-demo/fetch-sovereign-svid-grpc.py` - Increase timeouts
4. ⚠️ `keylime/keylime/cloud_verifier_tornado.py` - Only if using Option B

### Remote Linux Machine

1. ❌ **Revert** `keylime/keylime/cloud_verifier_tornado.py` - Remove validate_cert
2. ✅ Copy updated files from Windows machine
3. ✅ Clean state and restart

## Recommended Approach

**I recommend Option A (Fix Certificate Trust)** because:
- ✅ Proper security
- ✅ Matches production setup
- ✅ No code changes needed
- ✅ Just clean state and regenerate certificates

**Option B (Disable Validation)** should only be used for:
- ⚠️ Quick testing
- ⚠️ Debugging certificate issues
- ⚠️ Not for production

## Next Steps

1. **Update local files** (I'll help you with this)
2. **Copy to remote machine**
3. **Revert the broken cloud_verifier_tornado.py change**
4. **Clean state and restart** (Option A)
5. **Test**

Let me know which option you prefer, and I'll create the exact files you need!
