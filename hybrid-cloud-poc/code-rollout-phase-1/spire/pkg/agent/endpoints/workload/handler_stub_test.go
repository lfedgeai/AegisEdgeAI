//go:build !unified_identity

package workload_test

import (
	"context"
	"testing"

	workloadPB "github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/test/spiretest"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc/codes"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
func TestPerformSovereignAttestation(t *testing.T) {
	for _, tt := range []struct {
		name       string
		expectCode codes.Code
		expectMsg  string
		expectResp *workloadPB.PerformSovereignAttestationResponse
	}{
		{
			name:       "unimplemented",
			expectCode: codes.Unimplemented,
			expectMsg:  "sovereign attestation is not supported",
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			params := testParams{}
			runTest(t, params,
				func(ctx context.Context, client workloadPB.SpiffeWorkloadAPIClient) {
					stream, err := client.PerformSovereignAttestation(ctx, &workloadPB.PerformSovereignAttestationRequest{})
					require.NoError(t, err)

					resp, err := stream.Recv()
					spiretest.RequireGRPCStatus(t, err, tt.expectCode, tt.expectMsg)
					spiretest.RequireProtoEqual(t, tt.expectResp, resp)
				})
		})
	}
}
