// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Package keylime_stub provides a stubbed implementation of the Keylime Verifier API
// for Phase 1 testing. This stub always returns fixed, hardcoded AttestedClaims
// without performing actual cryptographic verification.
package keylime_stub

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Verifier represents a stubbed Keylime Verifier that returns fixed attestation claims
type Verifier struct {
	Port     int
	CertPath string
	KeyPath  string
	server   *http.Server
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// VerificationRequest represents the request sent to Keylime Verifier
type VerificationRequest struct {
	Data struct {
		Nonce            string `json:"nonce"`
		Quote            string `json:"quote"` // Base64-encoded TPM Quote
		HashAlg          string `json:"hash_alg"`
		AppKeyPublic     string `json:"app_key_public"`
		AppKeyCertificate string `json:"app_key_certificate"` // Base64-encoded X.509 DER/PEM
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
// NewVerifier creates a new stubbed Keylime Verifier instance
func NewVerifier(port int) *Verifier {
	return &Verifier{
		Port: port,
	}
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Start starts the stubbed Keylime Verifier HTTP server
func (v *Verifier) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/v2.4/verify/evidence", v.handleVerifyEvidence)

	v.server = &http.Server{
		Addr:         fmt.Sprintf(":%d", v.Port),
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Printf("[Unified-Identity Phase 1] Starting stubbed Keylime Verifier on port %d", v.Port)
	return v.server.ListenAndServe()
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Stop stops the stubbed Keylime Verifier HTTP server
func (v *Verifier) Stop() error {
	if v.server == nil {
		return nil
	}
	log.Printf("[Unified-Identity Phase 1] Stopping stubbed Keylime Verifier")
	return v.server.Close()
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// handleVerifyEvidence handles the POST /v2.4/verify/evidence endpoint
// This is a stub implementation that always returns fixed AttestedClaims
func (v *Verifier) handleVerifyEvidence(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	log.Printf("[Unified-Identity Phase 1] Received verification request from %s", r.RemoteAddr)

	var req VerificationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("[Unified-Identity Phase 1] Error decoding request: %v", err)
		http.Error(w, fmt.Sprintf("Bad request: %v", err), http.StatusBadRequest)
		return
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Validate request fields (basic validation for stub)
	if req.Data.Nonce == "" {
		log.Printf("[Unified-Identity Phase 1] Missing nonce in request")
		http.Error(w, "Missing required field: nonce", http.StatusBadRequest)
		return
	}

	if req.Data.Quote == "" {
		log.Printf("[Unified-Identity Phase 1] Missing quote in request")
		http.Error(w, "Missing required field: quote", http.StatusBadRequest)
		return
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Validate base64 encoding (basic check)
	if _, err := base64.StdEncoding.DecodeString(req.Data.Quote); err != nil {
		log.Printf("[Unified-Identity Phase 1] Invalid base64 encoding for quote: %v", err)
		http.Error(w, "Invalid base64 encoding for quote", http.StatusBadRequest)
		return
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Return fixed, hardcoded AttestedClaims response
	// This simulates a successful verification from a host in Spain with healthy GPU metrics
	resp := VerificationResponse{
		Results: struct {
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
		}{
			Verified: true,
			VerificationDetails: struct {
				AppKeyCertificateValid bool  `json:"app_key_certificate_valid"`
				AppKeyPublicMatchesCert bool  `json:"app_key_public_matches_cert"`
				QuoteSignatureValid     bool  `json:"quote_signature_valid"`
				NonceValid              bool  `json:"nonce_valid"`
				Timestamp               int64 `json:"timestamp"`
			}{
				AppKeyCertificateValid: true,
				AppKeyPublicMatchesCert: true,
				QuoteSignatureValid:     true,
				NonceValid:              true,
				Timestamp:               time.Now().Unix(),
			},
			AttestedClaims: AttestedClaimsJSON{
				Geolocation:        "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: "passed_all_checks",
				GPUMetricsHealth: struct {
					Status        string  `json:"status"`
					UtilizationPct float64 `json:"utilization_pct"`
					MemoryMB      int64   `json:"memory_mb"`
				}{
					Status:        "healthy",
					UtilizationPct: 15.0,
					MemoryMB:      10240,
				},
			},
			AuditID: fmt.Sprintf("audit-%d", time.Now().UnixNano()),
		},
	}

	log.Printf("[Unified-Identity Phase 1] Returning stubbed verification response: verified=true, geolocation=%s",
		resp.Results.AttestedClaims.Geolocation)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("[Unified-Identity Phase 1] Error encoding response: %v", err)
	}
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// ConvertToProtoAttestedClaims converts JSON AttestedClaims to protobuf format
func ConvertToProtoAttestedClaims(jsonClaims AttestedClaimsJSON) *workload.AttestedClaims {
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

