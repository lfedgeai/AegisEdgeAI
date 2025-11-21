// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Package keylime provides a client for interacting with the Keylime Verifier API.
package keylime

import (
	"bytes"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/sirupsen/logrus"
)

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Client is a client for the Keylime Verifier API
type Client struct {
	baseURL    string
	httpClient *http.Client
	logger     logrus.FieldLogger
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Config holds configuration for the Keylime client
type Config struct {
	BaseURL string
	TLSCert string
	TLSKey  string
	CACert  string
	Timeout time.Duration
	Logger  logrus.FieldLogger
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// AttestedClaims represents verified facts from Keylime
type AttestedClaims struct {
	Geolocation         string `json:"geolocation"`
	HostIntegrityStatus string `json:"host_integrity_status"`
	GPUMetricsHealth    struct {
		Status         string  `json:"status"`
		UtilizationPct float64 `json:"utilization_pct"`
		MemoryMB       int64   `json:"memory_mb"`
	} `json:"gpu_metrics_health"`
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
// VerifyEvidenceRequest represents the request to Keylime
type VerifyEvidenceRequest struct {
	Type string `json:"type"` // Unified-Identity - Phase 2: Required by Keylime Verifier
	Data struct {
		Nonce             string `json:"nonce"`
		Quote             string `json:"quote"`
		HashAlg           string `json:"hash_alg"`
		AppKeyPublic      string `json:"app_key_public"`
		AppKeyCertificate string `json:"app_key_certificate"`
		AgentUUID         string `json:"agent_uuid,omitempty"`
		AgentIP           string `json:"agent_ip,omitempty"`
		AgentPort         int    `json:"agent_port,omitempty"`
		TPMAK             string `json:"tpm_ak,omitempty"`
		TPMEK             string `json:"tpm_ek,omitempty"`
	} `json:"data"`
	Metadata struct {
		Source         string `json:"source"`
		SubmissionType string `json:"submission_type"`
		AuditID        string `json:"audit_id,omitempty"`
	} `json:"metadata"`
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// VerifyEvidenceResponse represents the response from Keylime
type VerifyEvidenceResponse struct {
	Results struct {
		Verified            bool `json:"verified"`
		VerificationDetails struct {
			AppKeyCertificateValid  bool  `json:"app_key_certificate_valid"`
			AppKeyPublicMatchesCert bool  `json:"app_key_public_matches_cert"`
			QuoteSignatureValid     bool  `json:"quote_signature_valid"`
			NonceValid              bool  `json:"nonce_valid"`
			Timestamp               int64 `json:"timestamp"`
		} `json:"verification_details"`
		AttestedClaims AttestedClaims `json:"attested_claims"`
		AuditID        string         `json:"audit_id"`
	} `json:"results"`
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// NewClient creates a new Keylime client
func NewClient(config Config) (*Client, error) {
	if config.Logger == nil {
		config.Logger = logrus.New()
	}

	if config.BaseURL == "" {
		return nil, fmt.Errorf("base URL is required")
	}

	if config.Timeout == 0 {
		// Unified-Identity - Phase 3: Increased timeout to 60s to allow for TPM quote operations
		// With USE_TPM2_QUOTE_DIRECT, quotes complete in ~10s, but we allow extra time for
		// network overhead and verifier processing
		config.Timeout = 60 * time.Second
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Interface: SPIRE Server → Keylime Verifier
	// Status: 🆕 New (Phase 2/3 Addition)
	// Transport: mTLS over HTTPS
	// Protocol: JSON REST API
	// Port: localhost:8881
	// Endpoint: POST /v2.4/verify/evidence
	// Authentication: TLS client certificate authentication (mTLS)
	// Configure TLS for mTLS connection to Keylime Verifier
	tlsConfig := &tls.Config{
		// For testing with self-signed certificates, allow insecure skip
		// In production, this should be false and CA cert should be loaded
		InsecureSkipVerify: true, // TODO: Phase 3: Make configurable for production
	}

	// Unified-Identity - Phase 3: Load CA certificate for server verification (production)
	if config.CACert != "" {
		// TODO: Implement CA cert loading for production use
		// This would set tlsConfig.RootCAs to verify the Keylime Verifier's server certificate
		config.Logger.Info("Unified-Identity - Phase 3: CA certificate loading not yet implemented (using InsecureSkipVerify for testing)")
	}

	// Unified-Identity - Phase 3: Configure client certificate for mTLS
	// If TLSCert and TLSKey are provided, enable mTLS (client authenticates to Keylime Verifier)
	if config.TLSCert != "" && config.TLSKey != "" {
		cert, err := tls.LoadX509KeyPair(config.TLSCert, config.TLSKey)
		if err != nil {
			return nil, fmt.Errorf("failed to load client certificate: %w", err)
		}
		tlsConfig.Certificates = []tls.Certificate{cert}
		config.Logger.Info("Unified-Identity - Phase 3: Loaded client certificate for mTLS (SPIRE Server authenticates to Keylime Verifier)")
	} else {
		config.Logger.Debug("Unified-Identity - Phase 3: No client certificate provided, mTLS not enabled (server-only TLS)")
	}

	transport := &http.Transport{
		TLSClientConfig: tlsConfig,
	}

	return &Client{
		baseURL: config.BaseURL,
		httpClient: &http.Client{
			Transport: transport,
			Timeout:   config.Timeout,
		},
		logger: config.Logger,
	}, nil
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// VerifyEvidence calls the Keylime Verifier to verify evidence and get AttestedClaims
func (c *Client) VerifyEvidence(req *VerifyEvidenceRequest) (*AttestedClaims, error) {
	c.logger.WithFields(logrus.Fields{
		"nonce":           req.Data.Nonce,
		"submission_type": req.Metadata.SubmissionType,
		"source":          req.Metadata.Source,
	}).Info("Unified-Identity - Phase 3: Calling Keylime Verifier to verify evidence")

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Encode request body
	reqBody, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Create HTTP request
	url := fmt.Sprintf("%s/v2.4/verify/evidence", c.baseURL)
	httpReq, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(reqBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Execute request
	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		c.logger.WithError(err).Error("Unified-Identity - Phase 3: Failed to call Keylime Verifier")
		return nil, fmt.Errorf("failed to call Keylime Verifier: %w", err)
	}
	defer resp.Body.Close()

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Read response body
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Check HTTP status
	if resp.StatusCode != http.StatusOK {
		c.logger.WithFields(logrus.Fields{
			"status_code": resp.StatusCode,
			"body":        string(respBody),
		}).Error("Unified-Identity - Phase 3: Keylime Verifier returned error")
		return nil, fmt.Errorf("keylime verifier returned status %d: %s", resp.StatusCode, string(respBody))
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Parse response
	var verifyResp VerifyEvidenceResponse
	if err := json.Unmarshal(respBody, &verifyResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Validate verification result
	if !verifyResp.Results.Verified {
		c.logger.WithFields(logrus.Fields{
			"audit_id": verifyResp.Results.AuditID,
		}).Warn("Unified-Identity - Phase 3: Keylime verification failed")
		return nil, fmt.Errorf("verification failed (audit_id: %s)", verifyResp.Results.AuditID)
	}

	c.logger.WithFields(logrus.Fields{
		"audit_id":    verifyResp.Results.AuditID,
		"geolocation": verifyResp.Results.AttestedClaims.Geolocation,
		"integrity":   verifyResp.Results.AttestedClaims.HostIntegrityStatus,
		"gpu_status":  verifyResp.Results.AttestedClaims.GPUMetricsHealth.Status,
	}).Info("Unified-Identity - Phase 3: Successfully received AttestedClaims from Keylime")

	return &verifyResp.Results.AttestedClaims, nil
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
// BuildVerifyEvidenceRequest builds a VerifyEvidenceRequest from SovereignAttestation
func BuildVerifyEvidenceRequest(sovereignAttestation *SovereignAttestationProto, nonce string) (*VerifyEvidenceRequest, error) {
	req := &VerifyEvidenceRequest{}

	// Unified-Identity - Phase 2: Set evidence type (required by Keylime Verifier)
	req.Type = "tpm"

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
	// Set data fields
	req.Data.Nonce = sovereignAttestation.ChallengeNonce
	if req.Data.Nonce == "" {
		req.Data.Nonce = nonce
	}
	req.Data.Quote = sovereignAttestation.TpmSignedAttestation
	req.Data.HashAlg = "sha256"
	req.Data.AppKeyPublic = sovereignAttestation.AppKeyPublic
	req.Data.AgentUUID = sovereignAttestation.KeylimeAgentUuid

	// Provide agent endpoint details so the Keylime Verifier can look up the AK
	req.Data.AgentIP = getEnvOrDefault("KEYLIME_AGENT_IP", "127.0.0.1")
	req.Data.AgentPort = getEnvIntOrDefault("KEYLIME_AGENT_PORT", 9002)

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
	// Base64 encode app_key_certificate if present
	if len(sovereignAttestation.AppKeyCertificate) > 0 {
		req.Data.AppKeyCertificate = base64.StdEncoding.EncodeToString(sovereignAttestation.AppKeyCertificate)
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
	// Set metadata
	req.Metadata.Source = "SPIRE Server"
	req.Metadata.SubmissionType = "PoR/tpm-app-key"

	return req, nil
}

func getEnvOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getEnvIntOrDefault(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	if parsed, err := strconv.Atoi(value); err == nil {
		return parsed
	}
	return fallback
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// SovereignAttestationProto represents the protobuf SovereignAttestation type
// This is a placeholder - in the actual implementation, this would be the generated protobuf type
type SovereignAttestationProto struct {
	TpmSignedAttestation string
	AppKeyPublic         string
	AppKeyCertificate    []byte
	ChallengeNonce       string
	WorkloadCodeHash     string
	KeylimeAgentUuid     string
}
