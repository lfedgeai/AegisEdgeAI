// The fflag package implements a basic singleton pattern for the purpose of
// providing SPIRE with a system-wide feature flagging facility. Feature flags
// can be easily added here, in a single central location, and be consumed
// throughout the codebase.
package fflag

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
)

// Flag represents a feature flag and its configuration name
type Flag string

// RawConfig is a list of feature flags that should be flipped on, in their string
// representations. It is loaded directly from the config file.
type RawConfig []string

// To add a feature flag, decleare it here along with its config name.
// Then, add it to the `flags` package-level singleton map below, setting the
// appropriate default value. Flags should generally be opt-in and default to
// false, with exceptions for flags that are enabled by default (e.g., Unified-Identity).
// Flags that default to true can be explicitly disabled via config using "-FlagName" syntax.
const (
	// FlagTestFlag is defined purely for testing purposes.
	FlagTestFlag Flag = "i_am_a_test_flag"

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// FlagUnifiedIdentity enables the Unified Identity feature for Sovereign AI,
	// which includes SPIRE API changes for SovereignAttestation and policy
	// evaluation logic. This flag is enabled by default but can be explicitly
	// disabled via configuration for backward compatibility.
	FlagUnifiedIdentity Flag = "Unified-Identity"
)

var (
	singleton = struct {
		flags  map[Flag]bool
		loaded bool
		mtx    *sync.RWMutex
	}{
		flags: map[Flag]bool{
			FlagTestFlag:        false,
			FlagUnifiedIdentity: true, // Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime) - Enabled by default
		},
		loaded: false,
		mtx:    new(sync.RWMutex),
	}
)

// Load initializes the fflag package and configures its feature flag state
// based on the configuration input. Feature flags are designed to be
// Write-Once-Read-Many, and as such, Load can be called only once (except when Using Unload function
// for test scenarios, which will reset states enabling Load to be called again).
// Load will return an error if it is called more than once, if the configuration input
// cannot be parsed, or if an unrecognized flag is set.
// 
// Unified-Identity: Flags can be explicitly disabled by prefixing with "-" (e.g., "-Unified-Identity")
// to disable a flag that defaults to enabled.
func Load(rc RawConfig) error {
	singleton.mtx.Lock()
	defer singleton.mtx.Unlock()

	if singleton.loaded {
		return errors.New("feature flags have already been loaded")
	}

	badFlags := []string{}
	goodFlags := []Flag{}
	disabledFlags := []Flag{}
	
	for _, rawFlag := range rc {
		// Unified-Identity: Support explicit disabling with "-" prefix
		if strings.HasPrefix(rawFlag, "-") {
			flagName := rawFlag[1:]
			if _, ok := singleton.flags[Flag(flagName)]; !ok {
				badFlags = append(badFlags, rawFlag)
				continue
			}
			disabledFlags = append(disabledFlags, Flag(flagName))
			continue
		}
		
		if _, ok := singleton.flags[Flag(rawFlag)]; !ok {
			badFlags = append(badFlags, rawFlag)
			continue
		}

		goodFlags = append(goodFlags, Flag(rawFlag))
	}

	if len(badFlags) > 0 {
		sort.Strings(badFlags)
		return fmt.Errorf("unknown feature flag(s): %v", badFlags)
	}

	// Set explicitly enabled flags to true
	for _, f := range goodFlags {
		singleton.flags[f] = true
	}
	
	// Unified-Identity: Explicitly disable flags that were prefixed with "-"
	for _, f := range disabledFlags {
		singleton.flags[f] = false
	}

	singleton.loaded = true
	return nil
}

// Unload resets the feature flags states to its default values. This function is intended to be used for testing
// purposes only, it is not expected to be called by the normal execution of SPIRE.
// If called before Load, it will reset flags to their defaults (useful for test setup).
func Unload() error {
	singleton.mtx.Lock()
	defer singleton.mtx.Unlock()

	// Unified-Identity: Reset flags to their default values
	// FlagTestFlag defaults to false
	// FlagUnifiedIdentity defaults to true (enabled by default)
	singleton.flags[FlagTestFlag] = false
	singleton.flags[FlagUnifiedIdentity] = true

	singleton.loaded = false
	return nil
}

// IsSet can be used to determine whether a particular feature flag is
// set.
func IsSet(f Flag) bool {
	singleton.mtx.RLock()
	defer singleton.mtx.RUnlock()

	return singleton.flags[f]
}
