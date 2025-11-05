// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
package unifiedidentity

import (
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/stretchr/testify/assert"
)

func TestEvaluatePolicy(t *testing.T) {
	log := logrus.New()
	log.SetLevel(logrus.DebugLevel)

	tests := []struct {
		name           string
		claims         *workload.AttestedClaims
		config         PolicyConfig
		expectedResult PolicyEvaluationResult
	}{
		{
			name: "All checks pass",
			claims: &workload.AttestedClaims{
				Geolocation:        "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
				GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
					Status:        "healthy",
					UtilizationPct: 15.0,
					MemoryMb:     10240,
				},
			},
			config: DefaultPolicyConfig(),
			expectedResult: PolicyEvaluationResult{
				Allowed: true,
				Reason:  "all policy checks passed",
			},
		},
		{
			name: "Geolocation not allowed",
			claims: &workload.AttestedClaims{
				Geolocation:        "France: N48.8566, E2.3522",
				HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
				GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
					Status:        "healthy",
					UtilizationPct: 15.0,
					MemoryMb:     10240,
				},
			},
			config: DefaultPolicyConfig(),
			expectedResult: PolicyEvaluationResult{
				Allowed: false,
				Reason:  "geolocation France: N48.8566, E2.3522 not in allowed list",
			},
		},
		{
			name: "Host integrity failed",
			claims: &workload.AttestedClaims{
				Geolocation:        "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: workload.AttestedClaims_FAILED,
				GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
					Status:        "healthy",
					UtilizationPct: 15.0,
					MemoryMb:     10240,
				},
			},
			config: DefaultPolicyConfig(),
			expectedResult: PolicyEvaluationResult{
				Allowed: false,
				Reason:  "host integrity status is FAILED, required PASSED_ALL_CHECKS",
			},
		},
		{
			name: "GPU not healthy",
			claims: &workload.AttestedClaims{
				Geolocation:        "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
				GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
					Status:        "degraded",
					UtilizationPct: 15.0,
					MemoryMb:     10240,
				},
			},
			config: DefaultPolicyConfig(),
			expectedResult: PolicyEvaluationResult{
				Allowed: false,
				Reason:  "GPU status is degraded, required healthy",
			},
		},
		{
			name: "Nil claims",
			claims: nil,
			config: DefaultPolicyConfig(),
			expectedResult: PolicyEvaluationResult{
				Allowed: false,
				Reason:  "claims are nil",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := EvaluatePolicy(tt.claims, tt.config, log)
			assert.Equal(t, tt.expectedResult.Allowed, result.Allowed)
			assert.Contains(t, result.Reason, tt.expectedResult.Reason)
		})
	}
}

func TestMatchesGeolocationPattern(t *testing.T) {
	tests := []struct {
		name       string
		geolocation string
		pattern     string
		expected    bool
	}{
		{
			name:       "Exact match",
			geolocation: "Spain: N40.4168, W3.7038",
			pattern:     "Spain: N40.4168, W3.7038",
			expected:    true,
		},
		{
			name:       "Pattern match with wildcard",
			geolocation: "Spain: Madrid",
			pattern:     "Spain: *",
			expected:    true,
		},
		{
			name:       "Pattern match with wildcard - different city",
			geolocation: "Spain: Barcelona",
			pattern:     "Spain: *",
			expected:    true,
		},
		{
			name:       "No match",
			geolocation: "France: Paris",
			pattern:     "Spain: *",
			expected:    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := matchesGeolocationPattern(tt.geolocation, tt.pattern)
			assert.Equal(t, tt.expected, result)
		})
	}
}

