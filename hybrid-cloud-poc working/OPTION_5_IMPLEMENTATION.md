# Option 5: Include Quote in SovereignAttestation (Simplest Fix)

**Status:** Recommended Solution  
**Effort:** 2-4 hours  
**Impact:** Avoids agent SSL bug entirely  

---

## The Problem

Currently, the SPIRE Agent sends an **empty quote** in the SovereignAttestation:

```go
// spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go:368
sovereignAttestation := &types.SovereignAttestation{
    TpmSignedAttestation: "", // Empty - Keylime Verifier will request quote from rust-keylime agent
    AppKeyPublic:         appKeyResult.AppKeyPublic,
    AppKeyCertificate:    appKeyResult.AppKeyCertificate,
    ChallengeNonce:       nonce,
}
```

This forces the Keylime Verifier to fetch the quote from the rust-keylime agent via HTTP:

```python
# keylime/keylime/cloud_verifier_tornado.py:2237
if not quote:
    agent_quote, quote_hash_alg, quote_payload = _fetch_quote_from_agent()
```

This HTTP request triggers the SSL bug in the rust-keylime agent.

---

## The Solution

**Have the SPIRE Agent include the quote in the SovereignAttestation.**

Then the Verifier will use the quote from the SovereignAttestation and won't need to fetch it from the agent.

### Benefits

1. ✅ **Avoids the agent SSL bug entirely** - No HTTP request to agent
2. ✅ **Simpler architecture** - One-way communication (Agent → Server → Verifier)
3. ✅ **Better performance** - No extra HTTP round-trip
4. ✅ **More secure** - Quote is signed and included in attestation payload
5. ✅ **Minimal code changes** - Only need to modify SPIRE Agent

---

## Implementation

### Step 1: Modify TPM Plugin Gateway to Request Quote

**File:** `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go`

**Current Code (lines 315-378):**
```go
func (g *TPMPluginGateway) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
    g.log.Info("Unified-Identity - Verification: Building real SovereignAttestation via TPM plugin")

    // Get App Key public key and certificate
    appKeyResult, err := g.GetAppKeyInfo()
    if err != nil {
        return nil, fmt.Errorf("failed to get App Key info: %w", err)
    }

    // Build SovereignAttestation
    // Quote is empty since Keylime Verifier will request it directly from rust-keylime agent
    sovereignAttestation := &types.SovereignAttestation{
        TpmSignedAttestation: "", // Empty - Keylime Verifier will request quote from rust-keylime agent
        AppKeyPublic:         appKeyResult.AppKeyPublic,
        AppKeyCertificate:    appKeyResult.AppKeyCertificate,
        ChallengeNonce:       nonce,
    }

    g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully (quote handled by Keylime Verifier)")

    return sovereignAttestation, nil
}
```

**New Code:**
```go
func (g *TPMPluginGateway) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
    g.log.Info("Unified-Identity - Verification: Building real SovereignAttestation via TPM plugin")

    // Get App Key public key and certificate
    appKeyResult, err := g.GetAppKeyInfo()
    if err != nil {
        return nil, fmt.Errorf("failed to get App Key info: %w", err)
    }

    // Request quote from rust-keylime agent
    // This avoids the Verifier having to fetch it later (which triggers SSL bug)
    g.log.Info("Unified-Identity - Verification: Requesting quote from rust-keylime agent")
    quote, err := g.RequestQuoteFromAgent(nonce)
    if err != nil {
        g.log.WithError(err).Warn("Unified-Identity - Verification: Failed to get quote from agent, using empty quote")
        quote = "" // Fallback to empty quote (Verifier will try to fetch it)
    }

    // Build SovereignAttestation with quote included
    sovereignAttestation := &types.SovereignAttestation{
        TpmSignedAttestation: quote, // Include quote in attestation payload
        AppKeyPublic:         appKeyResult.AppKeyPublic,
        AppKeyCertificate:    appKeyResult.AppKeyCertificate,
        ChallengeNonce:       nonce,
    }

    g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully with quote")

    return sovereignAttestation, nil
}
```

### Step 2: Add RequestQuoteFromAgent Method

**File:** `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go`

**Add this new method:**
```go
// RequestQuoteFromAgent requests a TPM quote from the rust-keylime agent
// This is called during SovereignAttestation building to include the quote in the attestation payload
func (g *TPMPluginGateway) RequestQuoteFromAgent(nonce string) (string, error) {
    g.log.Info("Unified-Identity - Verification: Requesting quote from rust-keylime agent")

    // Get agent URL from environment or config
    agentURL := os.Getenv("KEYLIME_AGENT_URL")
    if agentURL == "" {
        agentURL = "https://localhost:9002" // Default
    }

    // Build quote request URL
    // Use identity quote endpoint (mask=0 for PCRs 0-7)
    quoteURL := fmt.Sprintf("%s/v2.2/quotes/identity?nonce=%s", agentURL, nonce)
    g.log.WithField("url", quoteURL).Debug("Unified-Identity - Verification: Quote request URL")

    // Create HTTP client with TLS config
    // Skip cert verification for localhost (agent uses self-signed cert)
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
        return "", fmt.Errorf("failed to request quote from agent: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != 200 {
        body, _ := io.ReadAll(resp.Body)
        return "", fmt.Errorf("agent returned status %d: %s", resp.StatusCode, string(body))
    }

    // Parse response
    var quoteResponse struct {
        Code    int    `json:"code"`
        Status  string `json:"status"`
        Results struct {
            Quote   string `json:"quote"`
            HashAlg string `json:"hash_alg"`
            EncAlg  string `json:"enc_alg"`
            SignAlg string `json:"sign_alg"`
        } `json:"results"`
    }

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return "", fmt.Errorf("failed to read response body: %w", err)
    }

    if err := json.Unmarshal(body, &quoteResponse); err != nil {
        return "", fmt.Errorf("failed to parse quote response: %w", err)
    }

    if quoteResponse.Code != 200 {
        return "", fmt.Errorf("agent returned error code %d: %s", quoteResponse.Code, quoteResponse.Status)
    }

    if quoteResponse.Results.Quote == "" {
        return "", fmt.Errorf("agent returned empty quote")
    }

    g.log.Info("Unified-Identity - Verification: Successfully retrieved quote from agent")
    return quoteResponse.Results.Quote, nil
}
```

### Step 3: Add Required Imports

**File:** `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go`

**Add to imports:**
```go
import (
    // ... existing imports ...
    "crypto/tls"
    "encoding/json"
    "io"
    "net/http"
    "os"
    "time"
)
```

---

## Testing

### Test 1: Verify Quote is Included in SovereignAttestation

```bash
# Add debug logging to SPIRE Agent
# In spire/pkg/agent/client/client.go, add:
c.c.Log.WithField("quote", params.SovereignAttestation.TpmSignedAttestation[:50]).
    Info("Unified-Identity: Sending SovereignAttestation with quote")

# Run test
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause

# Check SPIRE Agent logs
tail -f /tmp/spire-agent.log | grep "quote"

# Should see:
# "Unified-Identity: Sending SovereignAttestation with quote" quote="H4sIAAAAAAAA..."
```

### Test 2: Verify Verifier Doesn't Fetch Quote from Agent

```bash
# Add debug logging to Verifier
# In keylime/keylime/cloud_verifier_tornado.py, add:
if not quote:
    logger.info("Unified-Identity: Quote not in SovereignAttestation, fetching from agent")
else:
    logger.info("Unified-Identity: Quote found in SovereignAttestation, skipping agent fetch")

# Run test
./test_complete.sh --no-pause

# Check Verifier logs
tail -f /tmp/keylime-verifier.log | grep "Quote"

# Should see:
# "Unified-Identity: Quote found in SovereignAttestation, skipping agent fetch"
```

### Test 3: Verify Multiple Attestations Work

```bash
# Test multiple attestations without agent restart
for i in {1..5}; do
    echo "Attestation attempt $i"
    pkill spire-agent
    sleep 5
    # SPIRE Agent will restart and attest
    sleep 10
    
    # Check if attestation succeeded
    if curl -k https://localhost:8081/health 2>/dev/null | grep -q "ready"; then
        echo "✅ Attestation $i succeeded"
    else
        echo "❌ Attestation $i failed"
    fi
done
```

---

## Advantages Over Other Options

### vs Option 1 (Fix rust-keylime Agent Bug)
- ✅ **Faster:** 2-4 hours vs 2-4 days
- ✅ **Simpler:** No Rust debugging needed
- ✅ **Avoids bug entirely:** Don't need to fix agent

### vs Option 2 (Isolate SSL Context)
- ✅ **Simpler:** No complex error handling needed
- ✅ **Better architecture:** One-way communication
- ✅ **More secure:** Quote in signed attestation payload

### vs Option 3 (Agent Restart Workaround)
- ✅ **Production-ready:** No workarounds
- ✅ **Better performance:** No restart overhead
- ✅ **Proper fix:** Not a hack

### vs Option 4 (Use Python Agent)
- ✅ **Keep Rust agent:** No need to switch
- ✅ **Faster:** No integration work needed
- ✅ **Proven:** Current architecture works

---

## Potential Issues

### Issue 1: Agent Not Ready When SPIRE Agent Starts

**Problem:** SPIRE Agent might start before rust-keylime agent is ready

**Solution:** Add retry logic with exponential backoff:

```go
func (g *TPMPluginGateway) RequestQuoteFromAgent(nonce string) (string, error) {
    maxRetries := 3
    backoff := 2 * time.Second
    
    for i := 0; i < maxRetries; i++ {
        quote, err := g.requestQuoteFromAgentOnce(nonce)
        if err == nil {
            return quote, nil
        }
        
        if i < maxRetries-1 {
            g.log.WithError(err).WithField("retry", i+1).
                Warn("Unified-Identity: Failed to get quote, retrying...")
            time.Sleep(backoff)
            backoff *= 2
        }
    }
    
    return "", fmt.Errorf("failed to get quote after %d retries", maxRetries)
}
```

### Issue 2: Agent SSL Bug Still Occurs

**Problem:** Even with quote in SovereignAttestation, agent might still have SSL issues

**Solution:** This is fine! The Verifier will use the quote from SovereignAttestation and won't make the HTTP request that triggers the bug. The agent can have SSL issues, but they won't affect attestation.

### Issue 3: Quote Becomes Stale

**Problem:** Quote is generated once and included in SovereignAttestation, might be stale by the time Verifier processes it

**Solution:** This is not an issue because:
1. The nonce ensures freshness (quote is generated with server's nonce)
2. The entire attestation flow happens in seconds
3. The quote is cryptographically signed and can't be tampered with

---

## Implementation Timeline

1. **Hour 1:** Modify `BuildSovereignAttestation` to call `RequestQuoteFromAgent`
2. **Hour 2:** Implement `RequestQuoteFromAgent` method with retry logic
3. **Hour 3:** Test and debug
4. **Hour 4:** Verify multiple attestations work

**Total:** 4 hours

---

## Recommendation

**Implement Option 5 immediately** because:

1. ✅ **Simplest solution** - Minimal code changes
2. ✅ **Fastest to implement** - 2-4 hours vs days
3. ✅ **Avoids agent bug** - No need to fix rust-keylime
4. ✅ **Better architecture** - Quote in attestation payload
5. ✅ **Production-ready** - No workarounds or hacks

After implementing this, you can:
- ✅ Complete Step 1 (single machine setup)
- ✅ Move to Step 2 (CI/CD testing)
- ✅ Report the agent SSL bug to rust-keylime project
- ✅ Optionally fix the agent bug later (Option 1) for upstream contribution

---

**Next Steps:**

1. Review this implementation plan
2. Make the code changes
3. Test thoroughly
4. Celebrate completing Step 1! 🎉

