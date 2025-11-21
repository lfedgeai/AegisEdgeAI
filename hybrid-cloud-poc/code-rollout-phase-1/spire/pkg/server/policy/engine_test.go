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
				Logger:              logrus.New(),
			},
			claims: &AttestedClaims{
				Geolocation: "Spain: N40.4168, W3.7038",
			},
			wantAllowed: true,
		},
		{
			name: "geolocation violation",
			config: PolicyConfig{
				AllowedGeolocations: []string{"Germany:*"},
				Logger:              logrus.New(),
			},
			claims: &AttestedClaims{
				Geolocation: "Spain: N40.4168, W3.7038",
			},
			wantAllowed: false,
		},
		{
			name: "no policy restrictions",
			config: PolicyConfig{
				Logger: logrus.New(),
			},
			claims: &AttestedClaims{
				Geolocation: "Spain: N40.4168, W3.7038",
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
		Geolocation: "Spain: N40.4168, W3.7038",
	}

	result := ConvertKeylimeAttestedClaims(keylimeClaims)
	require.NotNil(t, result)
	assert.Equal(t, keylimeClaims.Geolocation, result.Geolocation)
}

