// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// End-to-end test for Phase 1 implementation
package e2e

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/server/unifiedidentity"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestEndToEndFlow tests the complete flow from attestation to policy evaluation
func TestEndToEndFlow(t *testing.T) {
	// Setup: Create a mock Keylime Verifier server
	keylimeServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var req map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Bad request", http.StatusBadRequest)
			return
		}

		// Return fixed response
		response := map[string]interface{}{
			"results": map[string]interface{}{
				"verified": true,
				"verification_details": map[string]interface{}{
					"app_key_certificate_valid": true,
					"app_key_public_matches_cert": true,
					"quote_signature_valid":     true,
					"nonce_valid":              true,
					"timestamp":                time.Now().Unix(),
				},
				"attested_claims": map[string]interface{}{
					"geolocation":        "Spain: N40.4168, W3.7038",
					"host_integrity_status": "passed_all_checks",
					"gpu_metrics_health": map[string]interface{}{
						"status":         "healthy",
						"utilization_pct": 15.0,
						"memory_mb":      10240,
					},
				},
				"audit_id": "test-audit-id",
			},
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	}))
	defer keylimeServer.Close()

	// Step 1: Create a SovereignAttestation (stubbed data)
	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("stubbed-tpm-quote")),
		AppKeyPublic:         "stubbed-app-key-public",
		AppKeyCertificate:    []byte("stubbed-certificate"),
		ChallengeNonce:       "test-nonce-123",
		WorkloadCodeHash:     "stubbed-workload-hash",
	}

	// Step 2: Create Keylime client and verify evidence
	keylimeClient := unifiedidentity.NewKeylimeClient(keylimeServer.URL, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	claims, err := keylimeClient.VerifyEvidence(ctx, attestation)
	require.NoError(t, err)
	require.NotNil(t, claims)

	// Step 3: Verify claims content
	assert.Equal(t, "Spain: N40.4168, W3.7038", claims.Geolocation)
	assert.Equal(t, workload.AttestedClaims_PASSED_ALL_CHECKS, claims.HostIntegrityStatus)
	assert.NotNil(t, claims.GpuMetricsHealth)
	assert.Equal(t, "healthy", claims.GpuMetricsHealth.Status)
	assert.Equal(t, 15.0, claims.GpuMetricsHealth.UtilizationPct)
	assert.Equal(t, int64(10240), claims.GpuMetricsHealth.MemoryMb)

	// Step 4: Evaluate policy
	policyConfig := unifiedidentity.DefaultPolicyConfig()
	result := unifiedidentity.EvaluatePolicy(claims, policyConfig, nil)

	// Step 5: Verify policy evaluation
	assert.True(t, result.Allowed)
	assert.Contains(t, result.Reason, "all policy checks passed")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestPolicyViolation tests policy evaluation with violating claims
func TestPolicyViolation(t *testing.T) {
	// Create claims that violate policy (geolocation not allowed)
	claims := &workload.AttestedClaims{
		Geolocation:        "France: N48.8566, E2.3522", // Not in allowed list
		HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
		GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
			Status:        "healthy",
			UtilizationPct: 15.0,
			MemoryMb:     10240,
		},
	}

	policyConfig := unifiedidentity.DefaultPolicyConfig()
	result := unifiedidentity.EvaluatePolicy(claims, policyConfig, nil)

	assert.False(t, result.Allowed)
	assert.Contains(t, result.Reason, "not in allowed list")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestKeylimeClientErrorHandling tests error handling in Keylime client
func TestKeylimeClientErrorHandling(t *testing.T) {
	// Create a server that returns an error
	errorServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}))
	defer errorServer.Close()

	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
		AppKeyPublic:         "test-key",
		ChallengeNonce:       "test-nonce",
	}

	keylimeClient := unifiedidentity.NewKeylimeClient(errorServer.URL, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	claims, err := keylimeClient.VerifyEvidence(ctx, attestation)
	assert.Error(t, err)
	assert.Nil(t, claims)
	assert.Contains(t, err.Error(), "status 500")
}

