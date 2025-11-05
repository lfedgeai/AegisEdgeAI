// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Integration tests for feature flag behavior
package integration

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/server/unifiedidentity"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFullFlow_FeatureFlagDisabled tests the complete flow with feature flag disabled
func TestFullFlow_FeatureFlagDisabled(t *testing.T) {
	// Setup: Ensure feature flag is disabled
	fflag.Unload()
	defer fflag.Unload()

	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity), "Feature flag should be disabled")

	// Create Keylime server (even if feature flag is off, the server should still work)
	keylimeServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		response := map[string]interface{}{
			"results": map[string]interface{}{
				"verified": true,
				"attested_claims": map[string]interface{}{
					"geolocation":        "Spain: N40.4168, W3.7038",
					"host_integrity_status": "passed_all_checks",
				},
			},
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	}))
	defer keylimeServer.Close()

	// Create attestation
	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
		AppKeyPublic:         "test-key",
		ChallengeNonce:       "test-nonce",
	}

	// Keylime client should work regardless of feature flag
	client := unifiedidentity.NewKeylimeClient(keylimeServer.URL, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	claims, err := client.VerifyEvidence(ctx, attestation)
	require.NoError(t, err)
	require.NotNil(t, claims)

	// Policy evaluation should work regardless of feature flag
	policyConfig := unifiedidentity.DefaultPolicyConfig()
	result := unifiedidentity.EvaluatePolicy(claims, policyConfig, nil)
	assert.True(t, result.Allowed)
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFullFlow_FeatureFlagEnabled tests the complete flow with feature flag enabled
func TestFullFlow_FeatureFlagEnabled(t *testing.T) {
	// Setup: Enable feature flag
	fflag.Unload()
	err := fflag.Load(fflag.RawConfig{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity), "Feature flag should be enabled")

	// Create Keylime server
	keylimeServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		response := map[string]interface{}{
			"results": map[string]interface{}{
				"verified": true,
				"verification_details": map[string]interface{}{
					"app_key_certificate_valid": true,
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

	// Create attestation
	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
		AppKeyPublic:         "test-key",
		AppKeyCertificate:    []byte("test-cert"),
		ChallengeNonce:       "test-nonce",
		WorkloadCodeHash:     "test-hash",
	}

	// Verify with Keylime
	client := unifiedidentity.NewKeylimeClient(keylimeServer.URL, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	claims, err := client.VerifyEvidence(ctx, attestation)
	require.NoError(t, err)
	require.NotNil(t, claims)

	// Verify claims
	assert.Equal(t, "Spain: N40.4168, W3.7038", claims.Geolocation)
	assert.Equal(t, workload.AttestedClaims_PASSED_ALL_CHECKS, claims.HostIntegrityStatus)
	assert.NotNil(t, claims.GpuMetricsHealth)

	// Evaluate policy
	policyConfig := unifiedidentity.DefaultPolicyConfig()
	result := unifiedidentity.EvaluatePolicy(claims, policyConfig, nil)

	// Should pass
	assert.True(t, result.Allowed)
	assert.Contains(t, result.Reason, "all policy checks passed")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagToggle tests toggling the feature flag on and off
func TestFeatureFlagToggle(t *testing.T) {
	// Start with flag disabled
	fflag.Unload()
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Enable flag
	err := fflag.Load(fflag.RawConfig{"Unified-Identity"})
	require.NoError(t, err)
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unload
	fflag.Unload()
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Can't use IsSet after Unload without reloading
	// But we can reload
	err = fflag.Load(fflag.RawConfig{"Unified-Identity"})
	require.NoError(t, err)
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	fflag.Unload()
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestBackwardCompatibility tests that existing functionality still works
// with feature flag disabled
func TestBackwardCompatibility(t *testing.T) {
	// Ensure feature flag is disabled
	fflag.Unload()
	defer fflag.Unload()

	// Test that policy evaluation works with old-style claims (no GPU metrics)
	claims := &workload.AttestedClaims{
		Geolocation:        "Spain: N40.4168, W3.7038",
		HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
		// No GPU metrics - should still work
	}

	policyConfig := unifiedidentity.DefaultPolicyConfig()
	// Disable GPU requirement for this test
	policyConfig.RequireHealthyGPU = false
	result := unifiedidentity.EvaluatePolicy(claims, policyConfig, nil)

	assert.True(t, result.Allowed)
}

