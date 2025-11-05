// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Tests for feature flag behavior
package unifiedidentity

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagDisabled tests behavior when feature flag is disabled
func TestFeatureFlagDisabled(t *testing.T) {
	// Ensure feature flag is unloaded before test
	fflag.Unload()

	// Verify feature flag is not set
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity), "Feature flag should be disabled by default")

	// Test that Keylime client can still be created (no panic)
	client := NewKeylimeClient("http://localhost:8888", nil)
	assert.NotNil(t, client)

	// Test that policy evaluation still works (doesn't depend on feature flag)
	// Create a logger for the test
	log := logrus.New()
	log.SetLevel(logrus.DebugLevel)
	
	claims := &workload.AttestedClaims{
		Geolocation:        "Spain: N40.4168, W3.7038",
		HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
	}
	result := EvaluatePolicy(claims, DefaultPolicyConfig(), log)
	assert.True(t, result.Allowed)
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagEnabled tests behavior when feature flag is enabled
func TestFeatureFlagEnabled(t *testing.T) {
	// Setup: Load feature flag
	fflag.Unload() // Clean state first
	err := fflag.Load(fflag.RawConfig{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	// Verify feature flag is set
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity), "Feature flag should be enabled")

	// Test Keylime client with feature flag enabled
	keylimeServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
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

	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
		AppKeyPublic:         "test-key",
		ChallengeNonce:       "test-nonce",
	}

	log := logrus.New()
	log.SetLevel(logrus.DebugLevel)
	client := NewKeylimeClient(keylimeServer.URL, log)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	claims, err := client.VerifyEvidence(ctx, attestation)
	require.NoError(t, err)
	require.NotNil(t, claims)
	assert.Equal(t, "Spain: N40.4168, W3.7038", claims.Geolocation)
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagMultipleLoads tests that feature flag cannot be loaded twice
func TestFeatureFlagMultipleLoads(t *testing.T) {
	fflag.Unload()
	
	err := fflag.Load(fflag.RawConfig{"Unified-Identity"})
	require.NoError(t, err)

	// Try to load again - should fail
	err = fflag.Load(fflag.RawConfig{"Unified-Identity"})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already been loaded")

	fflag.Unload()
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagUnknownFlag tests that unknown flags are rejected
func TestFeatureFlagUnknownFlag(t *testing.T) {
	fflag.Unload()

	err := fflag.Load(fflag.RawConfig{"Unknown-Flag"})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unknown feature flag")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagEmptyConfig tests that empty config is allowed
func TestFeatureFlagEmptyConfig(t *testing.T) {
	fflag.Unload()

	err := fflag.Load(fflag.RawConfig{})
	require.NoError(t, err)

	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
	fflag.Unload()
}

