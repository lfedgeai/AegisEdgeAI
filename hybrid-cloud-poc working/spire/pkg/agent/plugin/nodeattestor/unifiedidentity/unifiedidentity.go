package unifiedidentity

import (
	"context"

	nodeattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/nodeattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"github.com/spiffe/spire/pkg/common/catalog"
)

const (
	PluginName = "unified_identity"
)

func BuiltIn() catalog.BuiltIn {
	return builtin(New())
}

func builtin(p *Plugin) catalog.BuiltIn {
	return catalog.MakeBuiltIn(PluginName, nodeattestorv1.NodeAttestorPluginServer(p))
}

type Plugin struct {
	nodeattestorv1.UnsafeNodeAttestorServer
}

func New() *Plugin {
	return &Plugin{}
}

func (p *Plugin) Configure(context.Context, *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	// Unified-Identity: TPM-based proof of residency node attestor
	// No configuration needed - uses SovereignAttestation from agent client
	return &configv1.ConfigureResponse{}, nil
}

func (p *Plugin) AidAttestation(stream nodeattestorv1.NodeAttestor_AidAttestationServer) error {
	// Unified-Identity: TPM-based proof of residency
	// The agent ID is derived from TPM evidence (AK/EK) in SovereignAttestation
	// which is sent separately in the AttestAgent request params.
	// This node attestor just needs to send a minimal payload to trigger
	// the server's Unified-Identity flow.
	// The server will handle the actual attestation via SovereignAttestation in the AttestAgent request.
	return stream.Send(&nodeattestorv1.PayloadOrChallengeResponse{
		Data: &nodeattestorv1.PayloadOrChallengeResponse_Payload{
			Payload: []byte("unified_identity"), // Minimal payload
		},
	})
}
