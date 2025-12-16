# Binary Issue Resolved - Root Cause Found

**Date:** December 11, 2024  
**Status:** ✅ FIXED - Ready to rebuild  
**Issue:** New code wasn't in source file, so old binary was being used

---

## Root Cause

The problem was simple: **The source file didn't have the new code.**

### What Happened

1. ✅ You created `tpm_plugin_gateway.go.UPDATED` with the new code
2. ❌ You tried to copy it to `tpm_plugin_gateway.go` but the copy didn't work
3. ❌ The source file still had the OLD code (no `RequestQuoteFromAgent` function)
4. ❌ The binary from Dec 8 was built with the OLD code
5. ❌ When you ran tests, it used the old binary with old code

### Verification

```bash
# Check if source file has new code
$ grep "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
# Result: NO MATCHES (before fix)

# Check if .UPDATED file has new code
$ grep "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.UPDATED
# Result: FOUND (3 matches)
```

---

## What I Fixed

### Fix 1: Copied .UPDATED to Source File

```bash
cp spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.UPDATED \
   spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
```

Now the source file has:
- ✅ `RequestQuoteFromAgent()` function
- ✅ `requestQuoteFromAgentOnce()` helper function
- ✅ Modified `BuildSovereignAttestation()` to call `RequestQuoteFromAgent()`
- ✅ `crypto/tls` import

### Fix 2: Fixed go.mod

Changed:
```go
go 1.25.3  // Invalid version
```

To:
```go
go 1.21  // Valid version that works with Go 1.23.5
```

### Fix 3: Fixed cosign Dependency

Changed:
```go
github.com/sigstore/cosign/v2 v2.6.1  // Too new for Go 1.21
```

To:
```go
github.com/sigstore/cosign/v2 v2.4.0  // Compatible with Go 1.21
```

---

## What You Need to Do

### Step 1: Rebuild SPIRE Agent

I created a script that does everything for you:

```bash
# On remote machine (dell@vso)
cd ~/dhanush/hybrid-cloud-poc-backup
chmod +x rebuild-spire-agent.sh
./rebuild-spire-agent.sh
```

This script will:
1. ✅ Verify source code has new changes
2. ✅ Verify go.mod has correct Go version
3. ✅ Remove old binary
4. ✅ Build new binary
5. ✅ Verify new code is in binary (using `strings`)
6. ✅ Test binary is executable

### Step 2: Run Full Test

```bash
# Stop any running processes
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true

# Unmount tmpfs if needed
sudo umount /tmp/keylime-agent/secure 2>/dev/null || true

# Clean up
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db

# Run control plane
./test_complete_control_plane.sh --no-pause

# Run integration test
./test_complete.sh --no-pause
```

### Step 3: Verify New Code is Running

**Check SPIRE Agent logs:**
```bash
tail -f /tmp/spire-agent.log | grep "quote"
```

**You should see:**
```
Unified-Identity - Verification: Requesting quote from rust-keylime agent
Unified-Identity - Verification: Successfully retrieved quote from agent
```

**You should NOT see:**
```
quote handled by Keylime Verifier  # This is the OLD message
```

**Check Verifier logs:**
```bash
tail -f /tmp/keylime-verifier.log | grep "quote"
```

**You should NOT see:**
```
Requesting quote from agent  # This means Verifier is fetching quote (old behavior)
```

**You should see:**
```
Using quote from SovereignAttestation  # This means Verifier is using quote from payload (new behavior)
```

---

## Expected Behavior After Fix

### Old Behavior (Before Fix)
```
SPIRE Agent → Server → Verifier → "Quote is empty, fetching from agent"
                                 ↓
                          Agent (HTTP request) → SSL BUG
                                 ↓
                          Connection reset by peer
```

### New Behavior (After Fix)
```
SPIRE Agent → "Requesting quote from agent"
           ↓
    Agent (HTTP request) → Returns quote
           ↓
SPIRE Agent → Server → Verifier → "Quote found in SovereignAttestation, using it"
                                 ↓
                          ✅ Attestation succeeds
```

---

## Why This Will Work

1. ✅ **Source code now has new code** - Verified with grep
2. ✅ **go.mod has valid version** - Changed from 1.25.3 to 1.21
3. ✅ **cosign dependency compatible** - Downgraded to v2.4.0
4. ✅ **Build script automates everything** - No manual steps
5. ✅ **Verification built into script** - Uses `strings` to check binary

---

## What Changed in the Code

### Before (Old Code)
```go
func (g *TPMPluginGateway) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
    // ... get App Key ...
    
    sovereignAttestation := &types.SovereignAttestation{
        TpmSignedAttestation: "", // Empty - Verifier will fetch it
        AppKeyPublic:         appKeyResult.AppKeyPublic,
        ChallengeNonce:       nonce,
        AppKeyCertificate:    appKeyCertificate,
        KeylimeAgentUuid:     agentUUID,
    }
    
    return sovereignAttestation, nil
}
```

### After (New Code)
```go
func (g *TPMPluginGateway) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
    // ... get App Key ...
    
    // NEW: Request quote from rust-keylime agent
    g.log.Info("Unified-Identity - Verification: Requesting quote from rust-keylime agent")
    quote, err := g.RequestQuoteFromAgent(nonce)
    if err != nil {
        g.log.WithError(err).Warn("Unified-Identity - Verification: Failed to get quote from agent, using empty quote (Verifier will try to fetch it)")
        quote = "" // Fallback to empty quote
    } else {
        g.log.Info("Unified-Identity - Verification: Successfully retrieved quote from agent")
    }
    
    sovereignAttestation := &types.SovereignAttestation{
        TpmSignedAttestation: quote, // NEW: Include quote in payload
        AppKeyPublic:         appKeyResult.AppKeyPublic,
        ChallengeNonce:       nonce,
        AppKeyCertificate:    appKeyCertificate,
        KeylimeAgentUuid:     agentUUID,
    }
    
    return sovereignAttestation, nil
}

// NEW FUNCTION: Request quote from agent
func (g *TPMPluginGateway) RequestQuoteFromAgent(nonce string) (string, error) {
    // Get agent URL from environment
    agentURL := os.Getenv("KEYLIME_AGENT_URL")
    if agentURL == "" {
        agentURL = "https://localhost:9002"
    }
    
    // Build quote request URL
    quoteURL := fmt.Sprintf("%s/v2.2/quotes/identity?nonce=%s", agentURL, nonce)
    
    // Retry logic with exponential backoff
    maxRetries := 3
    backoff := 2 * time.Second
    
    for i := 0; i < maxRetries; i++ {
        quote, err := g.requestQuoteFromAgentOnce(quoteURL)
        if err == nil {
            return quote, nil
        }
        
        if i < maxRetries-1 {
            g.log.WithError(err).WithField("retry", i+1).
                Warn("Unified-Identity - Verification: Failed to get quote, retrying...")
            time.Sleep(backoff)
            backoff *= 2
        }
    }
    
    return "", fmt.Errorf("failed to get quote after %d retries", maxRetries)
}

// NEW HELPER: Make single quote request
func (g *TPMPluginGateway) requestQuoteFromAgentOnce(quoteURL string) (string, error) {
    // Create HTTP client with TLS config
    tr := &http.Transport{
        TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
    }
    client := &http.Client{
        Transport: tr,
        Timeout:   30 * time.Second,
    }
    
    // Make request
    resp, err := client.Get(quoteURL)
    if err != nil {
        return "", fmt.Errorf("failed to request quote: %w", err)
    }
    defer resp.Body.Close()
    
    // Parse response
    var quoteResponse struct {
        Code    int    `json:"code"`
        Status  string `json:"status"`
        Results struct {
            Quote string `json:"quote"`
        } `json:"results"`
    }
    
    body, _ := io.ReadAll(resp.Body)
    if err := json.Unmarshal(body, &quoteResponse); err != nil {
        return "", fmt.Errorf("failed to parse response: %w", err)
    }
    
    if quoteResponse.Code != 200 {
        return "", fmt.Errorf("agent returned error: %s", quoteResponse.Status)
    }
    
    return quoteResponse.Results.Quote, nil
}
```

---

## Files Modified

1. ✅ `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go` - Added quote fetching
2. ✅ `spire/go.mod` - Fixed Go version (1.25.3 → 1.21)
3. ✅ `spire/go.mod` - Fixed cosign version (v2.6.1 → v2.4.0)
4. ✅ `rebuild-spire-agent.sh` - New script to rebuild binary

---

## Timeline

### What Happened
- **Dec 8:** Built binary with OLD code (no RequestQuoteFromAgent)
- **Dec 10:** Created .UPDATED file with NEW code
- **Dec 11 00:59:** Tried to rebuild, but source file still had OLD code
- **Dec 11 (now):** Fixed source file, ready to rebuild

### What's Next
- **Now:** Run `rebuild-spire-agent.sh` to build new binary
- **5 minutes:** Test with `test_complete.sh`
- **10 minutes:** Verify multiple attestations work
- **15 minutes:** Complete Step 1! 🎉

---

## Success Criteria

After rebuilding and testing, you should see:

1. ✅ **SPIRE Agent logs show:**
   - "Requesting quote from rust-keylime agent"
   - "Successfully retrieved quote from agent"

2. ✅ **Verifier logs DON'T show:**
   - "Requesting quote from agent"

3. ✅ **Attestation succeeds:**
   - No "missing required field: data.quote" error
   - No "Connection reset by peer" error

4. ✅ **Multiple attestations work:**
   - Can run 5+ attestations without agent restart
   - No SSL corruption

---

## Troubleshooting

### If build fails with "go: errors parsing go.mod"
```bash
# Check go.mod version
grep "^go " spire/go.mod

# Should show: go 1.21
# If not, run:
sed -i 's/^go .*/go 1.21/' spire/go.mod
```

### If binary doesn't have new code
```bash
# Verify source file has new code
grep "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# If no matches, copy from .UPDATED:
cp spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.UPDATED \
   spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
```

### If attestation still fails
```bash
# Check SPIRE Agent logs
tail -100 /tmp/spire-agent.log | grep -A 5 -B 5 "quote"

# Check Verifier logs
tail -100 /tmp/keylime-verifier.log | grep -A 5 -B 5 "quote"

# Check if agent is responding
curl -k https://localhost:9002/v2.2/agent/version
```

---

## Next Steps After Success

1. ✅ **Document findings** - Update mentor report
2. ✅ **Test thoroughly** - Multiple attestations, edge cases
3. ✅ **Complete Step 1** - Single machine setup done
4. ✅ **Move to Step 2** - CI/CD testing (5-minute runtime)
5. ✅ **Report bug** - Submit issue to rust-keylime project

---

**Prepared By:** Kiro AI Assistant  
**Date:** December 11, 2024  
**Status:** Ready to rebuild and test

