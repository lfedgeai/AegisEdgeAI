// ============================================================================
// REPLACE THE ENTIRE BuildSovereignAttestation FUNCTION WITH THIS:
// ============================================================================
// Find this function in: spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
// It starts around line 324
// Replace everything from "func (g *TPMPluginGateway) BuildSovereignAttestation"
// until the closing brace "}" (before the next function)
// ============================================================================

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// BuildSovereignAttestation builds a real SovereignAttestation using the TPM plugin
// nonce: Challenge nonce from SPIRE Server
// Returns a fully populated SovereignAttestation with real TPM data
//
// Architecture Change (Verification):
// - SPIRE Agent now requests quote from rust-keylime agent and includes it in SovereignAttestation
// - This avoids the Verifier having to fetch the quote later (which triggers SSL bug in agent)
// - Quote is included in the attestation payload for better security and performance
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

	// Build SovereignAttestation with quote included
	sovereignAttestation := &types.SovereignAttestation{
		TpmSignedAttestation: quote, // Include quote in attestation payload (was empty before)
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

// ============================================================================
// END OF BuildSovereignAttestation FUNCTION
// ============================================================================
