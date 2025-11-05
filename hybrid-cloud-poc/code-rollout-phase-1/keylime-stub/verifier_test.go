// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
package keylime_stub

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/stretchr/testify/assert"
)

func TestVerifier_HandleVerifyEvidence(t *testing.T) {
	verifier := NewVerifier(0)
	server := httptest.NewServer(http.HandlerFunc(verifier.handleVerifyEvidence))
	defer server.Close()

	tests := []struct {
		name          string
		request       VerificationRequest
		expectedCode  int
		expectedVerified bool
	}{
		{
			name: "Valid request",
			request: VerificationRequest{
				Data: struct {
					Nonce            string `json:"nonce"`
					Quote            string `json:"quote"`
					HashAlg          string `json:"hash_alg"`
					AppKeyPublic     string `json:"app_key_public"`
					AppKeyCertificate string `json:"app_key_certificate"`
					TPMAK            string `json:"tpm_ak,omitempty"`
					TPMEK            string `json:"tpm_ek,omitempty"`
				}{
					Nonce:            "test-nonce-123",
					Quote:            base64.StdEncoding.EncodeToString([]byte("test-quote")),
					HashAlg:          "sha256",
					AppKeyPublic:     "test-public-key",
					AppKeyCertificate: base64.StdEncoding.EncodeToString([]byte("test-cert")),
				},
				Metadata: struct {
					Source         string `json:"source"`
					SubmissionType string `json:"submission_type"`
					AuditID        string `json:"audit_id,omitempty"`
				}{
					Source:         "SPIRE Server",
					SubmissionType: "PoR/tpm-app-key",
				},
			},
			expectedCode:      http.StatusOK,
			expectedVerified: true,
		},
		{
			name: "Missing nonce",
			request: VerificationRequest{
				Data: struct {
					Nonce            string `json:"nonce"`
					Quote            string `json:"quote"`
					HashAlg          string `json:"hash_alg"`
					AppKeyPublic     string `json:"app_key_public"`
					AppKeyCertificate string `json:"app_key_certificate"`
					TPMAK            string `json:"tpm_ak,omitempty"`
					TPMEK            string `json:"tpm_ek,omitempty"`
				}{
					Quote: base64.StdEncoding.EncodeToString([]byte("test-quote")),
				},
			},
			expectedCode: http.StatusBadRequest,
		},
		{
			name: "Invalid base64 quote",
			request: VerificationRequest{
				Data: struct {
					Nonce            string `json:"nonce"`
					Quote            string `json:"quote"`
					HashAlg          string `json:"hash_alg"`
					AppKeyPublic     string `json:"app_key_public"`
					AppKeyCertificate string `json:"app_key_certificate"`
					TPMAK            string `json:"tpm_ak,omitempty"`
					TPMEK            string `json:"tpm_ek,omitempty"`
				}{
					Nonce: "test-nonce",
					Quote: "invalid-base64!!!",
				},
			},
			expectedCode: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jsonData, err := json.Marshal(tt.request)
			assert.NoError(t, err)

			req := httptest.NewRequest(http.MethodPost, server.URL+"/v2.4/verify/evidence", jsonData)
			req.Header.Set("Content-Type", "application/json")

			resp, err := http.DefaultClient.Do(req)
			assert.NoError(t, err)
			defer resp.Body.Close()

			assert.Equal(t, tt.expectedCode, resp.StatusCode)

			if tt.expectedCode == http.StatusOK {
				var verificationResp VerificationResponse
				err := json.NewDecoder(resp.Body).Decode(&verificationResp)
				assert.NoError(t, err)
				assert.Equal(t, tt.expectedVerified, verificationResp.Results.Verified)
				assert.Equal(t, "Spain: N40.4168, W3.7038", verificationResp.Results.AttestedClaims.Geolocation)
				assert.Equal(t, "passed_all_checks", verificationResp.Results.AttestedClaims.HostIntegrityStatus)
			}
		})
	}
}

func TestConvertToProtoAttestedClaims(t *testing.T) {
	jsonClaims := AttestedClaimsJSON{
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
	}

	protoClaims := ConvertToProtoAttestedClaims(jsonClaims)

	assert.Equal(t, "Spain: N40.4168, W3.7038", protoClaims.Geolocation)
	assert.Equal(t, workload.AttestedClaims_PASSED_ALL_CHECKS, protoClaims.HostIntegrityStatus)
	assert.NotNil(t, protoClaims.GpuMetricsHealth)
	assert.Equal(t, "healthy", protoClaims.GpuMetricsHealth.Status)
	assert.Equal(t, 15.0, protoClaims.GpuMetricsHealth.UtilizationPct)
	assert.Equal(t, int64(10240), protoClaims.GpuMetricsHealth.MemoryMb)
}

