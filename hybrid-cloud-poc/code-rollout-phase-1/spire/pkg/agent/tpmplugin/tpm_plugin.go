// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// TPM Plugin integration for SPIRE Agent
// 
// Interface: SPIRE Agent → SPIRE TPM Plugin
// Status: 🆕 New (Phase 3)
// Transport: JSON over UDS (Phase 3)
// Protocol: JSON REST API
// 
// Implementation: JSON over UDS (Phase 3) is the transport mechanism.
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

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// TPMPluginClient provides an interface to the Python TPM plugin via HTTP/UDS
type TPMPluginClient struct {
	pluginPath string
	workDir    string
	endpoint   string // UDS endpoint (e.g., "unix:///path/to/sock")
	useHTTP    bool   // Always true - UDS is the only transport mechanism
	httpClient *http.Client
	log        logrus.FieldLogger
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// AppKeyResult contains the result of App Key generation
type AppKeyResult struct {
	AppKeyPublic    string `json:"app_key_public"`
	AppKeyContext   string `json:"app_key_context"`
	Status          string `json:"status"`
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// QuoteResult contains the result of TPM Quote generation
type QuoteResult struct {
	Quote   string
	Nonce   string
	PCRList string
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// NewTPMPluginClient creates a new TPM plugin client
// pluginPath: Path to the TPM plugin CLI script (tpm_plugin_cli.py) - kept for compatibility, not used
// workDir: Working directory for TPM operations (defaults to /tmp/spire-data/tpm-plugin)
// endpoint: UDS endpoint (e.g., "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock")
//           If empty, defaults to UDS socket: "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
//           HTTP over localhost is not supported for security reasons.
func NewTPMPluginClient(pluginPath, workDir, endpoint string, log logrus.FieldLogger) *TPMPluginClient {
	if workDir == "" {
		workDir = "/tmp/spire-data/tpm-plugin"
	}
	
	// Ensure work directory exists
	if err := os.MkdirAll(workDir, 0755); err != nil {
		log.WithError(err).Warn("Unified-Identity - Phase 3: Failed to create TPM plugin work directory, using default")
		workDir = "/tmp/spire-data/tpm-plugin"
	}
	
	if endpoint == "" {
		log.Warn("Unified-Identity - Phase 3: TPM_PLUGIN_ENDPOINT not set, defaulting to UDS socket")
		endpoint = "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
	}
	
	// Validate endpoint is UDS (security requirement)
	if !strings.HasPrefix(endpoint, "unix://") {
		log.WithField("endpoint", endpoint).Error("Unified-Identity - Phase 3: TPM_PLUGIN_ENDPOINT must be a UDS socket (unix://). HTTP over localhost is not supported for security reasons")
		return nil
	}
	
	// Create HTTP client with UDS transport only
	socketPath := strings.TrimPrefix(endpoint, "unix://")
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			// Only support UNIX domain sockets
			return net.Dial("unix", socketPath)
		},
	}
	httpClient := &http.Client{
		Transport: transport,
		Timeout:   30 * time.Second,
	}
	log.Infof("Unified-Identity - Phase 3: TPM Plugin client using UDS endpoint: %s", endpoint)
	
	return &TPMPluginClient{
		pluginPath: pluginPath,
		workDir:    workDir,
		endpoint:   endpoint,
		useHTTP:    true, // Always use HTTP/UDS
		httpClient: httpClient,
		log:        log,
	}
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// GenerateAppKey generates a TPM App Key using the TPM plugin
// Returns the public key (PEM) and context file path
func (c *TPMPluginClient) GenerateAppKey(force bool) (*AppKeyResult, error) {
	c.log.Info("Unified-Identity - Phase 3: Generating TPM App Key via plugin")
	return c.generateAppKeyHTTP(force)
}

// generateAppKeyHTTP generates App Key via HTTP/UDS
func (c *TPMPluginClient) generateAppKeyHTTP(force bool) (*AppKeyResult, error) {
	request := map[string]interface{}{
		"work_dir": c.workDir,
		"force":    force,
	}
	
	var result AppKeyResult
	if err := c.httpRequest("POST", "/generate-app-key", request, &result); err != nil {
		return nil, fmt.Errorf("failed to generate App Key via HTTP: %w", err)
	}
	
	if result.Status != "success" {
		return nil, fmt.Errorf("App Key generation failed: status=%s", result.Status)
	}
	
	c.log.WithFields(logrus.Fields{
		"app_key_context": result.AppKeyContext,
		"public_key_len":  len(result.AppKeyPublic),
	}).Info("Unified-Identity - Phase 3: TPM App Key generated successfully via HTTP/UDS")
	
	return &result, nil
}


// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// GenerateQuote generates a TPM Quote using the App Key
// nonce: Challenge nonce from SPIRE Server
// pcrList: PCR selection (e.g., "sha256:0,1" or "0,1,2,3")
// appKeyContext: Path to App Key context file (optional, will use default if not provided)
func (c *TPMPluginClient) GenerateQuote(nonce, pcrList, appKeyContext string) (string, error) {
	c.log.WithFields(logrus.Fields{
		"nonce":    nonce,
		"pcr_list": pcrList,
	}).Info("Unified-Identity - Phase 3: Generating TPM Quote via plugin")
	
	if nonce == "" {
		return "", fmt.Errorf("nonce is required for quote generation")
	}
	
	return c.generateQuoteHTTP(nonce, pcrList, appKeyContext)
}

// generateQuoteHTTP generates TPM Quote via HTTP/UDS
func (c *TPMPluginClient) generateQuoteHTTP(nonce, pcrList, appKeyContext string) (string, error) {
	request := map[string]interface{}{
		"nonce":    nonce,
		"pcr_list": pcrList,
		"work_dir": c.workDir,
	}
	if appKeyContext != "" {
		request["app_key_context"] = appKeyContext
	}
	
	var result struct {
		Status string `json:"status"`
		Quote  string `json:"quote"`
	}
	
	if err := c.httpRequest("POST", "/generate-quote", request, &result); err != nil {
		return "", fmt.Errorf("failed to generate TPM Quote via HTTP: %w", err)
	}
	
	if result.Status != "success" {
		return "", fmt.Errorf("Quote generation failed: status=%s", result.Status)
	}
	
	c.log.WithField("quote_len", len(result.Quote)).Info("Unified-Identity - Phase 3: TPM Quote generated successfully via HTTP/UDS")
	
	return result.Quote, nil
}


// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// RequestCertificate requests an App Key certificate from rust-keylime agent
// appKeyPublic: PEM-encoded App Key public key
// appKeyContext: Path to App Key context file
// endpoint: rust-keylime agent endpoint (defaults to HTTP endpoint)
func (c *TPMPluginClient) RequestCertificate(appKeyPublic, appKeyContext, endpoint string) ([]byte, error) {
	c.log.Info("Unified-Identity - Phase 3: Requesting App Key certificate from rust-keylime agent via plugin")
	
	if appKeyPublic == "" || appKeyContext == "" {
		return nil, fmt.Errorf("app key public and context are required")
	}
	
	return c.requestCertificateHTTP(appKeyPublic, appKeyContext, endpoint)
}

// requestCertificateHTTP requests certificate via HTTP/UDS
func (c *TPMPluginClient) requestCertificateHTTP(appKeyPublic, appKeyContext, endpoint string) ([]byte, error) {
	// Use UDS endpoint (rust-keylime agent)
	if endpoint == "" {
		endpoint = "unix:///tmp/keylime-agent.sock"
	}
	
	request := map[string]interface{}{
		"app_key_public":       appKeyPublic,
		"app_key_context_path": appKeyContext,
		"endpoint":              endpoint,
	}
	
	var result struct {
		Status           string `json:"status"`
		AppKeyCertificate string `json:"app_key_certificate"`
	}
	
	if err := c.httpRequest("POST", "/request-certificate", request, &result); err != nil {
		return nil, fmt.Errorf("failed to request certificate via HTTP: %w", err)
	}
	
	if result.Status != "success" {
		return nil, fmt.Errorf("Certificate request failed: status=%s", result.Status)
	}
	
	// Decode base64 certificate
	certBytes, err := base64.StdEncoding.DecodeString(result.AppKeyCertificate)
	if err != nil {
		return nil, fmt.Errorf("invalid base64 certificate: %w", err)
	}
	
	c.log.WithField("cert_len", len(certBytes)).Info("Unified-Identity - Phase 3: App Key certificate received successfully via HTTP/UDS")
	
	return certBytes, nil
}


// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// BuildSovereignAttestation builds a real SovereignAttestation using the TPM plugin
// nonce: Challenge nonce from SPIRE Server
// Returns a fully populated SovereignAttestation with real TPM data
func (c *TPMPluginClient) BuildSovereignAttestation(nonce string) (*types.SovereignAttestation, error) {
	c.log.Info("Unified-Identity - Phase 3: Building real SovereignAttestation via TPM plugin")
	
	// Step 1: Generate or retrieve App Key
	appKeyResult, err := c.GenerateAppKey(false)
	if err != nil {
		return nil, fmt.Errorf("failed to generate App Key: %w", err)
	}
	
	// Step 2: Generate TPM Quote with nonce
	// Use default PCR list: sha256:0,1,2,3,4,5,6,7 (common PCRs)
	quote, err := c.GenerateQuote(nonce, "sha256:0,1,2,3,4,5,6,7", appKeyResult.AppKeyContext)
	if err != nil {
		return nil, fmt.Errorf("failed to generate TPM Quote: %w", err)
	}
	
	// Step 3: Request certificate from rust-keylime agent
	var certBytes []byte
	c.log.WithFields(logrus.Fields{
		"app_key_public_len":  len(appKeyResult.AppKeyPublic),
		"app_key_context":     appKeyResult.AppKeyContext,
	}).Debug("Unified-Identity - Phase 3: Preparing to request certificate")
	
	if appKeyResult.AppKeyPublic == "" || appKeyResult.AppKeyContext == "" {
		c.log.WithFields(logrus.Fields{
			"app_key_public_empty": appKeyResult.AppKeyPublic == "",
			"app_key_context_empty": appKeyResult.AppKeyContext == "",
		}).Warn("Unified-Identity - Phase 3: App Key result has empty fields, skipping certificate request")
		certBytes = nil
	} else {
		var err error
		certBytes, err = c.RequestCertificate(appKeyResult.AppKeyPublic, appKeyResult.AppKeyContext, "")
		if err != nil {
			c.log.WithError(err).Warn("Unified-Identity - Phase 3: Failed to request certificate, continuing without certificate")
			// Continue without certificate - it's optional
			certBytes = nil
		}
	}
	
	// Build SovereignAttestation
	sovereignAttestation := &types.SovereignAttestation{
		TpmSignedAttestation: quote,
		AppKeyPublic:         appKeyResult.AppKeyPublic,
		ChallengeNonce:       nonce,
	}
	
	if certBytes != nil {
		sovereignAttestation.AppKeyCertificate = certBytes
	}
	
	c.log.Info("Unified-Identity - Phase 3: Real SovereignAttestation built successfully")
	
	return sovereignAttestation, nil
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// httpRequest makes an HTTP request to the TPM plugin server
func (c *TPMPluginClient) httpRequest(method, path string, requestBody interface{}, responseBody interface{}) error {
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
	resp, err := c.httpClient.Do(req)
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


