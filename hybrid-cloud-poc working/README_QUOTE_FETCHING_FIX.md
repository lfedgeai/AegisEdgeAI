# Quick Start: Fix Quote Fetching Issue

## Problem

Keylime Verifier gets HTTP 599 errors when fetching quotes from rust-keylime agent:
```
ERROR: missing required field: data.quote (agent retrieval failed)
```

## Quick Fix (Run This First)

```bash
# Make scripts executable
chmod +x fix-quote-fetching.sh test-agent-quote-endpoint.sh

# Run automated diagnostic and fix
./fix-quote-fetching.sh
```

This will:
1. Run diagnostics to identify the issue
2. Test tornado connection with and without mTLS
3. Determine if timeout or mTLS is the problem
4. Offer to apply fixes automatically

## What Was Changed

### 1. Increased Timeout

**File**: `keylime/verifier.conf.minimal`

Added:
```ini
agent_quote_timeout_seconds = 60
```

This doubles the timeout from 30s to 60s.

### 2. Created Diagnostic Tools

- `test-agent-quote-endpoint.sh` - Tests agent connectivity
- `test-tornado-agent-connection.py` - Tests tornado HTTP client
- `fix-quote-fetching.sh` - Automated diagnostic and fix
- `TROUBLESHOOT_QUOTE_FETCHING.md` - Detailed troubleshooting guide

## Manual Testing

### Test 1: Check if Agent is Running

```bash
ps aux | grep keylime_agent
netstat -tln | grep 9002
```

### Test 2: Test HTTP Connection

```bash
curl -v http://127.0.0.1:9002/v2.4/quotes/identity?nonce=test123
```

### Test 3: Test Tornado Connection

```bash
# With mTLS
python3 test-tornado-agent-connection.py

# Without mTLS (HTTP)
python3 test-tornado-agent-connection.py --no-mtls
```

### Test 4: Check Logs

```bash
# Agent logs
tail -50 /tmp/rust-keylime-agent.log | grep -E "quote|GET|request"

# Verifier logs
tail -50 /tmp/keylime-verifier.log | grep -E "quote|599|timeout|connection"
```

## If Timeout Fix Doesn't Work

### Option A: Disable mTLS (Temporary Workaround)

If HTTP works but HTTPS fails:

```bash
# Edit agent config
nano rust-keylime/keylime-agent.conf
# Change: enable_agent_mtls = true → enable_agent_mtls = false

# Edit verifier config
nano keylime/verifier.conf.minimal
# Change: enable_agent_mtls = True → enable_agent_mtls = False

# Restart services
pkill -f keylime_agent
pkill -f keylime_verifier
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

### Option B: Increase Timeout Further

```bash
# Edit verifier config
nano keylime/verifier.conf.minimal
# Change: agent_quote_timeout_seconds = 60 → agent_quote_timeout_seconds = 120

# Restart verifier
pkill -f keylime_verifier
./test_complete_control_plane.sh --no-pause
```

## Verification

After applying fixes:

```bash
# Run full test
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause

# Check if quotes are being fetched successfully
grep "Successfully retrieved quote" /tmp/keylime-verifier.log
```

## Important Notes

1. **System Still Works**: The system continues to function despite these errors because SPIRE Agent includes the quote in the SovereignAttestation payload. This is an optimization issue, not a critical failure.

2. **Root Cause**: The issue is likely SSL context incompatibility between tornado's HTTP client and rust-keylime agent's actix-web server.

3. **Long-term Fix**: Consider replacing tornado HTTP client with Python's `requests` library for agent communication.

## Documentation

- `TROUBLESHOOT_QUOTE_FETCHING.md` - Comprehensive troubleshooting guide
- `QUOTE_FETCHING_INVESTIGATION.md` - Technical analysis and investigation summary

## Support

If issues persist after trying these fixes:

1. Run diagnostics: `./fix-quote-fetching.sh`
2. Check logs for detailed errors
3. Try disabling mTLS as a workaround
4. Review `TROUBLESHOOT_QUOTE_FETCHING.md` for advanced solutions
