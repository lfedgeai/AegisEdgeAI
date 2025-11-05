// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Package svid_test contains unit tests for sovereign attestation handling in the SVID service.
package svid_test

import (
	"context"
	"crypto/x509"
	"encoding/base64"
	"net/url"
	"testing"

	"github.com/sirupsen/logrus"
	logrustest "github.com/sirupsen/logrus/hooks/test"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	svidv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/server/api"
	"github.com/spiffe/spire/pkg/server/api/middleware"
	"github.com/spiffe/spire/pkg/server/api/rpccontext"
	svid "github.com/spiffe/spire/pkg/server/api/svid/v1"
	"github.com/spiffe/spire/pkg/server/sovereign/keylime"
	sovereignpolicy "github.com/spiffe/spire/pkg/server/sovereign"
	"github.com/spiffe/spire/test/grpctest"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/protobuf/proto"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestBatchNewX509SVID_WithSovereignAttestation tests BatchNewX509SVID with sovereign attestation
func TestBatchNewX509SVID_WithSovereignAttestation(t *testing.T) {
	_ = fflag.Unload()
	err := fflag.Load([]string{"Unified-Identity"})
	require.NoError(t, err)
	defer fflag.Unload()

	test := setupServiceTestWithSovereign(t)
	defer test.Cleanup()

	workloadEntry := &types.Entry{
		Id:       "workload",
		ParentId: api.ProtoFromID(agentID),
		SpiffeId: &types.SPIFFEID{TrustDomain: "example.org", Path: "/workload1"},
	}
	test.ef.entries = []*types.Entry{workloadEntry}

	csr := createCSRForID(t, workloadID)

	// Create valid sovereign attestation
	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-tpm-quote")),
		ChallengeNonce:       "test-nonce-123",
		AppKeyPublic:         "test-app-key-public",
		AppKeyCertificate:    []byte("test-cert-der"),
	}
	attestationBytes, err := proto.Marshal(attestation)
	require.NoError(t, err)

	t.Run("success with valid sovereign attestation", func(t *testing.T) {
		test.rateLimiter.count = 1
		req := &svidv1.BatchNewX509SVIDRequest{
			Params: []*svidv1.NewX509SVIDParams{
				{
					EntryId:            workloadEntry.Id,
					Csr:                csr,
					SovereignAttestation: attestationBytes,
				},
			},
		}

		resp, err := test.client.BatchNewX509SVID(context.Background(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.Len(t, resp.Results, 1)
		require.NotNil(t, resp.Results[0].Svid)
		require.EqualValues(t, codes.OK, resp.Results[0].Status.Code)
	})

	t.Run("policy violation denies SVID", func(t *testing.T) {
		// Create a new service with restrictive policy
		restrictivePolicy := &sovereignpolicy.PolicyConfig{
			AllowedGeolocations: []string{"USA"}, // Spain not allowed
		}
		
		// Recreate service with restrictive policy
		newService := svid.New(svid.Config{
			EntryFetcher:        test.serviceTest.ef,
			ServerCA:           test.serviceTest.ca,
			TrustDomain:        td,
			DataStore:          test.serviceTest.ds,
			KeylimeClient:      keylime.NewClient("", logrus.New()),
			SovereignPolicyConfig: restrictivePolicy,
		})
		
		// Recreate server with new service
		log, _ := logrustest.NewNullLogger()
		newRateLimiter := &fakeRateLimiter{count: 1}
		overrideContext := func(ctx context.Context) context.Context {
			ctx = rpccontext.WithLogger(ctx, log)
			ctx = rpccontext.WithRateLimiter(ctx, newRateLimiter)
			ctx = rpccontext.WithCallerID(ctx, agentID)
			return ctx
		}

		server := grpctest.StartServer(t, func(s grpc.ServiceRegistrar) {
			svid.RegisterService(s, newService)
		},
			grpctest.OverrideContext(overrideContext),
			grpctest.Middleware(middleware.WithAuditLog(false)),
		)
		defer server.Stop()
		
		conn := server.NewGRPCClient(t)
		newClient := svidv1.NewSVIDClient(conn)

		req := &svidv1.BatchNewX509SVIDRequest{
			Params: []*svidv1.NewX509SVIDParams{
				{
					EntryId:            workloadEntry.Id,
					Csr:                csr,
					SovereignAttestation: attestationBytes,
				},
			},
		}

		resp, err := newClient.BatchNewX509SVID(context.Background(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.Len(t, resp.Results, 1)
		require.Nil(t, resp.Results[0].Svid)
		require.EqualValues(t, codes.PermissionDenied, resp.Results[0].Status.Code)
		require.Contains(t, resp.Results[0].Status.Message, "sovereign policy check failed")
	})

	t.Run("invalid sovereign attestation format", func(t *testing.T) {
		test.rateLimiter.count = 1
		req := &svidv1.BatchNewX509SVIDRequest{
			Params: []*svidv1.NewX509SVIDParams{
				{
					EntryId:            workloadEntry.Id,
					Csr:                csr,
					SovereignAttestation: []byte("invalid-protobuf"),
				},
			},
		}

		resp, err := test.client.BatchNewX509SVID(context.Background(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.Len(t, resp.Results, 1)
		require.Nil(t, resp.Results[0].Svid)
		require.EqualValues(t, codes.PermissionDenied, resp.Results[0].Status.Code)
	})

	t.Run("no sovereign attestation - normal flow", func(t *testing.T) {
		test.rateLimiter.count = 1
		req := &svidv1.BatchNewX509SVIDRequest{
			Params: []*svidv1.NewX509SVIDParams{
				{
					EntryId: workloadEntry.Id,
					Csr:     csr,
					// No sovereign attestation
				},
			},
		}

		resp, err := test.client.BatchNewX509SVID(context.Background(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.Len(t, resp.Results, 1)
		require.NotNil(t, resp.Results[0].Svid)
		require.EqualValues(t, codes.OK, resp.Results[0].Status.Code)
	})
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestBatchNewX509SVID_FeatureFlagDisabled tests that sovereign attestation is ignored when feature flag is off
func TestBatchNewX509SVID_FeatureFlagDisabled(t *testing.T) {
	_ = fflag.Unload()

	test := setupServiceTestWithSovereign(t)
	defer test.Cleanup()

	workloadEntry := &types.Entry{
		Id:       "workload",
		ParentId: api.ProtoFromID(agentID),
		SpiffeId: &types.SPIFFEID{TrustDomain: "example.org", Path: "/workload1"},
	}
	test.ef.entries = []*types.Entry{workloadEntry}

	csr := createCSRForID(t, workloadID)

	attestation := &workload.SovereignAttestation{
		TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("test-quote")),
		ChallengeNonce:       "test-nonce",
		AppKeyPublic:         "test-key",
	}
	attestationBytes, err := proto.Marshal(attestation)
	require.NoError(t, err)

	req := &svidv1.BatchNewX509SVIDRequest{
		Params: []*svidv1.NewX509SVIDParams{
			{
				EntryId:            workloadEntry.Id,
				Csr:                csr,
				SovereignAttestation: attestationBytes,
			},
		},
	}

	// When feature flag is disabled, sovereign attestation should be ignored
	// and normal SVID issuance should proceed
	test.rateLimiter.count = 1
	resp, err := test.client.BatchNewX509SVID(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Results, 1)
	require.NotNil(t, resp.Results[0].Svid)
	require.EqualValues(t, codes.OK, resp.Results[0].Status.Code)
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// setupServiceTestWithSovereign creates a test setup with sovereign components
func setupServiceTestWithSovereign(t *testing.T) *sovereignServiceTest {
	// Use the existing setupServiceTest but override with sovereign config
	baseTest := setupServiceTest(t)
	
	// Create stubbed Keylime client
	keylimeClient := keylime.NewClient("", logrus.New())

	// Create default policy config
	policyConfig := sovereignpolicy.DefaultPolicyConfig()

	// Recreate service with sovereign components
	trustDomain := spiffeid.RequireTrustDomainFromString("example.org")
	service := svid.New(svid.Config{
		EntryFetcher:        baseTest.ef,
		ServerCA:           baseTest.ca,
		TrustDomain:        trustDomain,
		DataStore:          baseTest.ds,
		KeylimeClient:      keylimeClient,
		SovereignPolicyConfig: policyConfig,
	})

	// Recreate server with new service
	log, _ := logrustest.NewNullLogger()
	rateLimiter := &fakeRateLimiter{}
	
	overrideContext := func(ctx context.Context) context.Context {
		ctx = rpccontext.WithLogger(ctx, log)
		ctx = rpccontext.WithRateLimiter(ctx, rateLimiter)
		ctx = rpccontext.WithCallerID(ctx, agentID)
		return ctx
	}

	server := grpctest.StartServer(t, func(s grpc.ServiceRegistrar) {
		svid.RegisterService(s, service)
	},
		grpctest.OverrideContext(overrideContext),
		grpctest.Middleware(middleware.WithAuditLog(false)),
	)

	conn := server.NewGRPCClient(t)

	return &sovereignServiceTest{
		serviceTest: baseTest,
		service:     service,
		client:      svidv1.NewSVIDClient(conn),
		done:        server.Stop,
		rateLimiter: rateLimiter,
	}
}

type sovereignServiceTest struct {
	*serviceTest
	service     *svid.Service
	client      svidv1.SVIDClient
	done        func()
	rateLimiter *fakeRateLimiter
}

func (c *sovereignServiceTest) Cleanup() {
	if c.done != nil {
		c.done()
	}
	if c.serviceTest != nil {
		c.serviceTest.Cleanup()
	}
}

// createCSRForID creates a test CSR for the given SPIFFE ID
func createCSRForID(t *testing.T, id spiffeid.ID) []byte {
	csr := createCSR(t, &x509.CertificateRequest{
		URIs: []*url.URL{id.URL()},
	})
	return csr
}

