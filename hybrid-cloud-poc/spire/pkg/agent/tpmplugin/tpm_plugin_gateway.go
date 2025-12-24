// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TPM Plugin integration for SPIRE Agent
//
// Interface: SPIRE Agent → SPIRE TPM Plugin
// Status: 🆕 New (Verification)
// Transport: JSON over UDS (Verification)
// Protocol: JSON REST API
//
// Implementation: JSON over UDS (Verification) is the transport mechanism.
// The client requires TPM_PLUGIN_ENDPOINT to be set (e.g., "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock").
// HTTP over localhost is not supported for security reasons.

package tpmplugin

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TPMPluginGateway provides a bridge/gateway interface between SPIRE Agent (Go) and the TPM Plugin Server (Python)
// This gateway communicates with the Python TPM Plugin Server via HTTP/UDS
// Architecture: SPIRE Agent (Go) → TPM Plugin Gateway (Go) → TPM Plugin Server (Python) → TPM Hardware
type TPMPluginGateway struct {
	pluginPath string
	workDir    string
	endpoint   string // UDS endpoint (e.g., "unix:///path/to/sock")
	useHTTP    bool   // Always true - UDS is the only transport mechanism
	httpClient *http.Client
	log        logrus.FieldLogger
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// AppKeyResult contains the result of App Key generation
type AppKeyResult struct {
	AppKeyPublic string `json:"app_key_public"`
	Status       string `json:"status"`
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// Old QuoteResult type - removed (replaced by new QuoteResult with certificate support)

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// NewTPMPluginGateway creates a new TPM Plugin Gateway
// This gateway bridges SPIRE Agent (Go) with the TPM Plugin Server (Python)
// pluginPath: Path to the TPM plugin CLI script (tpm_plugin_cli.py) - kept for compatibility, not used
// workDir: Working directory for TPM operations (defaults to /tmp/spire-data/tpm-plugin)
// endpoint: UDS endpoint (e.g., "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock")
//
//	If empty, defaults to UDS socket: "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
//	HTTP over localhost is not supported for security reasons.
func NewTPMPluginGateway(pluginPath, workDir, endpoint string, log logrus.FieldLogger) *TPMPluginGateway {
	if workDir == "" {
		workDir = "/tmp/spire-data/tpm-plugin"
	}

	// Ensure work directory exists
	if err := os.MkdirAll(workDir, 0755); err != nil {
		log.WithError(err).Warn("Unified-Identity - Verification: Failed to create TPM plugin work directory, using default")
		workDir = "/tmp/spire-data/tpm-plugin"
	}

	if endpoint == "" {
		log.Warn("Unified-Identity - Verification: TPM_PLUGIN_ENDPOINT not set, defaulting to UDS socket")
		endpoint = "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
	}

	// Validate endpoint is UDS (security requirement)
	if !strings.HasPrefix(endpoint, "unix://") {
		log.WithField("endpoint", endpoint).Error("Unified-Identity - Verification: TPM_PLUGIN_ENDPOINT must be a UDS socket (unix://). HTTP over localhost is not supported for security reasons")
		return nil
	}

	// Create HTTP client with UDS transport only
	socketPath := strings.TrimPrefix(endpoint, "unix://")

	// Verify socket exists before creating transport (warn if not, but don't fail - might be created later)
	if _, err := os.Stat(socketPath); os.IsNotExist(err) {
		log.WithError(err).WithField("socket_path", socketPath).Warn("Unified-Identity - Verification: TPM Plugin Server socket does not exist yet, will retry on first request")
	}

	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			// Only support UNIX domain sockets
			// Verify socket exists before dialing for better error messages
			if _, err := os.Stat(socketPath); os.IsNotExist(err) {
				return nil, fmt.Errorf("TPM Plugin Server socket does not exist: %s (is the TPM Plugin Server running? check: ls -l %s)", socketPath, socketPath)
			}
			conn, err := net.Dial("unix", socketPath)
			if err != nil {
				return nil, fmt.Errorf("failed to connect to TPM Plugin Server socket %s: %w (is the server running?)", socketPath, err)
			}
			return conn, nil
		},
	}
	httpClient := &http.Client{
		Transport: transport,
		Timeout:   30 * time.Second,
	}
	log.Infof("Unified-Identity - Verification: TPM Plugin Gateway using UDS endpoint: %s", endpoint)

	return &TPMPluginGateway{
		pluginPath: pluginPath,
		workDir:    workDir,
		endpoint:   endpoint,
		useHTTP:    true, // Always use HTTP/UDS
		httpClient: httpClient,
		log:        log,
	}
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// GenerateAppKey gets the TPM App Key from the TPM plugin
// The App Key is generated on TPM plugin server startup, so this just retrieves it
// Returns the public key (PEM)
func (g *TPMPluginGateway) GenerateAppKey(force bool) (*AppKeyResult, error) {
	g.log.Info("Unified-Identity - Verification: Getting TPM App Key via plugin")
	return g.generateAppKeyHTTP(force)
}

// generateAppKeyHTTP gets App Key via HTTP/UDS (App Key is generated on TPM plugin server startup)
func (g *TPMPluginGateway) generateAppKeyHTTP(force bool) (*AppKeyResult, error) {
	// Note: App Key is generated on TPM plugin server startup, so we just get it
	// The 'force' parameter is ignored since the server manages key generation
	request := map[string]interface{}{}

	var result AppKeyResult
	if err := g.httpRequest("POST", "/get-app-key", request, &result); err != nil {
		return nil, fmt.Errorf("failed to get App Key via HTTP: %w", err)
	}

	if result.Status != "success" {
		return nil, fmt.Errorf("App Key retrieval failed: status=%s", result.Status)
	}

	g.log.WithFields(logrus.Fields{
		"public_key_len": len(result.AppKeyPublic),
	}).Info("Unified-Identity - Verification: TPM App Key retrieved successfully via HTTP/UDS")

	return &result, nil
}

// QuoteResult contains the quote, App Key public key, and optional certificate from the TPM plugin
type QuoteResult struct {
	Quote             string
	AppKeyPublic      string // App Key public key (PEM format) - required for Keylime verification
	AppKeyCertificate []byte // Optional, may be nil if delegated certification failed
}

// Unified-Identity - Verification: Quote generation removed
// Quotes are now generated by rust-keylime agent and requested by Keylime Verifier
// The GenerateQuote function is no longer needed

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// RequestCertificate requests an App Key certificate from rust-keylime agent
// appKeyPublic: PEM-encoded App Key public key
// appKeyContext: Path to App Key context file
// endpoint: rust-keylime agent endpoint (defaults to HTTP endpoint)
func (g *TPMPluginGateway) RequestCertificate(appKeyPublic, endpoint, challengeNonce string) ([]byte, string, error) {
	g.log.Info("Unified-Identity - Verification: Requesting App Key certificate from rust-keylime agent via plugin")

	if appKeyPublic == "" {
		return nil, "", fmt.Errorf("app key public is required")
	}
	if challengeNonce == "" {
		return nil, "", fmt.Errorf("challenge nonce is required")
	}

	return g.requestCertificateHTTP(appKeyPublic, endpoint, challengeNonce)
}

// requestCertificateHTTP requests certificate via HTTP/UDS
func (g *TPMPluginGateway) requestCertificateHTTP(appKeyPublic, endpoint, challengeNonce string) ([]byte, string, error) {
	// Use HTTP endpoint (rust-keylime agent) - simplified, no mTLS required
	if endpoint == "" {
		endpoint = "http://127.0.0.1:9002"
	}

	request := map[string]interface{}{
		"app_key_public":  appKeyPublic,
		"endpoint":        endpoint,
		"challenge_nonce": challengeNonce,
	}

	var result struct {
		Status            string `json:"status"`
		AppKeyCertificate string `json:"app_key_certificate"`
		AgentUUID         string `json:"agent_uuid"`
	}

	if err := g.httpRequest("POST", "/request-certificate", request, &result); err != nil {
		return nil, "", fmt.Errorf("failed to request certificate via HTTP: %w", err)
	}

	if result.Status != "success" {
		return nil, "", fmt.Errorf("Certificate request failed: status=%s", result.Status)
	}

	// Decode base64 certificate
	certBytes, err := base64.StdEncoding.DecodeString(result.AppKeyCertificate)
	if err != nil {
		return nil, "", fmt.Errorf("invalid base64 certificate: %w", err)
	}

	g.log.WithField("cert_len", len(certBytes)).Info("Unified-Identity - Verification: App Key certificate received successfully via HTTP/UDS")

	return certBytes, result.AgentUUID, nil
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// SignData signs data using the TPM App Key via the TPM plugin
// data: Data to sign (should be a digest when called from crypto.Signer.Sign())
// Returns the signature bytes
func (g *TPMPluginGateway) SignData(data []byte) ([]byte, error) {
	return g.SignDataWithHash(data, "sha256", "rsassa", -1)
}

// SignDataWithHash signs data using the TPM App Key via the TPM plugin with a specific hash algorithm
// data: Data to sign (should be a digest when called from crypto.Signer.Sign())
// hashAlg: Hash algorithm to use (e.g., "sha256", "sha384", "sha512")
// scheme: Signature scheme to use ("rsassa" for PKCS#1 v1.5, "rsapss" for RSA-PSS)
// saltLength: Salt length for RSA-PSS (-1 for default, which is hash length)
// Returns the signature bytes
func (g *TPMPluginGateway) SignDataWithHash(data []byte, hashAlg string, scheme string, saltLength int) ([]byte, error) {
	g.log.WithFields(logrus.Fields{
		"hash_alg":    hashAlg,
		"scheme":      scheme,
		"salt_length": saltLength,
	}).Debug("Unified-Identity - Verification: Signing data using TPM App Key via plugin")

	request := map[string]interface{}{
		"data":        base64.StdEncoding.EncodeToString(data),
		"hash_alg":    hashAlg,
		"is_digest":   true, // crypto.Signer.Sign() receives a digest, so we tell the plugin not to hash again
		"scheme":      scheme,
		"salt_length": saltLength,
	}

	var result struct {
		Status    string `json:"status"`
		Signature string `json:"signature"`
	}

	if err := g.httpRequest("POST", "/sign-data", request, &result); err != nil {
		return nil, fmt.Errorf("failed to sign data via HTTP: %w", err)
	}

	if result.Status != "success" {
		return nil, fmt.Errorf("signing failed: status=%s", result.Status)
	}

	// Decode base64 signature
	signatureBytes, err := base64.StdEncoding.DecodeString(result.Signature)
	if err != nil {
		return nil, fmt.Errorf("invalid base64 signature: %w", err)
	}

	g.log.WithField("signature_len", len(signatureBytes)).Debug("Unified-Identity - Verification: Data signed successfully via HTTP/UDS")

	return signatureBytes, nil
}

// VerifySignature verifies a signature using the TPM App Key via the TPM plugin
// data: Data that was signed (should be a digest when called from verification)
// signature: Signature bytes to verify
// hashAlg: Hash algorithm used (e.g., "sha256", "sha384", "sha512")
// isDigest: If true, data is already a digest and should not be hashed again
// Returns true if verification succeeds
func (g *TPMPluginGateway) VerifySignature(data []byte, signature []byte, hashAlg string, isDigest bool) (bool, error) {
	g.log.WithField("hash_alg", hashAlg).Debug("Unified-Identity - Verification: Verifying signature using TPM App Key via plugin")

	request := map[string]interface{}{
		"data":      base64.StdEncoding.EncodeToString(data),
		"signature": base64.StdEncoding.EncodeToString(signature),
		"hash_alg":  hashAlg,
		"is_digest": isDigest,
	}

	var result struct {
		Status  string `json:"status"`
		Verified bool   `json:"verified,omitempty"`
		Error   string `json:"error,omitempty"`
	}

	if err := g.httpRequest("POST", "/verify-signature", request, &result); err != nil {
		return false, fmt.Errorf("failed to verify signature via HTTP: %w", err)
	}

	if result.Status != "success" {
		return false, fmt.Errorf("verification failed: %s", result.Error)
	}

	if !result.Verified {
		return false, fmt.Errorf("signature verification failed")
	}

	g.log.Debug("Unified-Identity - Verification: Signature verified successfully via HTTP/UDS")
	return true, nil
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// BuildSovereignAttestation builds a real SovereignAttestation using the TPM plugin
// nonce: Challenge nonce from SPIRE Server
// Returns a fully populated SovereignAttestation with real TPM data
//
// Architecture Change (Verification):
// - TPM Plugin no longer generates quotes (removed /generate-quote endpoint)
// - Quotes are now generated by rust-keylime agent and requested by Keylime Verifier
// - SPIRE Agent only needs to get App Key public and certificate from TPM plugin
// - Quote field will be empty/stub since Keylime Verifier requests it directly from agent
func (g *TPMPluginGateway) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
	if g.log == nil {
		return nil, fmt.Errorf("logger is nil")
	}
	if g.httpClient == nil {
		g.log.Error("HTTP client is nil")
		return nil, fmt.Errorf("HTTP client is nil")
	}

	g.log.Info("Unified-Identity - Verification: Building real SovereignAttestation via TPM plugin")

	// Unified-Identity - Verification: Get App Key public key and certificate
	// The App Key was generated on plugin startup, so we need to get it from the plugin
	// Since the plugin doesn't expose a "get app key" endpoint, we'll request the certificate
	// which will trigger the plugin to get the App Key public key

	// First, try to get App Key info by requesting certificate
	// The plugin should have the App Key stored from startup
	// We'll use a workaround: request certificate which will return App Key public

	// Get App Key public key - we need to call the plugin to get it
	// Since there's no dedicated endpoint, we'll need to add one or use a workaround
	// For now, we'll use stub data for the quote since Keylime Verifier will request it directly
	g.log.Info("Unified-Identity - Verification: Getting App Key public and certificate (quote will be handled by Keylime Verifier)")

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
		TpmSignedAttestation: "", // Empty - Keylime Verifier will request quote from rust-keylime agent
		AppKeyPublic:         appKeyResult.AppKeyPublic,
		ChallengeNonce:       nonce,
		AppKeyCertificate:    appKeyCertificate,
		KeylimeAgentUuid:     agentUUID,
	}

	g.log.Info("Unified-Identity - Verification: SovereignAttestation built successfully (quote handled by Keylime Verifier)")

	return sovereignAttestation, nil
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// httpRequest makes an HTTP request to the TPM plugin server
func (g *TPMPluginGateway) httpRequest(method, path string, requestBody interface{}, responseBody interface{}) error {
	// Build URL for UDS (use http://localhost as the host, will be replaced by DialContext)
	url := "http://localhost" + path

	// Marshal request body
	reqBodyBytes, err := json.Marshal(requestBody)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %w", err)
	}

	// Create HTTP request
	req, err := http.NewRequest(method, url, bytes.NewReader(reqBodyBytes))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	// Execute request
	resp, err := g.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	respBodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	// Check status code
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP request failed with status %d: %s", resp.StatusCode, string(respBodyBytes))
	}

	// Unmarshal response
	if err := json.Unmarshal(respBodyBytes, responseBody); err != nil {
		return fmt.Errorf("failed to unmarshal response: %w, body: %s", err, string(respBodyBytes))
	}

	return nil
}
