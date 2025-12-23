package unifiedidentity

import (
	"context"
	"testing"

	credentialcomposerv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/server/credentialcomposer/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/server/unifiedidentity"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestComposeAgentX509SVID(t *testing.T) {
	plugin := New()
	ctx := context.Background()

	claims := &types.AttestedClaims{
		Geolocation: &types.Geolocation{
			Type:     "static",
			SensorId: "test-sensor",
			Value:    "test-value",
		},
	}
	unifiedJSON := []byte(`{"test": "json"}`)

	ctx = unifiedidentity.WithClaims(ctx, claims, unifiedJSON)

	req := &credentialcomposerv1.ComposeAgentX509SVIDRequest{
		Attributes: &credentialcomposerv1.X509SVIDAttributes{},
	}

	resp, err := plugin.ComposeAgentX509SVID(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.NotNil(t, resp.Attributes)

	// Check for the AttestedClaims extension
	found := false
	for _, ext := range resp.Attributes.ExtraExtensions {
		if ext.Oid == "1.3.6.1.4.1.99999.1" {
			found = true
			assert.Equal(t, unifiedJSON, ext.Value)
			break
		}
	}
	assert.True(t, found, "AttestedClaims extension not found in response")
}

func TestComposeWorkloadX509SVID(t *testing.T) {
	plugin := New()
	ctx := context.Background()

	claims := &types.AttestedClaims{
		Geolocation: &types.Geolocation{
			Type:     "static",
			SensorId: "test-sensor",
			Value:    "test-value",
		},
	}

	ctx = unifiedidentity.WithClaims(ctx, claims, nil)

	req := &credentialcomposerv1.ComposeWorkloadX509SVIDRequest{
		Attributes: &credentialcomposerv1.X509SVIDAttributes{},
	}

	resp, err := plugin.ComposeWorkloadX509SVID(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.NotNil(t, resp.Attributes)

	// Check for the AttestedClaims extension
	found := false
	for _, ext := range resp.Attributes.ExtraExtensions {
		if ext.Oid == "1.3.6.1.4.1.99999.1" {
			found = true
			// When unifiedJSON is nil, it should marshal claims to JSON
			assert.Contains(t, string(ext.Value), "test-sensor")
			break
		}
	}
	assert.True(t, found, "AttestedClaims extension not found in response")
}
