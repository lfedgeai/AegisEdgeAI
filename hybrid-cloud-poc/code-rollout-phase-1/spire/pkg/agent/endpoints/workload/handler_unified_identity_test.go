//go:build unified_identity

package workload_test

import (
	"context"
	"testing"

	"github.com/sirupsen/logrus"
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
			name:       "success",
			expectCode: codes.OK,
			expectResp: &workloadPB.PerformSovereignAttestationResponse{
				Challenge: []byte("stubbed-challenge"),
				Metadata: map[string]string{
					"provider": "stubbed-keylime",
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			params := testParams{
				ExpectLogs: []spiretest.LogEntry{
					{
						Level:   logrus.InfoLevel,
						Message: "Received PerformSovereignAttestation request",
						Data: logrus.Fields{
							"service": "WorkloadAPI",
							"method":  "PerformSovereignAttestation",
						},
					},
					{
						Level:   logrus.InfoLevel,
						Message: "Successfully sent sovereign attestation response",
						Data: logrus.Fields{
							"service": "WorkloadAPI",
							"method":  "PerformSovereignAttestation",
						},
					},
				},
			}
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
