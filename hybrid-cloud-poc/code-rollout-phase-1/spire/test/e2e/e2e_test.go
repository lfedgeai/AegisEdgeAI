package e2e_test

import (
	"context"
	"testing"
	"time"

	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/test/spiretest"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
)

func TestSovereignAttestationE2E(t *testing.T) {
	t.Parallel()

	// Create a new E2E test environment
	env := spiretest.New(t)
	defer env.Cleanup()

	// Start the SPIRE server
	server := env.NewServer()
	server.Start()

	// Start the SPIRE agent
	agent := env.NewAgent(server)
	agent.Start()

	// Create a workload client
	conn, err := grpc.DialContext(context.Background(), agent.WorkloadAPIAddr(), grpc.WithInsecure())
	require.NoError(t, err)
	defer conn.Close()
	client := workload.NewSpiffeWorkloadAPIClient(conn)

	// Fetch an X.509 SVID with a SovereignAttestation
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	stream, err := client.FetchX509SVID(ctx, &workload.X509SVIDRequest{
		SovereignAttestation: &types.SovereignAttestation{
			TpmSignedAttestation: "test",
		},
	})
	require.NoError(t, err)

	resp, err := stream.Recv()
	require.NoError(t, err)

	// Verify the response
	require.NotNil(t, resp)
	require.NotEmpty(t, resp.Svids)
	require.NotEmpty(t, resp.AttestedClaims)
	require.Equal(t, "es-es", resp.AttestedClaims[0].Geolocation)

	// Verify the server logs
	logs := server.Logs()
	require.Contains(t, logs, "Unified Identity - Phase 1: Sovereign attestation verified")
}
