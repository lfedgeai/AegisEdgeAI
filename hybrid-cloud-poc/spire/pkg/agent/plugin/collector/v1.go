package collector

import (
	"context"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/catalog"
	"github.com/spiffe/spire/pkg/common/plugin"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"github.com/sirupsen/logrus"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// V1 is the V1 facade for the Collector plugin.
type V1 struct {
	plugin.Facade
	impl Collector
}

func (v1 *V1) InitInfo(info catalog.PluginInfo) {
	v1.Facade.InitInfo(info)
}

func (v1 *V1) InitLog(log logrus.FieldLogger) {
	v1.Facade.InitLog(log)
}

func (v1 *V1) InitClient(conn grpc.ClientConnInterface) interface{} {
	client := &grpcClient{conn: conn}
	v1.impl = client
	return client
}

func (v1 *V1) GRPCServiceName() string {
	return "spire.agent.collector.v1.Collector"
}

func (v1 *V1) CollectSovereignAttestation(ctx context.Context, nonce string) (*types.SovereignAttestation, error) {
	if v1.impl == nil {
		return nil, v1.Error(codes.Internal, "plugin implementation not found")
	}
	return v1.impl.CollectSovereignAttestation(ctx, nonce)
}

type grpcClient struct {
	conn grpc.ClientConnInterface
}

func (c *grpcClient) CollectSovereignAttestation(ctx context.Context, nonce string) (*types.SovereignAttestation, error) {
	in := &wrapperspb.StringValue{Value: nonce}
	out := new(types.SovereignAttestation)
	err := c.conn.Invoke(ctx, "/spire.agent.collector.v1.Collector/CollectSovereignAttestation", in, out)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *grpcClient) Name() string {
	return "sovereign"
}

func (c *grpcClient) Type() string {
	return "Collector"
}
