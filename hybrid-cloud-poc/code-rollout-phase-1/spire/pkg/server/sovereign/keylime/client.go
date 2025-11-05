// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Package keylime provides a stubbed client for the Keylime Verifier API.
// This client is used by the SPIRE Server to forward sovereign attestation
// evidence to Keylime for verification and to receive attested claims.
package keylime

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/common/fflag"
)

const (
	// DefaultKeylimeVerifierURL is the default URL for the Keylime Verifier API
	DefaultKeylimeVerifierURL = "http://localhost:8881"
	// VerifyEvidenceEndpoint is the Keylime endpoint for verifying evidence
	VerifyEvidenceEndpoint = "/v2.4/verify/evidence"
	// DefaultTimeout is the default timeout for Keylime API calls
	DefaultTimeout = 30 * time.Second
)

// Client is a stubbed client for the Keylime Verifier API
type Client struct {
	baseURL    string
	httpClient *http.Client
	log        logrus.FieldLogger
}

// VerifyEvidenceRequest represents the request sent to Keylime Verifier
type VerifyEvidenceRequest struct {
	Data struct {
		Nonce              string `json:"nonce"`
		Quote              string `json:"quote"` // Base64-encoded TPM Quote
		HashAlg            string `json:"hash_alg"`
		AppKeyPublic       string `json:"app_key_public,omitempty"`
		AppKeyCertificate  string `json:"app_key_certificate,omitempty"` // Base64-encoded X.509 DER/PEM
		TPMAK              string `json:"tpm_ak,omitempty"`
		TPMEK              string `json:"tpm_ek,omitempty"`
	} `json:"data"`
	Metadata struct {
		Source         string `json:"source"`
		SubmissionType string `json:"submission_type"`
		AuditID        string `json:"audit_id,omitempty"`
	} `json:"metadata"`
}

// VerifyEvidenceResponse represents the response from Keylime Verifier
type VerifyEvidenceResponse struct {
	Results struct {
		Verified            bool `json:"verified"`
		VerificationDetails struct {
			AppKeyCertificateValid   bool  `json:"app_key_certificate_valid"`
			AppKeyPublicMatchesCert  bool  `json:"app_key_public_matches_cert"`
			QuoteSignatureValid      bool  `json:"quote_signature_valid"`
			NonceValid               bool  `json:"nonce_valid"`
			Timestamp                int64 `json:"timestamp"`
		} `json:"verification_details"`
		AttestedClaims AttestedClaimsJSON `json:"attested_claims"`
		AuditID        string             `json:"audit_id"`
	} `json:"results"`
}

// AttestedClaimsJSON represents the attested claims in JSON format
type AttestedClaimsJSON struct {
	Geolocation        string `json:"geolocation"`
	HostIntegrityStatus string `json:"host_integrity_status"`
	GPUMetricsHealth   struct {
		Status        string  `json:"status"`
		UtilizationPct float64 `json:"utilization_pct"`
		MemoryMB      int64   `json:"memory_mb"`
	} `json:"gpu_metrics_health"`
}

// NewClient creates a new stubbed Keylime Verifier client
func NewClient(baseURL string, log logrus.FieldLogger) *Client {
	if baseURL == "" {
		baseURL = DefaultKeylimeVerifierURL
	}

	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: DefaultTimeout,
		},
		log: log,
	}
}

// VerifyEvidence forwards sovereign attestation evidence to Keylime Verifier
// and returns the attested claims. This is a stubbed implementation that returns
// fixed hardcoded claims for Phase 1.
func (c *Client) VerifyEvidence(ctx context.Context, attestation *workload.SovereignAttestation) (*workload.AttestedClaims, error) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Check if Unified-Identity feature flag is enabled
	if !fflag.IsSet(fflag.FlagUnifiedIdentity) {
		c.log.Debug("Unified-Identity feature flag is not enabled, skipping Keylime verification")
		return nil, fmt.Errorf("Unified-Identity feature flag is not enabled")
	}

	// Validate input first (before accessing fields)
	if err := c.validateAttestation(attestation); err != nil {
		c.log.WithError(err).Error("Unified-Identity - Phase 1: Invalid sovereign attestation")
		return nil, fmt.Errorf("invalid attestation: %w", err)
	}

	c.log.WithFields(logrus.Fields{
		"nonce":               attestation.ChallengeNonce,
		"has_tpm_quote":      attestation.TpmSignedAttestation != "",
		"has_app_key":        attestation.AppKeyPublic != "",
		"has_app_key_cert":   len(attestation.AppKeyCertificate) > 0,
		"workload_code_hash": attestation.WorkloadCodeHash,
	}).Info("Unified-Identity - Phase 1: Processing sovereign attestation request (stubbed Keylime)")

	// Build request for Keylime Verifier
	req := c.buildVerifyRequest(attestation)

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// In Phase 1, we stub the Keylime Verifier and return fixed hardcoded claims
	// This allows us to test the SPIRE API and policy logic without a functional Keylime
	c.log.Info("Unified-Identity - Phase 1: Using stubbed Keylime Verifier (returning fixed claims)")

	// Return stubbed/hardcoded claims for Phase 1
	// These claims represent a successful verification with Spain geolocation
	claims := &workload.AttestedClaims{
		Geolocation:        "Spain: N40.4168, W3.7038",
		HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
		GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
			Status:        "healthy",
			UtilizationPct: 15.0,
			MemoryMb:     10240,
		},
	}

	c.log.WithFields(logrus.Fields{
		"geolocation":        claims.Geolocation,
		"host_integrity":     claims.HostIntegrityStatus.String(),
		"gpu_status":         claims.GpuMetricsHealth.Status,
		"gpu_utilization":    claims.GpuMetricsHealth.UtilizationPct,
		"gpu_memory_mb":      claims.GpuMetricsHealth.MemoryMb,
	}).Info("Unified-Identity - Phase 1: Returning stubbed attested claims from Keylime Verifier")

	// Log the request (for debugging, but don't log sensitive data)
	c.log.WithField("request_metadata_source", req.Metadata.Source).
		WithField("request_metadata_submission_type", req.Metadata.SubmissionType).
		Debug("Unified-Identity - Phase 1: Keylime verify evidence request prepared")

	return claims, nil
}

// validateAttestation validates the sovereign attestation input
func (c *Client) validateAttestation(attestation *workload.SovereignAttestation) error {
	if attestation == nil {
		return fmt.Errorf("attestation cannot be nil")
	}

	if attestation.TpmSignedAttestation == "" {
		return fmt.Errorf("tpm_signed_attestation is required")
	}

	// Validate base64 encoding
	if _, err := base64.StdEncoding.DecodeString(attestation.TpmSignedAttestation); err != nil {
		return fmt.Errorf("tpm_signed_attestation must be valid base64: %w", err)
	}

	// Validate size (max 64 KiB)
	if len(attestation.TpmSignedAttestation) > 64*1024 {
		return fmt.Errorf("tpm_signed_attestation exceeds maximum size of 64 KiB")
	}

	if attestation.ChallengeNonce == "" {
		return fmt.Errorf("challenge_nonce is required")
	}

	if attestation.AppKeyPublic == "" {
		return fmt.Errorf("app_key_public is required")
	}

	return nil
}

// buildVerifyRequest builds the Keylime Verifier API request from the sovereign attestation
func (c *Client) buildVerifyRequest(attestation *workload.SovereignAttestation) *VerifyEvidenceRequest {
	req := &VerifyEvidenceRequest{}

	// Set data fields
	req.Data.Nonce = attestation.ChallengeNonce
	req.Data.Quote = attestation.TpmSignedAttestation
	req.Data.HashAlg = "sha256"
	req.Data.AppKeyPublic = attestation.AppKeyPublic

	// Encode app_key_certificate as base64 if present
	if len(attestation.AppKeyCertificate) > 0 {
		req.Data.AppKeyCertificate = base64.StdEncoding.EncodeToString(attestation.AppKeyCertificate)
	}

	// Set metadata
	req.Metadata.Source = "SPIRE Server"
	req.Metadata.SubmissionType = "PoR/tpm-app-key"

	return req
}

// String returns a string representation of the request (for logging)
func (r *VerifyEvidenceRequest) String() string {
	data, _ := json.Marshal(r)
	return string(data)
}

