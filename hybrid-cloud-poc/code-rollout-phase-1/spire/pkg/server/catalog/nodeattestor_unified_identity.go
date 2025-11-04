//go:build unified_identity

package catalog

import (
	"github.com/spiffe/spire/pkg/common/catalog"
	"github.com/spiffe/spire/pkg/server/plugin/nodeattestor/sovereign"
)

func appendBuiltIns(builtIns []catalog.BuiltIn) []catalog.BuiltIn {
	return append(builtIns, sovereign.BuiltIn())
}
