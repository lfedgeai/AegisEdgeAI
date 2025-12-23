package collector

import (
	"context"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/catalog"
)

// Collector is the interface for the collector plugin.
// It is used to collect sovereign attestation data from the host.
type Collector interface {
	catalog.PluginInfo

	// CollectSovereignAttestation collects sovereign attestation data.
	CollectSovereignAttestation(ctx context.Context, nonce string) (*types.SovereignAttestation, error)
}
