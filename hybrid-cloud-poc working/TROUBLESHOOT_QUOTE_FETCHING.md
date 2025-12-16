# Troubleshooting: Keylime Verifier Cannot Fetch Quotes from rust-keylime Agent

## Problem

Keylime Verifier gets HTTP 599 errors when trying to fetch TPM quotes from rust-keylime agent:
```
ERROR: missing required field: data.quote (agent retrieval failed)
```

## Root Cause

The Keylime Verifier uses tornado's async HTTP client to fetch quotes from the rust-keylime agent. The HTTP 599 error indicates a connection timeout or SSL/TLS handshake failure. This is likely due to:

1. **SSL Context Incompatibility**: Tornado's SSL context may not be compatible with rust-keylime agent's actix-web server
2. **Timeout Too Short**: Default timeout (30s) may not be sufficient
3. **Certificate Issues**: mTLS certificate validation may be failing
4. **Network/Port Issues**: Agent may not be listening properly

## Diagnostic Steps

### Step 1: Run Diagnostic Script

```bash
chmod +x test-agent-quote-endpoint.sh
./test-agent-quote-endpoint.sh
```

This will check:
- If agent is listening on port 9002
- HTTP connection (no mTLS)
- HTTPS connection (with mTLS)
- Agent and verifier configuration
- Recent logs for errors

### Step 2: Test Tornado Connection

```bash
# Test with mTLS (default)
python3 test-tornado-agent-connection.py

# Test without mTLS (HTTP fallback)
python3 test-tornado-agent-connection.py --no-mtls
```

This replicates the exact connection method used by the verifier.

### Step 3: Check Agent Logs

```bash
tail -100 /tmp/rust-keylime-agent.log | grep -E "quote|GET|request|error"
```

Look for:
- Quote requests from verifier
- Connection errors
- SSL/TLS handshake failures

### Step 4: Check Verifier Logs

```bash
tail -100 /tmp/keylime-verifier.log | grep -E "quote|599|timeout|connection|agent retrieval"
```

Look for:
- Connection timeout errors
- SSL context errors
- HTTP 599 errors

## Solutions

### Solution 1: Increase Timeout (Already Applied)

The verifier config now includes:
```ini
agent_quote_timeout_seconds = 60
```

This gives the agent more time to respond.

### Solution 2: Disable Agent mTLS (Temporary Workaround)

If mTLS is causing issues, you can temporarily disable it:

**In `rust-keylime/keylime-agent.conf`:**
```ini
enable_agent_mtls = false
```

**In `keylime/verifier.conf.minimal`:**
```ini
enable_agent_mtls = False
```

Then restart both services:
```bash
pkill -f keylime_agent
pkill -f keylime_verifier

# Restart control plane
./test_complete_control_plane.sh --no-pause

# Restart agent services
./test_complete.sh --no-pause
```

### Solution 3: Fix SSL Context (Recommended)

The issue may be in how tornado builds the SSL context. Check `keylime/keylime/web_util.py` function `generate_agent_tls_context()`.

Potential fixes:
1. Use a more permissive SSL context
2. Disable hostname verification for localhost
3. Use a different HTTP client library (e.g., requests, httpx)

### Solution 4: Use Direct HTTP Client

Modify the verifier to use Python's `requests` library instead of tornado for agent communication:

```python
import requests

# Instead of tornado_requests.request()
response = requests.get(
    quote_url,
    timeout=agent_quote_timeout,
    verify=False,  # or path to CA cert
    cert=(client_cert, client_key) if use_mtls else None
)
```

### Solution 5: Check Network Configuration

Ensure the agent is listening on the correct interface:

```bash
# Check if agent is listening
netstat -tln | grep 9002

# Should show:
# tcp        0      0 127.0.0.1:9002          0.0.0.0:*               LISTEN
```

If not listening, check agent config:
```ini
ip = "127.0.0.1"
port = 9002
```

## Verification

After applying fixes, verify the connection works:

```bash
# Test direct connection
curl -v http://127.0.0.1:9002/v2.4/quotes/identity?nonce=test123

# Run full test
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

Check logs for successful quote fetching:
```bash
grep "Successfully retrieved quote" /tmp/keylime-verifier.log
```

## Current Status

- ✓ Timeout increased to 60 seconds
- ⏳ Need to test if this resolves the issue
- ⏳ May need to disable mTLS or fix SSL context

## Next Steps

1. Run diagnostic scripts to identify exact failure point
2. Test with mTLS disabled to isolate SSL issues
3. If mTLS is the problem, fix SSL context or use different HTTP client
4. If timeout is the problem, increase further or optimize agent quote generation

## Notes

- The system continues to function despite these errors because SPIRE Agent includes the quote in the SovereignAttestation payload
- This is a verifier-side issue, not an agent-side issue
- The rust-keylime agent is working correctly and can generate quotes
- The issue is specifically with the verifier's HTTP client connecting to the agent
