// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// This is a stub implementation of the Keylime Verifier API for Phase 1 testing.
// It validates mTLS calls and returns fixed, hardcoded AttestedClaims responses.
package main

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/sirupsen/logrus"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// VerifyEvidenceRequest represents the request sent to Keylime Verifier
type VerifyEvidenceRequest struct {
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
// AttestedClaimsResponse represents the verified facts from Keylime
type AttestedClaimsResponse struct {
	Geolocation         string `json:"geolocation"`
	HostIntegrityStatus string `json:"host_integrity_status"`
	GPUMetricsHealth    struct {
		Status        string  `json:"status"`
		UtilizationPct float64 `json:"utilization_pct"`
		MemoryMB      int64   `json:"memory_mb"`
	} `json:"gpu_metrics_health"`
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// VerifyEvidenceResponse represents the response from Keylime Verifier
type VerifyEvidenceResponse struct {
	Results struct {
		Verified            bool   `json:"verified"`
		VerificationDetails struct {
			AppKeyCertificateValid bool   `json:"app_key_certificate_valid"`
			AppKeyPublicMatchesCert bool   `json:"app_key_public_matches_cert"`
			QuoteSignatureValid    bool   `json:"quote_signature_valid"`
			NonceValid             bool   `json:"nonce_valid"`
			Timestamp              int64  `json:"timestamp"`
		} `json:"verification_details"`
		AttestedClaims AttestedClaimsResponse `json:"attested_claims"`
		AuditID        string                 `json:"audit_id"`
	} `json:"results"`
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Stubbed Keylime Verifier that returns fixed AttestedClaims
type KeylimeStub struct {
	logger *logrus.Logger
	// Stubbed response data - can be configured via environment variables
	stubbedGeolocation string
	stubbedIntegrity   string
	stubbedGPUStatus   string
	// Whether to require mTLS (only when TLS is enabled)
	requireMTLS bool
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// NewKeylimeStub creates a new Keylime stub instance
func NewKeylimeStub() *KeylimeStub {
	logger := logrus.New()
	logger.SetLevel(logrus.InfoLevel)
	logger.SetFormatter(&logrus.TextFormatter{
		FullTimestamp: true,
	})

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Allow configuration via environment variables for testing
	requireMTLS := getEnvOrDefault("KEYLIME_STUB_REQUIRE_MTLS", "false") == "true"
	stub := &KeylimeStub{
		logger:             logger,
		stubbedGeolocation: getEnvOrDefault("KEYLIME_STUB_GEOLOCATION", "Spain: N40.4168, W3.7038"),
		stubbedIntegrity:   getEnvOrDefault("KEYLIME_STUB_INTEGRITY", "passed_all_checks"),
		stubbedGPUStatus:   getEnvOrDefault("KEYLIME_STUB_GPU_STATUS", "healthy"),
		requireMTLS:        requireMTLS,
	}

	stub.logger.WithFields(logrus.Fields{
		"geolocation": stub.stubbedGeolocation,
		"integrity":   stub.stubbedIntegrity,
		"gpu_status":  stub.stubbedGPUStatus,
	}).Info("Unified-Identity - Phase 1: Keylime stub initialized with stubbed values")

	return stub
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// VerifyEvidence handles POST /v2.4/verify/evidence requests
func (ks *KeylimeStub) VerifyEvidence(w http.ResponseWriter, r *http.Request) {
	ks.logger.WithField("method", r.Method).WithField("path", r.URL.Path).Info("Unified-Identity - Phase 1: Received verify evidence request")

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Validate mTLS only if required (when TLS is enabled)
	if ks.requireMTLS {
		if r.TLS == nil || len(r.TLS.PeerCertificates) == 0 {
			ks.logger.Warn("Unified-Identity - Phase 1: Request missing mTLS client certificate")
			http.Error(w, "mTLS authentication required", http.StatusUnauthorized)
			return
		}

		clientCert := r.TLS.PeerCertificates[0]
		ks.logger.WithFields(logrus.Fields{
			"subject":      clientCert.Subject.String(),
			"issuer":       clientCert.Issuer.String(),
			"serial":       clientCert.SerialNumber.String(),
		}).Info("Unified-Identity - Phase 1: Validated mTLS client certificate")
	} else {
		ks.logger.Debug("Unified-Identity - Phase 1: mTLS not required (Phase 1 testing mode)")
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Parse request body
	var req VerifyEvidenceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		ks.logger.WithError(err).Error("Unified-Identity - Phase 1: Failed to parse request body")
		http.Error(w, fmt.Sprintf("invalid request: %v", err), http.StatusBadRequest)
		return
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Basic validation of required fields
	if req.Data.Nonce == "" {
		ks.logger.Warn("Unified-Identity - Phase 1: Missing nonce in request")
		http.Error(w, "missing required field: data.nonce", http.StatusBadRequest)
		return
	}

	if req.Data.Quote == "" {
		ks.logger.Warn("Unified-Identity - Phase 1: Missing quote in request")
		http.Error(w, "missing required field: data.quote", http.StatusBadRequest)
		return
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Validate base64 encoding of quote (stub validation)
	if _, err := base64.StdEncoding.DecodeString(req.Data.Quote); err != nil {
		ks.logger.WithError(err).Warn("Unified-Identity - Phase 1: Invalid base64 encoding in quote")
		http.Error(w, "invalid base64 encoding in data.quote", http.StatusUnprocessableEntity)
		return
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Log request details for debugging
	ks.logger.WithFields(logrus.Fields{
		"nonce":            req.Data.Nonce,
		"hash_alg":         req.Data.HashAlg,
		"submission_type":  req.Metadata.SubmissionType,
		"source":           req.Metadata.Source,
		"quote_length":      len(req.Data.Quote),
		"has_app_key_cert":  req.Data.AppKeyCertificate != "",
		"has_app_key_pub":   req.Data.AppKeyPublic != "",
	}).Info("Unified-Identity - Phase 1: Processing verify evidence request (stubbed)")

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Generate audit ID
	auditID := fmt.Sprintf("stub-audit-%d", time.Now().UnixNano())

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Create stubbed response with fixed AttestedClaims
	response := VerifyEvidenceResponse{
		Results: struct {
			Verified            bool   `json:"verified"`
			VerificationDetails struct {
				AppKeyCertificateValid bool   `json:"app_key_certificate_valid"`
				AppKeyPublicMatchesCert bool   `json:"app_key_public_matches_cert"`
				QuoteSignatureValid    bool   `json:"quote_signature_valid"`
				NonceValid             bool   `json:"nonce_valid"`
				Timestamp              int64  `json:"timestamp"`
			} `json:"verification_details"`
			AttestedClaims AttestedClaimsResponse `json:"attested_claims"`
			AuditID        string                 `json:"audit_id"`
		}{
			Verified: true,
			VerificationDetails: struct {
				AppKeyCertificateValid bool   `json:"app_key_certificate_valid"`
				AppKeyPublicMatchesCert bool   `json:"app_key_public_matches_cert"`
				QuoteSignatureValid    bool   `json:"quote_signature_valid"`
				NonceValid             bool   `json:"nonce_valid"`
				Timestamp              int64  `json:"timestamp"`
			}{
				AppKeyCertificateValid: true,
				AppKeyPublicMatchesCert: true,
				QuoteSignatureValid:    true,
				NonceValid:             true,
				Timestamp:              time.Now().Unix(),
			},
			AttestedClaims: AttestedClaimsResponse{
				Geolocation:         ks.stubbedGeolocation,
				HostIntegrityStatus: ks.stubbedIntegrity,
				GPUMetricsHealth: struct {
					Status        string  `json:"status"`
					UtilizationPct float64 `json:"utilization_pct"`
					MemoryMB      int64   `json:"memory_mb"`
				}{
					Status:        ks.stubbedGPUStatus,
					UtilizationPct: 15.0,
					MemoryMB:      10240,
				},
			},
			AuditID: auditID,
		},
	}

	ks.logger.WithFields(logrus.Fields{
		"audit_id":      auditID,
		"geolocation":   response.Results.AttestedClaims.Geolocation,
		"integrity":     response.Results.AttestedClaims.HostIntegrityStatus,
		"gpu_status":    response.Results.AttestedClaims.GPUMetricsHealth.Status,
	}).Info("Unified-Identity - Phase 1: Returning stubbed AttestedClaims response")

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Send response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		ks.logger.WithError(err).Error("Unified-Identity - Phase 1: Failed to encode response")
	}
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Health check endpoint
func (ks *KeylimeStub) Health(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
		"mode":   "stub",
	})
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	port := getEnvOrDefault("KEYLIME_STUB_PORT", "8888")
	certFile := os.Getenv("KEYLIME_STUB_TLS_CERT")
	keyFile := os.Getenv("KEYLIME_STUB_TLS_KEY")

	stub := NewKeylimeStub()

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Setup routes
	mux := http.NewServeMux()
	mux.HandleFunc("/v2.4/verify/evidence", stub.VerifyEvidence)
	mux.HandleFunc("/health", stub.Health)

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Configure TLS if certificates are provided
	server := &http.Server{
		Addr:    ":" + port,
		Handler: mux,
		// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
		// Require mTLS client authentication
		TLSConfig: &tls.Config{
			ClientAuth: tls.RequireAndVerifyClientCert,
			ClientCAs:  nil, // In production, this would load CA certs
		},
	}

	stub.logger.WithFields(logrus.Fields{
		"port":     port,
		"tls_cert": certFile != "",
		"tls_key":  keyFile != "",
	}).Info("Unified-Identity - Phase 1: Starting Keylime stub server")

	if certFile != "" && keyFile != "" {
		// When TLS is enabled, require mTLS
		stub.requireMTLS = true
		log.Fatal(server.ListenAndServeTLS(certFile, keyFile))
	} else {
		// When running without TLS, don't require mTLS (Phase 1 testing)
		stub.requireMTLS = false
		stub.logger.Warn("Unified-Identity - Phase 1: Running without TLS (testing only)")
		// Remove TLS config when not using TLS
		server.TLSConfig = nil
		log.Fatal(server.ListenAndServe())
	}
}

