// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
package policy

import (
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
func TestEngine_Evaluate(t *testing.T) {
	tests := []struct {
		name        string
		config      PolicyConfig
		claims      *AttestedClaims
		wantAllowed bool
		wantReason  string
	}{
		{
			name: "all checks pass",
			config: PolicyConfig{
				AllowedGeolocations: []string{"Spain:*"},
				RequireIntegrity:    true,
				MaxGPUUtilization:   100.0,
				MinGPUMemoryMB:     0,
				Logger:              logrus.New(),
			},
			claims: &AttestedClaims{
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
			wantAllowed: true,
		},
		{
			name: "geolocation violation",
			config: PolicyConfig{
				AllowedGeolocations: []string{"Germany:*"},
				RequireIntegrity:    false,
				Logger:              logrus.New(),
			},
			claims: &AttestedClaims{
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
			wantAllowed: false,
		},
		{
			name: "integrity violation",
			config: PolicyConfig{
				AllowedGeolocations: []string{"Spain:*"},
				RequireIntegrity:    true,
				Logger:              logrus.New(),
			},
			claims: &AttestedClaims{
				Geolocation:         "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: "failed",
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
			wantAllowed: false,
		},
		{
			name: "GPU utilization violation",
			config: PolicyConfig{
				AllowedGeolocations: []string{"Spain:*"},
				RequireIntegrity:    false,
				MaxGPUUtilization:   50.0,
				Logger:              logrus.New(),
			},
			claims: &AttestedClaims{
				Geolocation:         "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: "passed_all_checks",
				GPUMetricsHealth: struct {
					Status        string
					UtilizationPct float64
					MemoryMB      int64
				}{
					Status:        "healthy",
					UtilizationPct: 75.0,
					MemoryMB:      10240,
				},
			},
			wantAllowed: false,
		},
		{
			name: "GPU memory violation",
			config: PolicyConfig{
				AllowedGeolocations: []string{"Spain:*"},
				RequireIntegrity:    false,
				MinGPUMemoryMB:     20000,
				Logger:              logrus.New(),
			},
			claims: &AttestedClaims{
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
			wantAllowed: false,
		},
		{
			name: "no policy restrictions",
			config: PolicyConfig{
				Logger: logrus.New(),
			},
			claims: &AttestedClaims{
				Geolocation:         "Spain: N40.4168, W3.7038",
				HostIntegrityStatus: "failed",
				GPUMetricsHealth: struct {
					Status        string
					UtilizationPct float64
					MemoryMB      int64
				}{
					Status:        "degraded",
					UtilizationPct: 99.0,
					MemoryMB:      100,
				},
			},
			wantAllowed: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			engine := NewEngine(tt.config)
			result, err := engine.Evaluate(tt.claims)
			require.NoError(t, err)
			assert.Equal(t, tt.wantAllowed, result.Allowed)
			if !tt.wantAllowed {
				assert.NotEmpty(t, result.Reason)
			}
		})
	}
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
func TestEngine_matchesGeolocation(t *testing.T) {
	engine := &Engine{
		config: PolicyConfig{
			Logger: logrus.New(),
		},
	}

	tests := []struct {
		name      string
		location  string
		pattern   string
		wantMatch bool
	}{
		{
			name:      "exact match",
			location:  "Spain: N40.4168, W3.7038",
			pattern:   "Spain: N40.4168, W3.7038",
			wantMatch: true,
		},
		{
			name:      "wildcard match",
			location:  "Spain: N40.4168, W3.7038",
			pattern:   "Spain:*",
			wantMatch: true,
		},
		{
			name:      "wildcard no match",
			location:  "Germany: Berlin",
			pattern:   "Spain:*",
			wantMatch: false,
		},
		{
			name:      "no match",
			location:  "Spain: N40.4168, W3.7038",
			pattern:   "Germany: Berlin",
			wantMatch: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := engine.matchesGeolocation(tt.location, tt.pattern)
			assert.Equal(t, tt.wantMatch, result)
		})
	}
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
func TestConvertKeylimeAttestedClaims(t *testing.T) {
	keylimeClaims := &KeylimeAttestedClaims{
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
	}

	result := ConvertKeylimeAttestedClaims(keylimeClaims)
	require.NotNil(t, result)
	assert.Equal(t, keylimeClaims.Geolocation, result.Geolocation)
	assert.Equal(t, keylimeClaims.HostIntegrityStatus, result.HostIntegrityStatus)
	assert.Equal(t, keylimeClaims.GPUMetricsHealth.Status, result.GPUMetricsHealth.Status)
	assert.Equal(t, keylimeClaims.GPUMetricsHealth.UtilizationPct, result.GPUMetricsHealth.UtilizationPct)
	assert.Equal(t, keylimeClaims.GPUMetricsHealth.MemoryMB, result.GPUMetricsHealth.MemoryMB)
}

