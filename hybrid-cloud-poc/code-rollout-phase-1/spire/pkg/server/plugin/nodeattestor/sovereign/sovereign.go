//go:build unified_identity

package sovereign

import (
	"context"

	nodeattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/server/nodeattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"github.com/spiffe/spire/pkg/common/catalog"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	pluginName = "sovereign"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
func BuiltIn() catalog.BuiltIn {
	return builtin(New())
}

func builtin(p *Plugin) catalog.BuiltIn {
	return catalog.MakeBuiltIn(pluginName,
		nodeattestorv1.NodeAttestorPluginServer(p),
		configv1.ConfigServiceServer(p),
	)
}

type Plugin struct {
	nodeattestorv1.UnsafeNodeAttestorServer
	configv1.UnsafeConfigServer
}

func New() *Plugin {
	return &Plugin{}
}

func (p *Plugin) Attest(stream nodeattestorv1.NodeAttestor_AttestServer) error {
	req, err := stream.Recv()
	if err != nil {
		return err
	}

	payload := req.GetPayload()
	if len(payload) == 0 {
		return status.Error(codes.InvalidArgument, "missing attestation data")
	}

	// In Phase 1, we are just stubbing this out.
	// We will return a canned response.
	return stream.Send(&nodeattestorv1.AttestResponse{
		Response: &nodeattestorv1.AttestResponse_AgentAttributes{
			AgentAttributes: &nodeattestorv1.AgentAttributes{
				SpiffeId: "spiffe://domain.test/spire/agent/sovereign/stubbed-agent",
			},
		},
	})
}

func (p *Plugin) Configure(ctx context.Context, req *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	return &configv1.ConfigureResponse{}, nil
}

func (p *Plugin) Validate(ctx context.Context, req *configv1.ValidateRequest) (*configv1.ValidateResponse, error) {
	return &configv1.ValidateResponse{
		Valid: true,
	}, nil
}
