# Fix: validate_cert Error in cloud_verifier_tornado.py

## The Problem

On your remote Linux machine, you modified `keylime/keylime/cloud_verifier_tornado.py` around line 2143:

**WRONG (Current on Remote):**
```python
request_kwargs = {'timeout': 300.0, 'validate_cert': False}
```

**Error:**
```
WARNING:keylime.verifier:Unified-Identity: Quote request to agent API v2.2 failed: 
request() got an unexpected keyword argument 'validate_cert'
```

## Why It Fails

The `validate_cert` parameter **does not exist** in tornado's HTTP client. This causes the Verifier to crash when trying to fetch quotes from the agent.

## The Fix

You need to **revert this change** on your remote Linux machine.

### Option 1: Use Git (Recommended)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Check if you have uncommitted changes
git status

# Revert the file to original
git checkout keylime/keylime/cloud_verifier_tornado.py

# Verify it's reverted
git diff keylime/keylime/cloud_verifier_tornado.py
# Should show no differences
```

### Option 2: Manual Edit

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
nano keylime/keylime/cloud_verifier_tornado.py
```

Find line ~2143 (search for `validate_cert`):

**BEFORE (WRONG):**
```python
async def _make_request() -> Any:
    # Only pass ssl_context if using HTTPS
    request_kwargs = {'timeout': 300.0, 'validate_cert': False}  # ❌ WRONG
    if use_https and ssl_context:
        request_kwargs['context'] = ssl_context
    return await tornado_requests.request('GET', quote_url, **request_kwargs)
```

**AFTER (CORRECT):**
```python
async def _make_request() -> Any:
    # Only pass ssl_context if using HTTPS
    request_kwargs = {'timeout': agent_quote_timeout}  # ✅ CORRECT
    if use_https and ssl_context:
        request_kwargs['context'] = ssl_context
    return await tornado_requests.request('GET', quote_url, **request_kwargs)
```

**Key changes:**
1. Remove `'validate_cert': False` - this parameter doesn't exist
2. Use `agent_quote_timeout` variable instead of hardcoded `300.0`
3. The timeout is already configured in `verifier.conf.minimal` as `agent_quote_timeout_seconds = 300`

### Option 3: Use sed Command

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Find the line with validate_cert
grep -n "validate_cert" keylime/keylime/cloud_verifier_tornado.py

# If found, replace it
sed -i "s/request_kwargs = {'timeout': 300.0, 'validate_cert': False}/request_kwargs = {'timeout': agent_quote_timeout}/" keylime/keylime/cloud_verifier_tornado.py

# Verify the change
grep -A 2 "request_kwargs = " keylime/keylime/cloud_verifier_tornado.py | head -5
```

## Why You Don't Need validate_cert=False

### The Real Issue Was Certificate Mismatch

You tried to disable certificate validation because the Verifier was rejecting the Agent's certificate. But the **root cause** was:

1. You cleaned `/tmp/spire-*` and `/opt/spire/data/*`
2. SPIRE regenerated new certificates
3. But Keylime still had old certificates in `keylime/cv_ca`
4. **Mismatch** → SSL errors

### The Proper Fix

**Clean ALL state** so certificates are regenerated and match:

```bash
# Stop everything
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true

# Clean ALL state (including Keylime certificates)
rm -rf /tmp/keylime-agent
rm -rf /tmp/spire-*
rm -rf /opt/spire/data/*
rm -rf keylime/cv_ca  # ← This is the key!
rm -rf keylime/*.db

# Restart - this regenerates matching certificates
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

## If You Really Need to Disable Certificate Validation (Not Recommended)

If you absolutely must disable certificate validation for testing, here's the **correct** way:

```python
import ssl

async def _make_request() -> Any:
    request_kwargs = {'timeout': agent_quote_timeout}
    
    if use_https:
        if ssl_context:
            # Use provided SSL context (with validation)
            request_kwargs['context'] = ssl_context
        else:
            # Create SSL context without validation (INSECURE - testing only)
            ssl_context_no_verify = ssl.create_default_context()
            ssl_context_no_verify.check_hostname = False
            ssl_context_no_verify.verify_mode = ssl.CERT_NONE
            request_kwargs['context'] = ssl_context_no_verify
    
    return await tornado_requests.request('GET', quote_url, **request_kwargs)
```

**But you shouldn't need this** if you clean state properly!

## Verification

After reverting the change:

```bash
# Restart verifier
pkill keylime-verifier
cd ~/dhanush/hybrid-cloud-poc-backup
./test_complete_control_plane.sh --no-pause

# Check logs - should NOT see validate_cert error
tail -50 /tmp/keylime-verifier.log | grep -i "validate_cert"
# Should show nothing

# Should see successful startup
tail -50 /tmp/keylime-verifier.log | grep -i "Starting Cloud Verifier"
# Should show: INFO:keylime.verifier:Starting Cloud Verifier (tornado) on port 8881
```

## Summary

| What You Did | Why It Failed | What to Do |
|--------------|---------------|------------|
| Added `'validate_cert': False` | Parameter doesn't exist in tornado | **Revert the change** |
| Tried to disable SSL validation | Wrong approach | **Clean state and regenerate certificates** |
| Hardcoded timeout to 300.0 | Should use config variable | **Use `agent_quote_timeout` variable** |

## Related Files

- `keylime/verifier.conf.minimal` - Already has `agent_quote_timeout_seconds = 300`
- `REMOTE_MACHINE_COMMANDS.md` - Complete fix procedure
- `SYNC_AND_FIX_GUIDE.md` - Explanation of all changes
