package unifiedidentity

import (
	"context"

	credentialcomposerv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/server/credentialcomposer/v1"
	"github.com/spiffe/spire/pkg/common/catalog"
	"github.com/spiffe/spire/pkg/server/credtemplate"
	"github.com/spiffe/spire/pkg/server/unifiedidentity"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func BuiltIn() catalog.BuiltIn {
	return builtIn(New())
}

func builtIn(p *Plugin) catalog.BuiltIn {
	return catalog.MakeBuiltIn("unifiedidentity",
		credentialcomposerv1.CredentialComposerPluginServer(p),
	)
}

type Plugin struct {
	credentialcomposerv1.UnsafeCredentialComposerServer
}

func New() *Plugin {
	return &Plugin{}
}

func (p *Plugin) ComposeServerX509CA(context.Context, *credentialcomposerv1.ComposeServerX509CARequest) (*credentialcomposerv1.ComposeServerX509CAResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

func (p *Plugin) ComposeServerX509SVID(context.Context, *credentialcomposerv1.ComposeServerX509SVIDRequest) (*credentialcomposerv1.ComposeServerX509SVIDResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

func (p *Plugin) ComposeAgentX509SVID(ctx context.Context, req *credentialcomposerv1.ComposeAgentX509SVIDRequest) (*credentialcomposerv1.ComposeAgentX509SVIDResponse, error) {
	if req.Attributes == nil {
		return nil, status.Error(codes.InvalidArgument, "request missing attributes")
	}

	attributes := req.Attributes
	claims, unifiedJSON := unifiedidentity.FromContext(ctx)

	if claims != nil || len(unifiedJSON) > 0 {
		ext, err := credtemplate.AttestedClaimsExtension(claims, unifiedJSON)
		if err != nil {
			return nil, status.Errorf(codes.Internal, "failed to create AttestedClaims extension: %v", err)
		}
		if ext.Id != nil {
			attributes.ExtraExtensions = append(attributes.ExtraExtensions, &credentialcomposerv1.X509Extension{
				Oid:      ext.Id.String(),
				Value:    ext.Value,
				Critical: ext.Critical,
			})
		}
	}

	return &credentialcomposerv1.ComposeAgentX509SVIDResponse{
		Attributes: attributes,
	}, nil
}

func (p *Plugin) ComposeWorkloadX509SVID(ctx context.Context, req *credentialcomposerv1.ComposeWorkloadX509SVIDRequest) (*credentialcomposerv1.ComposeWorkloadX509SVIDResponse, error) {
	if req.Attributes == nil {
		return nil, status.Error(codes.InvalidArgument, "request missing attributes")
	}

	attributes := req.Attributes
	claims, unifiedJSON := unifiedidentity.FromContext(ctx)

	if claims != nil || len(unifiedJSON) > 0 {
		ext, err := credtemplate.AttestedClaimsExtension(claims, unifiedJSON)
		if err != nil {
			return nil, status.Errorf(codes.Internal, "failed to create AttestedClaims extension: %v", err)
		}
		if ext.Id != nil {
			attributes.ExtraExtensions = append(attributes.ExtraExtensions, &credentialcomposerv1.X509Extension{
				Oid:      ext.Id.String(),
				Value:    ext.Value,
				Critical: ext.Critical,
			})
		}
	}

	return &credentialcomposerv1.ComposeWorkloadX509SVIDResponse{
		Attributes: attributes,
	}, nil
}

func (p *Plugin) ComposeWorkloadJWTSVID(context.Context, *credentialcomposerv1.ComposeWorkloadJWTSVIDRequest) (*credentialcomposerv1.ComposeWorkloadJWTSVIDResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}
