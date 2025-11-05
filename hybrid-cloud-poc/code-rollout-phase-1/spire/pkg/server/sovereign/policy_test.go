// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
package sovereign

import (
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDefaultPolicyConfig(t *testing.T) {
	config := DefaultPolicyConfig()
	assert.NotNil(t, config)
	assert.Contains(t, config.AllowedGeolocations, "Spain")
}

func TestEvaluatePolicy_FeatureFlagDisabled(t *testing.T) {
	_ = fflag.Unload()

	log := logrus.New()
	config := DefaultPolicyConfig()
	claims := &workload.AttestedClaims{
		Geolocation:        "Spain: N40.4168, W3.7038",
		HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
	}

	result, err := EvaluatePolicy(log, claims, config)
	require.NoError(t, err)
	assert.True(t, result.Allowed)
	assert.Contains(t, result.Reason, "feature flag not enabled")
}

func TestEvaluatePolicy_FeatureFlagEnabled(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	config := DefaultPolicyConfig()

	tests := []struct {
		name        string
		claims      *workload.AttestedClaims
		expectAllow bool
		expectReason string
	}{
		{
			name: "all checks pass",
			claims: &workload.AttestedClaims{
				Geolocation:        "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
				GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
					Status:        "healthy",
					UtilizationPct: 15.0,
					MemoryMb:      10240,
				},
			},
			expectAllow: true,
			expectReason: "all policy checks passed",
		},
		{
			name: "host integrity failed",
			claims: &workload.AttestedClaims{
				Geolocation:        "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: workload.AttestedClaims_FAILED,
			},
			expectAllow: false,
			expectReason: "host integrity check failed",
		},
		{
			name: "geolocation not allowed",
			claims: &workload.AttestedClaims{
				Geolocation:        "USA: N40.7128, W74.0060",
				HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
			},
			expectAllow: false,
			expectReason: "geolocation",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := EvaluatePolicy(log, tt.claims, config)
			require.NoError(t, err)
			assert.Equal(t, tt.expectAllow, result.Allowed)
			assert.Contains(t, result.Reason, tt.expectReason)
		})
	}
}

func TestEvaluatePolicy_NilClaims(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	config := DefaultPolicyConfig()

	result, err := EvaluatePolicy(log, nil, config)
	assert.Error(t, err)
	assert.False(t, result.Allowed)
	assert.Contains(t, result.Reason, "claims cannot be nil")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestEvaluatePolicy_GPUUtilizationThreshold tests GPU metrics handling
// Note: In Phase 1, GPU thresholds are not enforced, but we test that GPU metrics are handled correctly
func TestEvaluatePolicy_GPUUtilizationThreshold(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	config := DefaultPolicyConfig()
	config.AllowedGeolocations = []string{"Spain"}

	tests := []struct {
		name        string
		utilization float64
		expectAllow bool
		expectReason string
	}{
		{
			name:        "low GPU utilization passes",
			utilization: 15.0,
			expectAllow: true,
			expectReason: "all policy checks passed",
		},
		{
			name:        "high GPU utilization passes (not enforced in Phase 1)",
			utilization: 95.0,
			expectAllow: true,
			expectReason: "all policy checks passed",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			claims := &workload.AttestedClaims{
				Geolocation:        "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
				GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
					Status:        "healthy",
					UtilizationPct: tt.utilization,
					MemoryMb:      10240,
				},
			}

			result, err := EvaluatePolicy(log, claims, config)
			require.NoError(t, err)
			assert.Equal(t, tt.expectAllow, result.Allowed)
			assert.Contains(t, result.Reason, tt.expectReason)
		})
	}
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestEvaluatePolicy_NoGPUMetrics tests behavior when GPU metrics are not provided
func TestEvaluatePolicy_NoGPUMetrics(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	config := DefaultPolicyConfig()

	claims := &workload.AttestedClaims{
		Geolocation:        "Spain: N40.4168, W3.7038",
		HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
		// No GPU metrics
	}

	result, err := EvaluatePolicy(log, claims, config)
	require.NoError(t, err)
	// Should pass when GPU metrics are not required
	assert.True(t, result.Allowed)
	assert.Contains(t, result.Reason, "all policy checks passed")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestEvaluatePolicy_MultipleGeolocations tests multiple allowed geolocations
func TestEvaluatePolicy_MultipleGeolocations(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	config := DefaultPolicyConfig()
	config.AllowedGeolocations = []string{"Spain", "France", "Germany"}

	tests := []struct {
		name         string
		geolocation  string
		expectAllow  bool
		expectReason string
	}{
		{
			name:         "Spain allowed",
			geolocation:  "Spain: N40.4168, W3.7038",
			expectAllow:  true,
			expectReason: "all policy checks passed",
		},
		{
			name:         "France allowed",
			geolocation:  "France: N48.8566, E2.3522",
			expectAllow:  true,
			expectReason: "all policy checks passed",
		},
		{
			name:         "Germany allowed",
			geolocation:  "Germany: N52.5200, E13.4050",
			expectAllow:  true,
			expectReason: "all policy checks passed",
		},
		{
			name:         "USA not allowed",
			geolocation:  "USA: N40.7128, W74.0060",
			expectAllow:  false,
			expectReason: "geolocation",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			claims := &workload.AttestedClaims{
				Geolocation:        tt.geolocation,
				HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
			}

			result, err := EvaluatePolicy(log, claims, config)
			require.NoError(t, err)
			assert.Equal(t, tt.expectAllow, result.Allowed)
			assert.Contains(t, result.Reason, tt.expectReason)
		})
	}
}

