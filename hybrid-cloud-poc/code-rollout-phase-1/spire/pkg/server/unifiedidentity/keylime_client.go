// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Package unifiedidentity provides server-side integration for Unified Identity features
package unifiedidentity

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// KeylimeClient provides a client for communicating with the Keylime Verifier
type KeylimeClient struct {
	BaseURL    string
	HTTPClient *http.Client
	Log        logrus.FieldLogger
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// VerificationRequest represents the request sent to Keylime Verifier
type VerificationRequest struct {
	Data struct {
		Nonce            string `json:"nonce"`
		Quote            string `json:"quote"`
		HashAlg          string `json:"hash_alg"`
		AppKeyPublic     string `json:"app_key_public"`
		AppKeyCertificate string `json:"app_key_certificate"`
		TPMAK            string `json:"tpm_ak,omitempty"`
		TPMEK            string `json:"tpm_ek,omitempty"`
	} `json:"data"`
	Metadata struct {
		Source         string `json:"source"`
		SubmissionType string `json:"submission_type"`
		AuditID        string `json:"audit_id,omitempty"`
	} `json:"metadata"`
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// VerificationResponse represents the response from Keylime Verifier
type VerificationResponse struct {
	Results struct {
		Verified            bool `json:"verified"`
		VerificationDetails struct {
			AppKeyCertificateValid bool  `json:"app_key_certificate_valid"`
			AppKeyPublicMatchesCert bool  `json:"app_key_public_matches_cert"`
			QuoteSignatureValid     bool  `json:"quote_signature_valid"`
			NonceValid              bool  `json:"nonce_valid"`
			Timestamp               int64 `json:"timestamp"`
		} `json:"verification_details"`
		AttestedClaims AttestedClaimsJSON `json:"attested_claims"`
		AuditID        string              `json:"audit_id"`
	} `json:"results"`
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// AttestedClaimsJSON represents the JSON structure of attested claims
type AttestedClaimsJSON struct {
	Geolocation        string `json:"geolocation"`
	HostIntegrityStatus string `json:"host_integrity_status"`
	GPUMetricsHealth   struct {
		Status        string  `json:"status"`
		UtilizationPct float64 `json:"utilization_pct"`
		MemoryMB      int64   `json:"memory_mb"`
	} `json:"gpu_metrics_health"`
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// NewKeylimeClient creates a new Keylime client
func NewKeylimeClient(baseURL string, log logrus.FieldLogger) *KeylimeClient {
	return &KeylimeClient{
		BaseURL: baseURL,
		HTTPClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		Log: log,
	}
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// VerifyEvidence sends a verification request to Keylime and returns attested claims
func (c *KeylimeClient) VerifyEvidence(ctx context.Context, attestation *workload.SovereignAttestation) (*workload.AttestedClaims, error) {
	if attestation == nil {
		return nil, fmt.Errorf("attestation cannot be nil")
	}

	c.Log.WithFields(logrus.Fields{
		"nonce":            attestation.ChallengeNonce,
		"has_quote":        attestation.TpmSignedAttestation != "",
		"has_app_key":      attestation.AppKeyPublic != "",
		"has_certificate":  len(attestation.AppKeyCertificate) > 0,
		"workload_hash":    attestation.WorkloadCodeHash,
	}).Debug("[Unified-Identity Phase 1] Sending verification request to Keylime")

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Prepare request
	reqBody := VerificationRequest{
		Data: struct {
			Nonce            string `json:"nonce"`
			Quote            string `json:"quote"`
			HashAlg          string `json:"hash_alg"`
			AppKeyPublic     string `json:"app_key_public"`
			AppKeyCertificate string `json:"app_key_certificate"`
			TPMAK            string `json:"tpm_ak,omitempty"`
			TPMEK            string `json:"tpm_ek,omitempty"`
		}{
			Nonce:            attestation.ChallengeNonce,
			Quote:            attestation.TpmSignedAttestation,
			HashAlg:          "sha256",
			AppKeyPublic:     attestation.AppKeyPublic,
			AppKeyCertificate: base64.StdEncoding.EncodeToString(attestation.AppKeyCertificate),
		},
		Metadata: struct {
			Source         string `json:"source"`
			SubmissionType string `json:"submission_type"`
			AuditID        string `json:"audit_id,omitempty"`
		}{
			Source:         "SPIRE Server",
			SubmissionType: "PoR/tpm-app-key",
		},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		c.Log.WithError(err).Error("[Unified-Identity Phase 1] Failed to marshal verification request")
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Send HTTP request
	url := fmt.Sprintf("%s/v2.4/verify/evidence", c.BaseURL)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(jsonData))
	if err != nil {
		c.Log.WithError(err).Error("[Unified-Identity Phase 1] Failed to create HTTP request")
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		c.Log.WithError(err).Error("[Unified-Identity Phase 1] Failed to send request to Keylime")
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		c.Log.WithError(err).Error("[Unified-Identity Phase 1] Failed to read response body")
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		c.Log.WithFields(logrus.Fields{
			"status_code": resp.StatusCode,
			"body":        string(body),
		}).Error("[Unified-Identity Phase 1] Keylime returned error status")
		return nil, fmt.Errorf("keylime returned status %d: %s", resp.StatusCode, string(body))
	}

	var keylimeResp VerificationResponse
	if err := json.Unmarshal(body, &keylimeResp); err != nil {
		c.Log.WithError(err).Error("[Unified-Identity Phase 1] Failed to unmarshal response")
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if !keylimeResp.Results.Verified {
		c.Log.Warn("[Unified-Identity Phase 1] Keylime verification failed")
		return nil, fmt.Errorf("keylime verification failed")
	}

	c.Log.WithFields(logrus.Fields{
		"geolocation":        keylimeResp.Results.AttestedClaims.Geolocation,
		"integrity_status":   keylimeResp.Results.AttestedClaims.HostIntegrityStatus,
		"gpu_status":         keylimeResp.Results.AttestedClaims.GPUMetricsHealth.Status,
		"audit_id":           keylimeResp.Results.AuditID,
	}).Info("[Unified-Identity Phase 1] Successfully verified attestation with Keylime")

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Convert to protobuf format
	return convertToProtoAttestedClaims(keylimeResp.Results.AttestedClaims), nil
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// convertToProtoAttestedClaims converts JSON AttestedClaims to protobuf format
func convertToProtoAttestedClaims(jsonClaims AttestedClaimsJSON) *workload.AttestedClaims {
	claims := &workload.AttestedClaims{
		Geolocation: jsonClaims.Geolocation,
	}

	// Convert host integrity status
	switch jsonClaims.HostIntegrityStatus {
	case "passed_all_checks":
		claims.HostIntegrityStatus = workload.AttestedClaims_PASSED_ALL_CHECKS
	case "failed":
		claims.HostIntegrityStatus = workload.AttestedClaims_FAILED
	case "partial":
		claims.HostIntegrityStatus = workload.AttestedClaims_PARTIAL
	default:
		claims.HostIntegrityStatus = workload.AttestedClaims_HOST_INTEGRITY_UNSPECIFIED
	}

	// Convert GPU metrics
	if jsonClaims.GPUMetricsHealth.Status != "" {
		claims.GpuMetricsHealth = &workload.AttestedClaims_GpuMetrics{
			Status:        jsonClaims.GPUMetricsHealth.Status,
			UtilizationPct: jsonClaims.GPUMetricsHealth.UtilizationPct,
			MemoryMb:     jsonClaims.GPUMetricsHealth.MemoryMB,
		}
	}

	return claims
}

