//go:build !unified_identity

package catalog

import (
	"github.com/spiffe/spire/pkg/common/catalog"
)

func appendBuiltIns(builtIns []catalog.BuiltIn) []catalog.BuiltIn {
	return builtIns
}
