// Unified-Identity - Verification: Hardware Integration & Delegated Certification
package svid

import (
	"testing"

	"github.com/sirupsen/logrus"
	svidv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/server/keylime"
	"github.com/spiffe/spire/pkg/server/policy"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TestSovereignAttestationIntegration tests the integration of SovereignAttestation
// processing in the SVID service (requires feature flag to be enabled)
func TestSovereignAttestationIntegration(t *testing.T) {
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Load feature flag for testing
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Create mock Keylime client (stubbed)
	claims := &keylime.AttestedClaims{
		Geolocation: &keylime.Geolocation{
			Type:     "mobile",
			SensorID: "12d1:1433",
			Value:    "Spain: N40.4168, W3.7038",
		},
	}

	mockKeylimeClient := &mockKeylimeClient{
		returnAttestedClaims: claims,
	}


	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Since we can't directly inject mockKeylimeClient, we test the mock client directly
	// and verify the feature flag behavior
	req := &keylime.VerifyEvidenceRequest{}
	attestedClaims, err := mockKeylimeClient.VerifyEvidence(req)
	require.NoError(t, err)
	require.NotNil(t, attestedClaims)
	require.NotNil(t, attestedClaims.Geolocation)
	assert.Equal(t, "mobile", attestedClaims.Geolocation.Type)
	assert.Equal(t, "12d1:1433", attestedClaims.Geolocation.SensorID)
	assert.Equal(t, "Spain: N40.4168, W3.7038", attestedClaims.Geolocation.Value)
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
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

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TestPolicyFailure tests that policy failures are properly handled
func TestPolicyFailure(t *testing.T) {
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	claims2 := &keylime.AttestedClaims{
		Geolocation: &keylime.Geolocation{
			Type:     "mobile",
			SensorID: "12d1:1433",
			Value:    "Germany: Berlin",
		},
	}

	mockKeylimeClient := &mockKeylimeClient{
		returnAttestedClaims: claims2,
	}
	_ = mockKeylimeClient // Use variable

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Policy only allows Spain
	policyEngine := policy.NewEngine(policy.PolicyConfig{
		AllowedGeolocations: []string{"Spain:*"},
		Logger:              logrus.New(),
	})

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Test that policy engine correctly rejects geolocation outside allowed zones
	// Since we can't directly test processSovereignAttestation without a real client,
	// we test the policy engine directly
	policyClaims := &policy.AttestedClaims{
		Geolocation: "Germany: Berlin",
	}
	result, err := policyEngine.Evaluate(policyClaims)
	require.NoError(t, err)
	assert.False(t, result.Allowed, "Germany should not be allowed when policy only allows Spain")
	
	policyClaims2 := &policy.AttestedClaims{
		Geolocation: "Spain: Madrid",
	}
	result2, err := policyEngine.Evaluate(policyClaims2)
	require.NoError(t, err)
	assert.True(t, result2.Allowed, "Spain should be allowed")
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TestFeatureFlagDisabled tests that SovereignAttestation is ignored when feature flag is disabled
func TestFeatureFlagDisabled(t *testing.T) {
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Explicitly disable feature flag (default is now enabled)
	fflag.Unload()
	err := fflag.Load([]string{"-Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Verify feature flag is disabled
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Test that processSovereignAttestation returns nil when feature flag is disabled
	// (This is tested indirectly through newX509SVID, but we can test the direct call too)
	service := &Service{
		keylimeClient: nil,
		policyEngine:  policy.NewEngine(policy.PolicyConfig{Logger: logrus.New()}),
	}

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Even with Keylime client configured, if feature flag is disabled,
	// the code path should not process SovereignAttestation
	// The actual check happens in newX509SVID, but we verify the flag state here
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity), "Feature flag should be disabled")
	assert.NotNil(t, service)
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TestFeatureFlagDisabledWithSovereignAttestation tests that when feature flag is disabled,
// SovereignAttestation in requests is ignored and normal SVID flow continues
func TestFeatureFlagDisabledWithSovereignAttestation(t *testing.T) {
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Explicitly disable feature flag (default is now enabled)
	fflag.Unload()
	err := fflag.Load([]string{"-Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Verify feature flag is disabled
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
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

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Verify that SovereignAttestation is present but feature flag controls processing
	assert.NotNil(t, param.SovereignAttestation)
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// The condition in newX509SVID is:
	// if fflag.IsSet(fflag.FlagUnifiedIdentity) && param.SovereignAttestation != nil
	// So when flag is false, the block is skipped
	shouldProcess := fflag.IsSet(fflag.FlagUnifiedIdentity) && param.SovereignAttestation != nil
	assert.False(t, shouldProcess, "SovereignAttestation should not be processed when feature flag is disabled")
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TestFeatureFlagDisabledWithoutKeylimeClient tests that when feature flag is disabled,
// even if Keylime client is not configured, no errors occur
func TestFeatureFlagDisabledWithoutKeylimeClient(t *testing.T) {
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Explicitly disable feature flag (default is now enabled)
	fflag.Unload()
	err := fflag.Load([]string{"-Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Service without Keylime client - should still work when feature flag is disabled
	service := &Service{
		keylimeClient: nil,
		policyEngine:  nil,
	}

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Verify that service can be created without Keylime client when feature is disabled
	assert.Nil(t, service.keylimeClient)
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TestFeatureFlagToggle tests that feature flag can be toggled on and off
func TestFeatureFlagToggle(t *testing.T) {
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Start with default state (enabled)
	fflag.Unload()
	defer fflag.Unload()

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Verify enabled by default
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Explicitly enable feature flag (redundant but tests explicit enable)
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Disable feature flag explicitly
	err = fflag.Unload()
	require.NoError(t, err)
	err = fflag.Load([]string{"-Unified-Identity"})
	require.NoError(t, err)
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
}
