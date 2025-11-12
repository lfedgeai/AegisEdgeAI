// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// TPM Plugin integration for SPIRE Agent
// This package provides Go bindings to call the Python TPM plugin CLI

package tpmplugin

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// TPMPluginClient provides an interface to the Python TPM plugin CLI
type TPMPluginClient struct {
	pluginPath string
	workDir    string
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
// pluginPath: Path to the TPM plugin CLI script (tpm_plugin_cli.py)
// workDir: Working directory for TPM operations (defaults to /tmp/spire-data/tpm-plugin)
func NewTPMPluginClient(pluginPath, workDir string, log logrus.FieldLogger) *TPMPluginClient {
	if workDir == "" {
		workDir = "/tmp/spire-data/tpm-plugin"
	}
	
	// Ensure work directory exists
	if err := os.MkdirAll(workDir, 0755); err != nil {
		log.WithError(err).Warn("Unified-Identity - Phase 3: Failed to create TPM plugin work directory, using default")
		workDir = "/tmp/spire-data/tpm-plugin"
	}
	
	return &TPMPluginClient{
		pluginPath: pluginPath,
		workDir:    workDir,
		log:        log,
	}
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// GenerateAppKey generates a TPM App Key using the TPM plugin
// Returns the public key (PEM) and context file path
func (c *TPMPluginClient) GenerateAppKey(force bool) (*AppKeyResult, error) {
	c.log.Info("Unified-Identity - Phase 3: Generating TPM App Key via plugin")
	
	args := []string{"generate-app-key", "--work-dir", c.workDir}
	if force {
		args = append(args, "--force")
	}
	
	output, err := c.runPluginCommand(args)
	if err != nil {
		return nil, fmt.Errorf("failed to generate App Key: %w", err)
	}
	
	var result AppKeyResult
	if err := json.Unmarshal([]byte(output), &result); err != nil {
		return nil, fmt.Errorf("failed to parse App Key result: %w", err)
	}
	
	if result.Status != "success" {
		return nil, fmt.Errorf("App Key generation failed: status=%s", result.Status)
	}
	
	c.log.WithFields(logrus.Fields{
		"app_key_context": result.AppKeyContext,
		"public_key_len":  len(result.AppKeyPublic),
	}).Info("Unified-Identity - Phase 3: TPM App Key generated successfully")
	
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
	
	args := []string{"generate-quote", "--work-dir", c.workDir, "--nonce", nonce}
	if pcrList != "" {
		args = append(args, "--pcr-list", pcrList)
	}
	if appKeyContext != "" {
		args = append(args, "--app-key-context", appKeyContext)
	}
	
	output, err := c.runPluginCommand(args)
	if err != nil {
		return "", fmt.Errorf("failed to generate TPM Quote: %w", err)
	}
	
	// Output is base64-encoded quote
	quote := strings.TrimSpace(output)
	
	c.log.WithField("quote_len", len(quote)).Info("Unified-Identity - Phase 3: TPM Quote generated successfully")
	
	return quote, nil
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
	
	args := []string{"request-certificate", "--app-key-public", appKeyPublic, "--app-key-context", appKeyContext}
	
	// Use HTTP endpoint by default (rust-keylime agent)
	if endpoint == "" {
		endpoint = "http://localhost:9002/v2.2/delegated_certification/certify_app_key"
	}
	args = append(args, "--endpoint", endpoint)
	
	output, err := c.runPluginCommand(args)
	if err != nil {
		return nil, fmt.Errorf("failed to request certificate: %w", err)
	}
	
	// Output is base64-encoded certificate
	certB64 := strings.TrimSpace(output)
	
	// Decode to verify it's valid base64
	certBytes, err := base64.StdEncoding.DecodeString(certB64)
	if err != nil {
		return nil, fmt.Errorf("invalid base64 certificate: %w", err)
	}
	
	c.log.WithField("cert_len", len(certBytes)).Info("Unified-Identity - Phase 3: App Key certificate received successfully")
	
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
// runPluginCommand executes the TPM plugin CLI with the given arguments
func (c *TPMPluginClient) runPluginCommand(args []string) (string, error) {
	// Find Python 3
	python3, err := exec.LookPath("python3")
	if err != nil {
		return "", fmt.Errorf("python3 not found: %w", err)
	}
	
	// Check if plugin path exists
	if c.pluginPath == "" {
		// Try to find the plugin in common locations
		possiblePaths := []string{
			"/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py",
			filepath.Join(os.Getenv("HOME"), "AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-3/tpm-plugin/tpm_plugin_cli.py"),
			"./tpm-plugin/tpm_plugin_cli.py",
		}
		
		for _, path := range possiblePaths {
			if _, err := os.Stat(path); err == nil {
				c.pluginPath = path
				break
			}
		}
		
		if c.pluginPath == "" {
			return "", fmt.Errorf("TPM plugin CLI not found, please set plugin path")
		}
	}
	
	if _, err := os.Stat(c.pluginPath); err != nil {
		return "", fmt.Errorf("TPM plugin CLI not found at %s: %w", c.pluginPath, err)
	}
	
	// Ensure UNIFIED_IDENTITY_ENABLED is set
	env := os.Environ()
	unifiedIdentitySet := false
	for _, e := range env {
		if strings.HasPrefix(e, "UNIFIED_IDENTITY_ENABLED=") {
			unifiedIdentitySet = true
			break
		}
	}
	if !unifiedIdentitySet {
		env = append(env, "UNIFIED_IDENTITY_ENABLED=true")
	}
	
	// Build command
	cmd := exec.Command(python3, c.pluginPath)
	cmd.Args = append(cmd.Args, args...)
	cmd.Env = env
	cmd.Dir = filepath.Dir(c.pluginPath)
	
	c.log.WithFields(logrus.Fields{
		"command": strings.Join(cmd.Args, " "),
		"work_dir": c.workDir,
	}).Debug("Unified-Identity - Phase 3: Executing TPM plugin command")
	
	// Unified-Identity - Phase 3: Capture stdout and stderr separately
	// Logs go to stderr, JSON output goes to stdout
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	
	output, err := cmd.Output()
	if err != nil {
		// Include stderr in error message for debugging
		stderrStr := stderr.String()
		if stderrStr != "" {
			c.log.WithField("stderr", stderrStr).Debug("Unified-Identity - Phase 3: TPM plugin stderr output")
		}
		return "", fmt.Errorf("TPM plugin command failed: %w, stdout: %s, stderr: %s", err, string(output), stderrStr)
	}
	
	// Log stderr output for debugging (but don't include it in the return value)
	if stderrStr := stderr.String(); stderrStr != "" {
		c.log.WithField("stderr", stderrStr).Debug("Unified-Identity - Phase 3: TPM plugin stderr output")
	}
	
	return string(output), nil
}

