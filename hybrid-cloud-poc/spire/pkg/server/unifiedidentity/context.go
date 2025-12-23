package unifiedidentity

import (
	"context"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

type contextKey string

const (
	attestedClaimsKey      contextKey = "attestedClaims"
	unifiedIdentityJSONKey contextKey = "unifiedIdentityJSON"
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
