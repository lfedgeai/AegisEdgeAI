// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Validation tests for feature flag behavior
package validation

import (
	"testing"

	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagDefaultState validates that feature flag defaults to disabled
func TestFeatureFlagDefaultState(t *testing.T) {
	// Ensure clean state
	fflag.Unload()

	// Verify default state
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity),
		"Feature flag should be disabled by default")

	fflag.Unload()
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagEnableDisable validates enabling and disabling the flag
func TestFeatureFlagEnableDisable(t *testing.T) {
	fflag.Unload()
	defer fflag.Unload()

	// Test enabling
	err := fflag.Load(fflag.RawConfig{"Unified-Identity"})
	require.NoError(t, err, "Should be able to enable feature flag")
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity),
		"Feature flag should be enabled after Load")

	// Can't test disabling without Unload (which is for testing only)
	// But we can verify it's still enabled
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagCaseSensitive validates that feature flag name is case-sensitive
func TestFeatureFlagCaseSensitive(t *testing.T) {
	fflag.Unload()
	defer fflag.Unload()

	// Test with wrong case
	err := fflag.Load(fflag.RawConfig{"unified-identity"}) // lowercase
	assert.Error(t, err, "Should reject lowercase flag name")
	assert.Contains(t, err.Error(), "unknown feature flag")

	// Test with correct case
	err = fflag.Load(fflag.RawConfig{"Unified-Identity"}) // correct case
	assert.NoError(t, err)
	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagMultipleFlags validates behavior with multiple flags
func TestFeatureFlagMultipleFlags(t *testing.T) {
	fflag.Unload()
	defer fflag.Unload()

	// Test with Unified-Identity and test flag
	err := fflag.Load(fflag.RawConfig{"Unified-Identity", "i_am_a_test_flag"})
	require.NoError(t, err)

	assert.True(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
	assert.True(t, fflag.IsSet(fflag.FlagTestFlag))
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagLoadOnce validates that Load can only be called once
func TestFeatureFlagLoadOnce(t *testing.T) {
	fflag.Unload()

	// First load should succeed
	err := fflag.Load(fflag.RawConfig{"Unified-Identity"})
	require.NoError(t, err)

	// Second load should fail
	err = fflag.Load(fflag.RawConfig{"Unified-Identity"})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already been loaded")

	fflag.Unload()
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagUnloadBeforeLoad validates that Unload before Load fails
func TestFeatureFlagUnloadBeforeLoad(t *testing.T) {
	fflag.Unload()

	// Try to unload before loading
	err := fflag.Unload()
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not been loaded")
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// TestFeatureFlagEmptyConfig validates behavior with empty config
func TestFeatureFlagEmptyConfig(t *testing.T) {
	fflag.Unload()
	defer fflag.Unload()

	// Empty config should be valid (all flags disabled)
	err := fflag.Load(fflag.RawConfig{})
	require.NoError(t, err)

	// All flags should be disabled
	assert.False(t, fflag.IsSet(fflag.FlagUnifiedIdentity))
	assert.False(t, fflag.IsSet(fflag.FlagTestFlag))
}

