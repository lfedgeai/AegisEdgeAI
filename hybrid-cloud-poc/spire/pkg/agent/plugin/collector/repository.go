package collector

type Repository struct {
	Collector Collector
}

func (repo *Repository) GetCollector() (Collector, bool) {
	return repo.Collector, repo.Collector != nil
}

func (repo *Repository) SetCollector(collector Collector) {
	repo.Collector = collector
}

func (repo *Repository) Clear() {
	repo.Collector = nil
}
