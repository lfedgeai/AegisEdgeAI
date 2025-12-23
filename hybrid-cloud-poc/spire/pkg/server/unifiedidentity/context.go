package unifiedidentity

import (
	"context"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

type contextKey string

const (
	attestedClaimsKey       contextKey = "attestedClaims"
	unifiedIdentityJSONKey  contextKey = "unifiedIdentityJSON"
	sovereignAttestationKey contextKey = "sovereignAttestation"
)

// WithClaims returns a new context with the given attested claims and unified identity JSON.
func WithClaims(ctx context.Context, claims *types.AttestedClaims, unifiedJSON []byte) context.Context {
	if claims != nil {
		ctx = context.WithValue(ctx, attestedClaimsKey, claims)
	}
	if len(unifiedJSON) > 0 {
		ctx = context.WithValue(ctx, unifiedIdentityJSONKey, unifiedJSON)
	}
	return ctx
}

// FromContext returns the attested claims and unified identity JSON stored in the context, if any.
func FromContext(ctx context.Context) (*types.AttestedClaims, []byte) {
	claims, _ := ctx.Value(attestedClaimsKey).(*types.AttestedClaims)
	unifiedJSON, _ := ctx.Value(unifiedIdentityJSONKey).([]byte)
	return claims, unifiedJSON
}

// WithSovereignAttestation returns a new context with the given sovereign attestation.
func WithSovereignAttestation(ctx context.Context, sa *types.SovereignAttestation) context.Context {
	if sa != nil {
		ctx = context.WithValue(ctx, sovereignAttestationKey, sa)
	}
	return ctx
}

// FromSovereignAttestation returns the sovereign attestation stored in the context, if any.
func FromSovereignAttestation(ctx context.Context) *types.SovereignAttestation {
	sa, _ := ctx.Value(sovereignAttestationKey).(*types.SovereignAttestation)
	return sa
}
