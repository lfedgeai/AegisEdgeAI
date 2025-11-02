package svid_test

import (
	"context"
	"crypto/rand"
	"crypto/x509"
	"testing"

	"github.com/sirupsen/logrus/hooks/test"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	svidv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/server/api"
	"github.com/spiffe/spire/pkg/server/api/middleware"
	"github.com/spiffe/spire/pkg/server/api/rpccontext"
	"github.com/spiffe/spire/pkg/server/api/svid/v1"
	"github.com/spiffe/spire/test/fakes/fakeserverca"
	"github.com/spiffe/spire/test/grpctest"
	"github.com/spiffe/spire/test/testkey"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
)

func TestEndToEnd(t *testing.T) {
	td := spiffeid.RequireTrustDomainFromString("example.org")
	ca := fakeserverca.New(t, td, &fakeserverca.Options{})
	testKey := testkey.MustEC256()

	// Create a new fake agent
	agentID := spiffeid.RequireFromPath(td, "/agent")
	agentEntry := &types.Entry{
		Id:       "agent-entry-id",
		ParentId: api.ProtoFromID(agentID),
		SpiffeId: &types.SPIFFEID{TrustDomain: "example.org", Path: "/agent"},
	}

	// Create a new fake workload
	workloadEntry := &types.Entry{
		Id:       "workload-entry-id",
		ParentId: api.ProtoFromID(agentID),
		SpiffeId: &types.SPIFFEID{TrustDomain: "example.org", Path: "/workload"},
	}

	// Create a new SVID service
	service := svid.New(svid.Config{
		EntryFetcher: &entryFetcher{
			entries: []*types.Entry{agentEntry, workloadEntry},
		},
		ServerCA:    ca,
		TrustDomain: td,
	})

	log, _ := test.NewNullLogger()
	rateLimiter := &fakeRateLimiter{
		count: 1,
	}
	// Create a new test server
	server := grpctest.StartServer(t, func(s grpc.ServiceRegistrar) {
		svidv1.RegisterSVIDServer(s, service)
	},
		grpctest.Middleware(middleware.WithLogger(log)),
		grpctest.OverrideContext(func(ctx context.Context) context.Context {
			ctx = rpccontext.WithLogger(ctx, log)
			ctx = rpccontext.WithRateLimiter(ctx, rateLimiter)
			ctx = rpccontext.WithCallerID(ctx, agentID)
			return ctx
		}),
	)

	defer server.Stop()

	// Create a new client
	client := svidv1.NewSVIDClient(server.NewGRPCClient(t))

	// Create a new CSR for the workload
	csr, err := x509.CreateCertificateRequest(rand.Reader, &x509.CertificateRequest{}, testKey)
	require.NoError(t, err)

	// Create a BatchNewX509SVID request
	req := &svidv1.BatchNewX509SVIDRequest{
		Params: []*svidv1.NewX509SVIDParams{
			{
				EntryId: workloadEntry.Id,
				Csr:     csr,
			},
		},
		SovereignAttestation: &svidv1.SovereignAttestation{
			TpmSignedAttestation: "test_attestation",
		},
	}

	// Call BatchNewX509SVID
	resp, err := client.BatchNewX509SVID(context.Background(), req)
	require.NoError(t, err)

	// Verify the response
	require.NotNil(t, resp)
	require.Len(t, resp.Results, 1)
	require.Equal(t, int32(codes.OK), resp.Results[0].Status.Code)
	require.Len(t, resp.AttestedClaims, 1)
	require.Equal(t, "Spain", resp.AttestedClaims[0].Geolocation)
}
