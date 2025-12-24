package unifiedidentity

import (
	"context"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/proto"
)

type contextKey string

const (
	attestedClaimsKey       contextKey = "attestedClaims"
	unifiedIdentityJSONKey  contextKey = "unifiedIdentityJSON"
	sovereignAttestationKey contextKey = "sovereignAttestation"
	// Metadata key must end in -bin for binary data
	sovereignAttestationMDKey = "sovereign-attestation-bin"
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
func FromContext(ctx context.Context, _ ...bool) (*types.AttestedClaims, []byte) {
	claims, _ := ctx.Value(attestedClaimsKey).(*types.AttestedClaims)
	unifiedJSON, _ := ctx.Value(unifiedIdentityJSONKey).([]byte)
	return claims, unifiedJSON
}

// WithSovereignAttestation returns a new context with the given sovereign attestation.
// It stores it in both context value (for local) and outgoing metadata (for gRPC plugins).
func WithSovereignAttestation(ctx context.Context, sa *types.SovereignAttestation) context.Context {
	logrus.Infof("Unified-Identity: WithSovereignAttestation storing %p type %T", sa, sa)
	if sa != nil {
		// Store in local context
		ctx = context.WithValue(ctx, sovereignAttestationKey, sa)

		// Marshal to protobuf
		data, err := proto.Marshal(sa)
		if err != nil {
			logrus.WithError(err).Error("Unified-Identity: Failed to marshal SovereignAttestation for metadata")
		} else {
			// Append to outgoing metadata for gRPC calls (plugin boundary)
			ctx = metadata.AppendToOutgoingContext(ctx, sovereignAttestationMDKey, string(data))
		}
	}
	return ctx
}

// FromSovereignAttestation returns the sovereign attestation stored in the context, if any.
// It checks local context first, then incoming metadata.
func FromSovereignAttestation(ctx context.Context) *types.SovereignAttestation {
	// 1. Try local value
	val := ctx.Value(sovereignAttestationKey)
	if sa, ok := val.(*types.SovereignAttestation); ok && sa != nil {
		logrus.Infof("Unified-Identity: FromSovereignAttestation retrieved from local context")
		return sa
	}

	// 2. Try incoming metadata (gRPC)
	md, ok := metadata.FromIncomingContext(ctx)
	if ok {
		values := md.Get(sovereignAttestationMDKey)
		if len(values) > 0 {
			// Last value takes precedence
			data := []byte(values[len(values)-1])
			sa := &types.SovereignAttestation{}
			if err := proto.Unmarshal(data, sa); err != nil {
				logrus.WithError(err).Error("Unified-Identity: Failed to unmarshal SovereignAttestation from metadata")
			} else {
				logrus.Infof("Unified-Identity: FromSovereignAttestation retrieved from gRPC metadata")
				return sa
			}
		}
	}

	logrus.Warnf("Unified-Identity: FromSovereignAttestation failed to retrieve from both local context (raw=%v) and metadata", val)
	return nil
}
