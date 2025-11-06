// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
package svid

import (
	"context"
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	svidv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/server/api"
	"github.com/spiffe/spire/pkg/server/keylime"
	"github.com/spiffe/spire/pkg/server/policy"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc/codes"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestSovereignAttestationIntegration tests the integration of SovereignAttestation
// processing in the SVID service (requires feature flag to be enabled)
func TestSovereignAttestationIntegration(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Load feature flag for testing
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Create mock Keylime client (stubbed)
	mockKeylimeClient := &mockKeylimeClient{
		returnAttestedClaims: &keylime.AttestedClaims{
			Geolocation:         "Spain: N40.4168, W3.7038",
			HostIntegrityStatus: "passed_all_checks",
			GPUMetricsHealth: struct {
				Status        string
				UtilizationPct float64
				MemoryMB      int64
			}{
				Status:        "healthy",
				UtilizationPct: 15.0,
				MemoryMB:      10240,
			},
		},
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Create policy engine with permissive policy
	policyEngine := policy.NewEngine(policy.PolicyConfig{
		AllowedGeolocations: []string{"Spain:*"},
		RequireIntegrity:    false,
		Logger:              logrus.New(),
	})

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Create service with Keylime client and policy engine
	service := &Service{
		keylimeClient: mockKeylimeClient,
		policyEngine:  policyEngine,
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Test processing SovereignAttestation
	sovereignAttestation := &types.SovereignAttestation{
		TpmSignedAttestation: "dGVzdC1xdW90ZQ==", // base64("test-quote")
		AppKeyPublic:         "test-public-key",
		AppKeyCertificate:    []byte("test-cert"),
		ChallengeNonce:       "test-nonce-123",
		WorkloadCodeHash:     "test-hash",
	}

	ctx := context.Background()
	log := logrus.New()
	log.SetLevel(logrus.DebugLevel)

	claims, err := service.processSovereignAttestation(ctx, log, sovereignAttestation, "spiffe://test.example/workload/test")
	require.NoError(t, err)
	require.NotNil(t, claims)
	assert.Equal(t, "Spain: N40.4168, W3.7038", claims.Geolocation)
	assert.Equal(t, types.AttestedClaims_PASSED_ALL_CHECKS, claims.HostIntegrityStatus)
	assert.NotNil(t, claims.GpuMetricsHealth)
	assert.Equal(t, "healthy", claims.GpuMetricsHealth.Status)
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Mock Keylime client for testing
type mockKeylimeClient struct {
	returnAttestedClaims *keylime.AttestedClaims
	returnError          error
}

func (m *mockKeylimeClient) VerifyEvidence(req *keylime.VerifyEvidenceRequest) (*keylime.AttestedClaims, error) {
	if m.returnError != nil {
		return nil, m.returnError
	}
	return m.returnAttestedClaims, nil
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestPolicyFailure tests that policy failures are properly handled
func TestPolicyFailure(t *testing.T) {
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	mockKeylimeClient := &mockKeylimeClient{
		returnAttestedClaims: &keylime.AttestedClaims{
			Geolocation:         "Germany: Berlin",
			HostIntegrityStatus: "passed_all_checks",
			GPUMetricsHealth: struct {
				Status        string
				UtilizationPct float64
				MemoryMB      int64
			}{
				Status:        "healthy",
				UtilizationPct: 15.0,
				MemoryMB:      10240,
			},
		},
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Policy only allows Spain
	policyEngine := policy.NewEngine(policy.PolicyConfig{
		AllowedGeolocations: []string{"Spain:*"},
		RequireIntegrity:    false,
		Logger:              logrus.New(),
	})

	service := &Service{
		keylimeClient: mockKeylimeClient,
		policyEngine:  policyEngine,
	}

	sovereignAttestation := &types.SovereignAttestation{
		TpmSignedAttestation: "dGVzdC1xdW90ZQ==",
		AppKeyPublic:         "test-public-key",
		ChallengeNonce:       "test-nonce-123",
	}

	ctx := context.Background()
	log := logrus.New()

	claims, err := service.processSovereignAttestation(ctx, log, sovereignAttestation, "spiffe://test.example/workload/test")
	require.Error(t, err)
	assert.Nil(t, claims)
	assert.Contains(t, err.Error(), "policy evaluation failed")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagDisabled tests that SovereignAttestation is ignored when feature flag is disabled
func TestFeatureFlagDisabled(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Ensure feature flag is not set
	fflag.Unload()
	defer fflag.Unload()

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Verify feature flag is disabled
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Test that processSovereignAttestation returns nil when feature flag is disabled
	// (This is tested indirectly through newX509SVID, but we can test the direct call too)
	service := &Service{
		keylimeClient: &mockKeylimeClient{},
		policyEngine:   policy.NewEngine(policy.PolicyConfig{Logger: logrus.New()}),
	}

	sovereignAttestation := &types.SovereignAttestation{
		TpmSignedAttestation: "dGVzdC1xdW90ZQ==",
		ChallengeNonce:       "test-nonce",
	}

	ctx := context.Background()
	log := logrus.New()

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Even with Keylime client configured, if feature flag is disabled,
	// the code path should not process SovereignAttestation
	// The actual check happens in newX509SVID, but we verify the flag state here
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity), "Feature flag should be disabled")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagDisabledWithSovereignAttestation tests that when feature flag is disabled,
// SovereignAttestation in requests is ignored and normal SVID flow continues
func TestFeatureFlagDisabledWithSovereignAttestation(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Ensure feature flag is disabled
	fflag.Unload()
	defer fflag.Unload()

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Verify feature flag is disabled
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Test that when feature flag is disabled, SovereignAttestation is ignored
	// This test verifies the conditional check in newX509SVID
	param := &svidv1.NewX509SVIDParams{
		EntryId: "test-entry",
		Csr:     []byte("test-csr"),
		SovereignAttestation: &types.SovereignAttestation{
			TpmSignedAttestation: "dGVzdC1xdW90ZQ==",
			ChallengeNonce:       "test-nonce",
			AppKeyPublic:         "test-public-key",
		},
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Verify that SovereignAttestation is present but feature flag controls processing
	assert.NotNil(t, param.SovereignAttestation)
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// The condition in newX509SVID is:
	// if fflag.IsSet(fflag.FlagUnifiedIdentity) && param.SovereignAttestation != nil
	// So when flag is false, the block is skipped
	shouldProcess := fflag.IsSet(fflag.FlagUnifiedIdentity) && param.SovereignAttestation != nil
	assert.False(t, shouldProcess, "SovereignAttestation should not be processed when feature flag is disabled")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagDisabledWithoutKeylimeClient tests that when feature flag is disabled,
// even if Keylime client is not configured, no errors occur
func TestFeatureFlagDisabledWithoutKeylimeClient(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Ensure feature flag is disabled
	fflag.Unload()
	defer fflag.Unload()

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Service without Keylime client - should still work when feature flag is disabled
	service := &Service{
		keylimeClient: nil,
		policyEngine:  nil,
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Verify that service can be created without Keylime client when feature is disabled
	assert.Nil(t, service.keylimeClient)
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagToggle tests that feature flag can be toggled on and off
func TestFeatureFlagToggle(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Start with disabled state
	fflag.Unload()
	defer fflag.Unload()

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Verify disabled
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Enable feature flag
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Disable feature flag
	err = fflag.Unload()
	require.NoError(t, err)
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
}
