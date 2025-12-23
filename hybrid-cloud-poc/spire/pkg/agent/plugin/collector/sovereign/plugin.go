package sovereign

import (
	"context"
	"sync"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"github.com/spiffe/spire/pkg/agent/tpmplugin"
	"github.com/spiffe/spire/pkg/common/catalog"
	"google.golang.org/grpc"
)

const (
	PluginName = "sovereign"
)

func BuiltIn() catalog.BuiltIn {
	return builtin(New())
}

func builtin(p *Plugin) catalog.BuiltIn {
	return catalog.MakeBuiltIn(PluginName, p)
}

type Plugin struct {
	log logrus.FieldLogger

	mu        sync.RWMutex
	tpmPlugin *tpmplugin.TPMPluginGateway
}

func New() *Plugin {
	return &Plugin{}
}

func (p *Plugin) Type() string {
	return "Collector"
}

func (p *Plugin) GRPCServiceName() string {
	return "spire.agent.collector.v1.Collector"
}

func (p *Plugin) RegisterServer(s *grpc.Server) interface{} {
	// No-op until we have a proto for the collector plugin
	return nil
}

func (p *Plugin) SetLogger(log logrus.FieldLogger) {
	p.log = log
}

func (p *Plugin) Configure(ctx context.Context, req *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	// For now, use existing environment variables or standard paths
	// as the agent core already does.
	p.mu.Lock()
	defer p.mu.Unlock()

	// Initialize TPM plugin gateway if not already done
	if p.tpmPlugin == nil {
		p.tpmPlugin = tpmplugin.NewTPMPluginGateway("", "", "", p.log)
	}

	return &configv1.ConfigureResponse{}, nil
}

func (p *Plugin) CollectSovereignAttestation(ctx context.Context, nonce string) (*types.SovereignAttestation, error) {
	p.mu.RLock()
	tpmPlugin := p.tpmPlugin
	p.mu.RUnlock()

	if tpmPlugin == nil {
		p.log.Warn("TPM plugin not initialized during collection")
		return nil, nil
	}

	return tpmPlugin.BuildSovereignAttestation(nonce)
}
