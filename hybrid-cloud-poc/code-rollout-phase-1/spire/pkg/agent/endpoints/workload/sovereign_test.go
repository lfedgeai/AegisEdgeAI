// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
package workload

import (
	"context"
	"encoding/base64"
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGenerateStubbedSovereignAttestation_FeatureFlagDisabled(t *testing.T) {
	_ = fflag.Unload()

	log := logrus.New()
	req := &workload.X509SVIDRequest{}

	attestation := generateStubbedSovereignAttestation(context.Background(), log, req)
	assert.Nil(t, attestation)
}

func TestGenerateStubbedSovereignAttestation_FeatureFlagEnabled(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	req := &workload.X509SVIDRequest{}

	attestation := generateStubbedSovereignAttestation(context.Background(), log, req)
	require.NotNil(t, attestation)

	assert.NotEmpty(t, attestation.TpmSignedAttestation)
	assert.NotEmpty(t, attestation.AppKeyPublic)
	assert.NotEmpty(t, attestation.ChallengeNonce)
	assert.NotEmpty(t, attestation.AppKeyCertificate)

	// Validate base64 encoding
	_, err = base64.StdEncoding.DecodeString(attestation.TpmSignedAttestation)
	assert.NoError(t, err)
}

func TestValidateSovereignAttestation(t *testing.T) {
	tests := []struct {
		name        string
		attestation *workload.SovereignAttestation
		expectError string
	}{
		{
			name:        "nil attestation",
			attestation: nil,
			expectError: "attestation cannot be nil",
		},
		{
			name: "missing tpm quote",
			attestation: &workload.SovereignAttestation{
				ChallengeNonce: "test-nonce",
				AppKeyPublic:   "test-key",
			},
			expectError: "tpm_signed_attestation is required",
		},
		{
			name: "invalid base64 tpm quote",
			attestation: &workload.SovereignAttestation{
				TpmSignedAttestation: "invalid base64!@#$",
				ChallengeNonce:       "test-nonce",
				AppKeyPublic:         "test-key",
			},
			expectError: "tpm_signed_attestation must be valid base64",
		},
		{
			name: "missing nonce",
			attestation: &workload.SovereignAttestation{
				TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
				AppKeyPublic:         "test-key",
			},
			expectError: "challenge_nonce is required",
		},
		{
			name: "missing app key public",
			attestation: &workload.SovereignAttestation{
				TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
				ChallengeNonce:       "test-nonce",
			},
			expectError: "app_key_public is required",
		},
		{
			name: "valid attestation",
			attestation: &workload.SovereignAttestation{
				TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
				ChallengeNonce:       "test-nonce",
				AppKeyPublic:         "test-public-key",
			},
			expectError: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateSovereignAttestation(tt.attestation)
			if tt.expectError != "" {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tt.expectError)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestProcessSovereignAttestation(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()

	tests := []struct {
		name        string
		req         *workload.X509SVIDRequest
		expectError bool
	}{
		{
			name:        "nil request",
			req:         nil,
			expectError: false, // Should return nil, nil
		},
		{
			name: "request with valid sovereign attestation",
			req: &workload.X509SVIDRequest{
				SovereignAttestation: &workload.SovereignAttestation{
					TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
					ChallengeNonce:       "test-nonce",
					AppKeyPublic:         "test-public-key",
				},
			},
			expectError: false,
		},
		{
			name: "request with invalid sovereign attestation",
			req: &workload.X509SVIDRequest{
				SovereignAttestation: &workload.SovereignAttestation{
					// Missing required fields
					ChallengeNonce: "test-nonce",
				},
			},
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			attestation, err := processSovereignAttestation(context.Background(), log, tt.req)
			if tt.expectError {
				assert.Error(t, err)
				assert.Nil(t, attestation)
			} else {
				if tt.req != nil && tt.req.SovereignAttestation != nil {
					assert.NotNil(t, attestation)
				}
			}
		})
	}
}

