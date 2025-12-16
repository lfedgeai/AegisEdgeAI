# Quote Fetching Investigation Summary

## Issue

Keylime Verifier cannot fetch TPM quotes from rust-keylime agent, resulting in HTTP 599 errors:
```
ERROR: missing required field: data.quote (agent retrieval failed)
```

## Analysis

### Code Review

Reviewed `keylime/keylime/cloud_verifier_tornado.py` (lines 2100-2300):

1. **Connection Method**: Verifier uses tornado's async HTTP client with custom SSL context
2. **Timeout**: Default 30 seconds (configurable via `agent_quote_timeout_seconds`)
3. **mTLS**: Enabled by default, falls back to HTTP if SSL context fails
4. **API Versions**: Tries v2.2, v2.4, v1.0 in sequence
5. **Error Handling**: HTTP 599 indicates connection timeout or SSL handshake failure

### Root Causes (Hypotheses)

1. **SSL Context Incompatibility**: Tornado's SSL implementation may not be compatible with rust-keylime agent's actix-web server
2. **Timeout Too Short**: 30 seconds may not be sufficient for quote generation
3. **Certificate Issues**: mTLS certificate validation may be failing silently
4. **Network Issues**: Agent may not be listening properly on port 9002

## Fixes Applied

### 1. Increased Timeout

**File**: `keylime/verifier.conf.minimal`

Added:
```ini
# Timeout for fetching quotes from agent (in seconds)
agent_quote_timeout_seconds = 60
```

This doubles the timeout from 30s to 60s, giving the agent more time to respond.

### 2. Created Diagnostic Tools

#### a. `test-agent-quote-endpoint.sh`
Bash script that checks:
- Agent listening on port 9002
- HTTP connection (no mTLS)
- HTTPS connection (with mTLS)
- Agent and verifier configuration
- Recent logs for errors

Usage:
```bash
chmod +x test-agent-quote-endpoint.sh
./test-agent-quote-endpoint.sh
```

#### b. `test-tornado-agent-connection.py`
Python script that replicates the exact connection method used by the verifier:
- Uses tornado HTTP client
- Tests with and without mTLS
- Tries different API versions
- Shows detailed error messages

Usage:
```bash
# Test with mTLS
python3 test-tornado-agent-connection.py

# Test without mTLS
python3 test-tornado-agent-connection.py --no-mtls
```

#### c. `fix-quote-fetching.sh`
Automated fix script that:
- Runs diagnostics
- Tests tornado connection
- Determines if mTLS or HTTP works
- Offers to disable mTLS if needed
- Shows current configuration

Usage:
```bash
chmod +x fix-quote-fetching.sh
./fix-quote-fetching.sh
```

### 3. Created Documentation

#### a. `TROUBLESHOOT_QUOTE_FETCHING.md`
Comprehensive troubleshooting guide with:
- Problem description
- Root cause analysis
- Diagnostic steps
- Multiple solution approaches
- Verification steps
- Current status and next steps

#### b. `QUOTE_FETCHING_INVESTIGATION.md` (this file)
Summary of investigation and fixes applied.

## Next Steps for User

### Immediate Actions

1. **Run diagnostics**:
   ```bash
   ./fix-quote-fetching.sh
   ```

2. **Check if timeout fix is sufficient**:
   ```bash
   ./test_complete_control_plane.sh --no-pause
   ./test_complete.sh --no-pause
   grep "Successfully retrieved quote" /tmp/keylime-verifier.log
   ```

3. **If still failing, test connection directly**:
   ```bash
   python3 test-tornado-agent-connection.py
   python3 test-tornado-agent-connection.py --no-mtls
   ```

### If Timeout Fix Doesn't Work

#### Option A: Disable mTLS (Quick Fix)

If HTTP works but HTTPS fails, disable agent mTLS:

**In `rust-keylime/keylime-agent.conf`:**
```ini
enable_agent_mtls = false
```

**In `keylime/verifier.conf.minimal`:**
```ini
enable_agent_mtls = False
```

Then restart services.

#### Option B: Fix SSL Context (Proper Fix)

Investigate and fix the SSL context incompatibility:

1. Check `keylime/keylime/web_util.py` function `generate_agent_tls_context()`
2. Try more permissive SSL settings
3. Disable hostname verification for localhost
4. Consider using a different HTTP client (requests, httpx)

#### Option C: Replace HTTP Client

Modify verifier to use Python's `requests` library instead of tornado for agent communication. This would require code changes in `cloud_verifier_tornado.py`.

## System Impact

**Important**: The system continues to function despite these errors because:
- SPIRE Agent includes the quote in the SovereignAttestation payload
- The verifier receives the quote from SPIRE Server, not directly from the agent
- This is an optimization issue, not a critical failure

However, fixing this is important for:
- Proper on-demand quote verification
- Reduced payload size in attestation
- Better separation of concerns
- Compliance with Keylime architecture

## Technical Details

### Tornado HTTP Client

The verifier uses tornado's async HTTP client:
```python
async def _make_request() -> Any:
    request_kwargs = {'timeout': agent_quote_timeout}
    if use_https and ssl_context:
        request_kwargs['context'] = ssl_context
    return await tornado_requests.request('GET', quote_url, **request_kwargs)
```

### SSL Context Generation

```python
ssl_context = web_util.generate_agent_tls_context('verifier', agent_mtls_cert, logger=logger)
```

This may be where the incompatibility occurs.

### Error Code 599

HTTP 599 is tornado's custom error code for:
- Connection timeout
- SSL/TLS handshake failure
- Network unreachable
- Connection refused (after timeout)

## Files Modified

1. `keylime/verifier.conf.minimal` - Added `agent_quote_timeout_seconds = 60`

## Files Created

1. `test-agent-quote-endpoint.sh` - Diagnostic bash script
2. `test-tornado-agent-connection.py` - Tornado connection test
3. `fix-quote-fetching.sh` - Automated fix script
4. `TROUBLESHOOT_QUOTE_FETCHING.md` - Troubleshooting guide
5. `QUOTE_FETCHING_INVESTIGATION.md` - This summary

## Conclusion

The timeout increase should resolve the issue if the problem is simply that the agent needs more time to respond. If the issue persists, the diagnostic tools will help identify whether it's an mTLS/SSL issue or a deeper network problem.

The user should run `./fix-quote-fetching.sh` to diagnose and potentially fix the issue automatically.
