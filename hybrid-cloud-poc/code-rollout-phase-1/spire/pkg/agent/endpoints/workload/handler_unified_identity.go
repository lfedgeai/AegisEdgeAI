//go:build unified_identity

package workload

import (
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/agent/api/rpccontext"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
func (h *Handler) PerformSovereignAttestation(req *workload.PerformSovereignAttestationRequest, stream workload.SpiffeWorkloadAPI_PerformSovereignAttestationServer) error {
	log := rpccontext.Logger(stream.Context())
	log.Info("Received PerformSovereignAttestation request")

	// In Phase 1, we are just stubbing this out.
	// We will return a canned response.
	err := stream.Send(&workload.PerformSovereignAttestationResponse{
		Challenge: []byte("stubbed-challenge"),
		Metadata: map[string]string{
			"provider": "stubbed-keylime",
		},
	})
	if err != nil {
		log.WithError(err).Error("Failed to send sovereign attestation response")
		return err
	}
	log.Info("Successfully sent sovereign attestation response")

	return nil
}
