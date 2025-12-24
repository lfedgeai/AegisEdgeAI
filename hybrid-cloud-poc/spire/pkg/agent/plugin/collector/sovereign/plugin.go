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
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/wrapperspb"
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
	p := &Plugin{
		log: logrus.New(),
	}
	p.tpmPlugin = tpmplugin.NewTPMPluginGateway("", "", "", p.log)
	return p
}

func (p *Plugin) Type() string {
	return "Collector"
}

func (p *Plugin) GRPCServiceName() string {
	return "spire.agent.collector.v1.Collector"
}

func (p *Plugin) RegisterServer(s *grpc.Server) interface{} {
	s.RegisterService(&_Collector_serviceDesc, p)
	return p
}

type CollectorServer interface {
	CollectSovereignAttestation(context.Context, string) (*types.SovereignAttestation, error)
}

func _Collector_CollectSovereignAttestation_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(wrapperspb.StringValue)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(CollectorServer).CollectSovereignAttestation(ctx, in.Value)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/spire.agent.collector.v1.Collector/CollectSovereignAttestation",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(CollectorServer).CollectSovereignAttestation(ctx, req.(*wrapperspb.StringValue).Value)
	}
	return interceptor(ctx, in, info, handler)
}

var _Collector_serviceDesc = grpc.ServiceDesc{
	ServiceName: "spire.agent.collector.v1.Collector",
	HandlerType: (*CollectorServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "CollectSovereignAttestation",
			Handler:    _Collector_CollectSovereignAttestation_Handler,
		},
	},
	Streams:  []grpc.StreamDesc{},
	Metadata: "spire/agent/collector/v1/collector.proto",
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
		return nil, status.Error(codes.FailedPrecondition, "TPM plugin not initialized")
	}

	return tpmPlugin.BuildSovereignAttestation(nonce)
}
