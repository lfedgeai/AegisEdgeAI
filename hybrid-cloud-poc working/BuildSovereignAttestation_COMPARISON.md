# BuildSovereignAttestation Function - OLD vs NEW

## Location
**File:** `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go`  
**Line:** Around 324-378

---

## OLD VERSION (What you have now)

```go
func (g *TPMPluginGateway) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
	g.log.Info("Unified-Identity - Verification: Building real SovereignAttestation via TPM plugin")

	// Get App Key public key via /get-app-key endpoint
	var appKeyResult AppKeyResult

	if err := g.httpRequest("POST", "/get-app-key", map[string]interface{}{}, &appKeyResult); err != nil {
		return nil, fmt.Errorf("failed to get App Key: %w", err)
	}

	if appKeyResult.Status != "success" || appKeyResult.AppKeyPublic == "" {
		return nil, fmt.Errorf("App Key not available: status=%s", appKeyResult.Status)
	}

	// Request App Key certificate (delegated certification)
	var appKeyCertificate []byte
	var agentUUID string
	cert, uuid, err := g.RequestCertificate(appKeyResult.AppKeyPublic, "", nonce)
	if err != nil {
		g.log.WithError(err).Warn("Unified-Identity - Verification: Failed to get App Key certificate, continuing without certificate")
	} else {
		appKeyCertificate = cert
		agentUUID = uuid
		g.log.Info("Unified-Identity - Verification: App Key certificate obtained via delegated certification (App Key signed by AK)")
	}

	// Build SovereignAttestation
	// Quote is empty since Keylime Verifier will request it directly from rust-keylime agent
	sovereignAttestation := &types.SovereignAttestation{
		TpmSignedAttestation: "", // ❌ Empty - Keylime Verifier will request quote from rust-keylime agent
		AppKeyPublic:         appKeyResult.AppKeyPublic,
		ChallengeNonce:       nonce,
		AppKeyCertificate:    appKeyCertificate,
		KeylimeAgentUuid:     agentUUID,
	}

	g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully (quote handled by Keylime Verifier)")

	return sovereignAttestation, nil
}
```

---

## NEW VERSION (What you need)

```go
func (g *TPMPluginGateway) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
	g.log.Info("Unified-Identity - Verification: Building real SovereignAttestation via TPM plugin")

	// Get App Key public key via /get-app-key endpoint
	var appKeyResult AppKeyResult

	if err := g.httpRequest("POST", "/get-app-key", map[string]interface{}{}, &appKeyResult); err != nil {
		return nil, fmt.Errorf("failed to get App Key: %w", err)
	}

	if appKeyResult.Status != "success" || appKeyResult.AppKeyPublic == "" {
		return nil, fmt.Errorf("App Key not available: status=%s", appKeyResult.Status)
	}

	// Request App Key certificate (delegated certification)
	var appKeyCertificate []byte
	var agentUUID string
	cert, uuid, err := g.RequestCertificate(appKeyResult.AppKeyPublic, "", nonce)
	if err != nil {
		g.log.WithError(err).Warn("Unified-Identity - Verification: Failed to get App Key certificate, continuing without certificate")
	} else {
		appKeyCertificate = cert
		agentUUID = uuid
		g.log.Info("Unified-Identity - Verification: App Key certificate obtained via delegated certification (App Key signed by AK)")
	}

	// ✅ NEW CODE: Request quote from rust-keylime agent
	// This avoids the Verifier having to fetch it later (which triggers SSL bug)
	g.log.Info("Unified-Identity - Verification: Requesting quote from rust-keylime agent")
	quote, err := g.RequestQuoteFromAgent(nonce)
	if err != nil {
		g.log.WithError(err).Warn("Unified-Identity - Verification: Failed to get quote from agent, using empty quote (Verifier will try to fetch it)")
		quote = "" // Fallback to empty quote (Verifier will try to fetch it)
	} else {
		g.log.Info("Unified-Identity - Verification: Successfully retrieved quote from agent")
	}

	// Build SovereignAttestation with quote included
	sovereignAttestation := &types.SovereignAttestation{
		TpmSignedAttestation: quote, // ✅ Include quote in attestation payload (was empty before)
		AppKeyPublic:         appKeyResult.AppKeyPublic,
		ChallengeNonce:       nonce,
		AppKeyCertificate:    appKeyCertificate,
		KeylimeAgentUuid:     agentUUID,
	}

	if quote != "" {
		g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully with quote included")
	} else {
		g.log.Warn("Unified-Identity - Verification: SovereignAttestation built without quote (Verifier will fetch it)")
	}

	return sovereignAttestation, nil
}
```

---

## What Changed (Summary)

### ADDED (Lines to add after certificate request):

```go
// *** NEW CODE: Request quote from rust-keylime agent ***
// This avoids the Verifier having to fetch it later (which triggers SSL bug)
g.log.Info("Unified-Identity - Verification: Requesting quote from rust-keylime agent")
quote, err := g.RequestQuoteFromAgent(nonce)
if err != nil {
	g.log.WithError(err).Warn("Unified-Identity - Verification: Failed to get quote from agent, using empty quote (Verifier will try to fetch it)")
	quote = "" // Fallback to empty quote (Verifier will try to fetch it)
} else {
	g.log.Info("Unified-Identity - Verification: Successfully retrieved quote from agent")
}
```

### CHANGED (In SovereignAttestation struct):

**OLD:**
```go
TpmSignedAttestation: "", // Empty - Keylime Verifier will request quote from rust-keylime agent
```

**NEW:**
```go
TpmSignedAttestation: quote, // Include quote in attestation payload (was empty before)
```

### CHANGED (Final log message):

**OLD:**
```go
g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully (quote handled by Keylime Verifier)")

return sovereignAttestation, nil
```

**NEW:**
```go
if quote != "" {
	g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully with quote included")
} else {
	g.log.Warn("Unified-Identity - Verification: SovereignAttestation built without quote (Verifier will fetch it)")
}

return sovereignAttestation, nil
```

---

## How to Apply

### Option 1: Replace Entire Function

1. Open `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go`
2. Find the `BuildSovereignAttestation` function (around line 324)
3. Delete everything from `func (g *TPMPluginGateway) BuildSovereignAttestation` to the closing `}`
4. Copy the NEW VERSION from above and paste it

### Option 2: Make Changes Manually

1. Find this line (around line 360):
   ```go
   g.log.Info("Unified-Identity - Verification: App Key certificate obtained via delegated certification (App Key signed by AK)")
   }
   ```

2. After that closing brace `}`, ADD these lines:
   ```go
   
   // *** NEW CODE: Request quote from rust-keylime agent ***
   // This avoids the Verifier having to fetch it later (which triggers SSL bug)
   g.log.Info("Unified-Identity - Verification: Requesting quote from rust-keylime agent")
   quote, err := g.RequestQuoteFromAgent(nonce)
   if err != nil {
       g.log.WithError(err).Warn("Unified-Identity - Verification: Failed to get quote from agent, using empty quote (Verifier will try to fetch it)")
       quote = "" // Fallback to empty quote (Verifier will try to fetch it)
   } else {
       g.log.Info("Unified-Identity - Verification: Successfully retrieved quote from agent")
   }
   ```

3. Find this line (around line 368):
   ```go
   TpmSignedAttestation: "", // Empty - Keylime Verifier will request quote from rust-keylime agent
   ```

4. CHANGE it to:
   ```go
   TpmSignedAttestation: quote, // Include quote in attestation payload (was empty before)
   ```

5. Find this line (around line 375):
   ```go
   g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully (quote handled by Keylime Verifier)")
   
   return sovereignAttestation, nil
   ```

6. REPLACE it with:
   ```go
   if quote != "" {
       g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully with quote included")
   } else {
       g.log.Warn("Unified-Identity - Verification: SovereignAttestation built without quote (Verifier will fetch it)")
   }
   
   return sovereignAttestation, nil
   ```

---

## Verify Your Changes

After making changes, search for these strings in the file:

```bash
# Should find the new code
grep "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# Should find the changed line
grep "TpmSignedAttestation: quote" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# Should find the new log message
grep "with quote included" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
```

All three should return results if you made the changes correctly.

---

## Important Note

This function calls `g.RequestQuoteFromAgent(nonce)` which is a NEW function you also need to add. Make sure you've added:

1. ✅ `crypto/tls` import (line 19)
2. ✅ This `BuildSovereignAttestation` function (modified)
3. ✅ `RequestQuoteFromAgent` function (new, add after this function)
4. ✅ `requestQuoteFromAgentOnce` function (new, add after RequestQuoteFromAgent)

See the complete file: `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.UPDATED`
