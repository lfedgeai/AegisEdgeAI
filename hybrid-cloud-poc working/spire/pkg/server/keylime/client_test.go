// Unified-Identity - Setup: SPIRE API & Policy Staging (Stubbed Keylime)
package keylime

import (
	"encoding/base64"
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unified-Identity - Setup: SPIRE API & Policy Staging (Stubbed Keylime)
func TestBuildVerifyEvidenceRequest(t *testing.T) {
	tests := []struct {
		name                 string
		sovereignAttestation *SovereignAttestationProto
		nonce                string
		wantErr              bool
		validate             func(t *testing.T, req *VerifyEvidenceRequest)
	}{
		{
			name: "valid request with all fields",
			sovereignAttestation: &SovereignAttestationProto{
				TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
				AppKeyPublic:         "test-public-key",
				AppKeyCertificate:    []byte("test-cert"),
				ChallengeNonce:       "test-nonce-123",
				WorkloadCodeHash:     "test-hash",
			},
			nonce:   "fallback-nonce",
			wantErr: false,
			validate: func(t *testing.T, req *VerifyEvidenceRequest) {
				assert.Equal(t, "test-nonce-123", req.Data.Nonce)
				assert.Equal(t, base64.StdEncoding.EncodeToString([]byte("test-quote")), req.Data.Quote)
				assert.Equal(t, "sha256", req.Data.HashAlg)
				assert.Equal(t, "test-public-key", req.Data.AppKeyPublic)
				assert.NotEmpty(t, req.Data.AppKeyCertificate)
				assert.Equal(t, "127.0.0.1", req.Data.AgentIP)
				assert.Equal(t, 9002, req.Data.AgentPort)
				assert.Equal(t, "SPIRE Server", req.Metadata.Source)
				assert.Equal(t, "PoR/tpm-app-key", req.Metadata.SubmissionType)
			},
		},
		{
			name: "request with fallback nonce",
			sovereignAttestation: &SovereignAttestationProto{
				TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
				AppKeyPublic:         "test-public-key",
			},
			nonce:   "fallback-nonce",
			wantErr: false,
			validate: func(t *testing.T, req *VerifyEvidenceRequest) {
				assert.Equal(t, "fallback-nonce", req.Data.Nonce)
			},
		},
		{
			name: "request without certificate",
			sovereignAttestation: &SovereignAttestationProto{
				TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
				AppKeyPublic:         "test-public-key",
				ChallengeNonce:       "test-nonce",
			},
			nonce:   "",
			wantErr: false,
			validate: func(t *testing.T, req *VerifyEvidenceRequest) {
				assert.Empty(t, req.Data.AppKeyCertificate)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := BuildVerifyEvidenceRequest(tt.sovereignAttestation, tt.nonce)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			require.NotNil(t, req)
			if tt.validate != nil {
				tt.validate(t, req)
			}
		})
	}
}

// Unified-Identity - Setup: SPIRE API & Policy Staging (Stubbed Keylime)
func TestNewClient(t *testing.T) {
	tests := []struct {
		name    string
		config  Config
		wantErr bool
	}{
		{
			name: "valid config with base URL",
			config: Config{
				BaseURL: "https://keylime.example.com",
				Logger:  logrus.New(),
			},
			wantErr: false,
		},
		{
			name: "missing base URL",
			config: Config{
				Logger: logrus.New(),
			},
			wantErr: true,
		},
		{
			name: "valid config with client cert",
			config: Config{
				BaseURL: "https://keylime.example.com",
				TLSCert: "/dev/null", // Will fail to load but validates config structure
				TLSKey:  "/dev/null",
				Logger:  logrus.New(),
			},
			wantErr: true, // Will fail to load cert but that's expected
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client, err := NewClient(tt.config)
			if tt.wantErr {
				assert.Error(t, err)
				assert.Nil(t, client)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, client)
			}
		})
	}
}
