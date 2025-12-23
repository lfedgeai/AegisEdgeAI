package catalog

import (
	"github.com/spiffe/spire/pkg/agent/plugin/collector"
	"github.com/spiffe/spire/pkg/agent/plugin/collector/sovereign"
	"github.com/spiffe/spire/pkg/common/catalog"
)

type collectorRepository struct {
	collector.Repository
}

func (repo *collectorRepository) Binder() any {
	return repo.SetCollector
}

func (repo *collectorRepository) GetCollector() (collector.Collector, bool) {
	return repo.Collector, repo.Collector != nil
}

func (repo *collectorRepository) Constraints() catalog.Constraints {
	return catalog.MaybeOne()
}

func (repo *collectorRepository) Versions() []catalog.Version {
	return []catalog.Version{
		collectorV1{},
	}
}

func (repo *collectorRepository) BuiltIns() []catalog.BuiltIn {
	return []catalog.BuiltIn{
		sovereign.BuiltIn(),
	}
}

type collectorV1 struct{}

func (collectorV1) New() catalog.Facade { return new(collector.V1) }
func (collectorV1) Deprecated() bool    { return false }
