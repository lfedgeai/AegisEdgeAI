// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
package keylime

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

func TestNewClient(t *testing.T) {
	log := logrus.New()
	client := NewClient("", log)
	assert.NotNil(t, client)
	assert.Equal(t, DefaultKeylimeVerifierURL, client.baseURL)
}

func TestVerifyEvidence_FeatureFlagDisabled(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Ensure feature flag is unloaded
	_ = fflag.Unload()

	log := logrus.New()
	client := NewClient("", log)

	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
		ChallengeNonce:        "test-nonce",
		AppKeyPublic:         "test-public-key",
	}

	claims, err := client.VerifyEvidence(context.Background(), attestation)
	assert.Nil(t, claims)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "feature flag is not enabled")
}

func TestVerifyEvidence_FeatureFlagEnabled(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Load feature flag
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	client := NewClient("", log)

	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
		ChallengeNonce:        "test-nonce",
		AppKeyPublic:         "test-public-key",
	}

	claims, err := client.VerifyEvidence(context.Background(), attestation)
	require.NoError(t, err)
	require.NotNil(t, claims)

	// Verify stubbed claims
	assert.Equal(t, "Spain: N40.4168, W3.7038", claims.Geolocation)
	assert.Equal(t, workload.AttestedClaims_PASSED_ALL_CHECKS, claims.HostIntegrityStatus)
	assert.NotNil(t, claims.GpuMetricsHealth)
	assert.Equal(t, "healthy", claims.GpuMetricsHealth.Status)
	assert.Equal(t, 15.0, claims.GpuMetricsHealth.UtilizationPct)
	assert.Equal(t, int64(10240), claims.GpuMetricsHealth.MemoryMb)
}

func TestVerifyEvidence_ValidationErrors(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	log := logrus.New()
	client := NewClient("", log)

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
				AppKeyPublic:   "test-public-key",
			},
			expectError: "tpm_signed_attestation is required",
		},
		{
			name: "invalid base64 tpm quote",
			attestation: &workload.SovereignAttestation{
				TpmSignedAttestation: "invalid base64!@#$",
				ChallengeNonce:       "test-nonce",
				AppKeyPublic:         "test-public-key",
			},
			expectError: "tpm_signed_attestation must be valid base64",
		},
		{
			name: "missing nonce",
			attestation: &workload.SovereignAttestation{
				TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
				AppKeyPublic:         "test-public-key",
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
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			claims, err := client.VerifyEvidence(context.Background(), tt.attestation)
			assert.Nil(t, claims)
			assert.Error(t, err)
			assert.Contains(t, err.Error(), tt.expectError)
		})
	}
}

func TestBuildVerifyRequest(t *testing.T) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	log := logrus.New()
	client := NewClient("", log)

	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test quote")),
		ChallengeNonce:        "test-nonce-123",
		AppKeyPublic:         "test-public-key-pem",
		AppKeyCertificate:    []byte("test-cert-der"),
	}

	req := client.buildVerifyRequest(attestation)

	assert.Equal(t, "test-nonce-123", req.Data.Nonce)
	assert.Equal(t, attestation.TpmSignedAttestation, req.Data.Quote)
	assert.Equal(t, "sha256", req.Data.HashAlg)
	assert.Equal(t, "test-public-key-pem", req.Data.AppKeyPublic)
	assert.Equal(t, base64.StdEncoding.EncodeToString([]byte("test-cert-der")), req.Data.AppKeyCertificate)
	assert.Equal(t, "SPIRE Server", req.Metadata.Source)
	assert.Equal(t, "PoR/tpm-app-key", req.Metadata.SubmissionType)
}

