//go:build !unified_identity

package workload

import (
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
func (h *Handler) PerformSovereignAttestation(req *workload.PerformSovereignAttestationRequest, stream workload.SpiffeWorkloadAPI_PerformSovereignAttestationServer) error {
	return status.Error(codes.Unimplemented, "sovereign attestation is not supported")
}
