// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Package policy provides policy evaluation logic for AttestedClaims.
package policy

import (
	"fmt"
	"strings"

	"github.com/sirupsen/logrus"
)

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// PolicyConfig holds configuration for policy evaluation
type PolicyConfig struct {
	AllowedGeolocations []string // Allowed geolocation patterns (e.g., "Spain:*", "Germany:Berlin")
	RequireIntegrity    bool     // Require host integrity to be PASSED_ALL_CHECKS
	MaxGPUUtilization   float64  // Maximum GPU utilization percentage (0-100)
	MinGPUMemoryMB      int64    // Minimum GPU memory in MB
	Logger              logrus.FieldLogger
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// PolicyResult represents the result of policy evaluation
type PolicyResult struct {
	Allowed bool
	Reason  string
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// AttestedClaims represents verified facts from Keylime
type AttestedClaims struct {
	Geolocation         string
	HostIntegrityStatus string
	GPUMetricsHealth    struct {
		Status        string
		UtilizationPct float64
		MemoryMB      int64
	}
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Engine evaluates AttestedClaims against configured policies
type Engine struct {
	config PolicyConfig
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// NewEngine creates a new policy engine
func NewEngine(config PolicyConfig) *Engine {
	if config.Logger == nil {
		config.Logger = logrus.New()
	}

	return &Engine{
		config: config,
	}
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Evaluate checks if the AttestedClaims meet the policy requirements
func (e *Engine) Evaluate(claims *AttestedClaims) (*PolicyResult, error) {
	e.config.Logger.WithFields(logrus.Fields{
		"geolocation":   claims.Geolocation,
		"integrity":     claims.HostIntegrityStatus,
		"gpu_status":    claims.GPUMetricsHealth.Status,
		"gpu_util":      claims.GPUMetricsHealth.UtilizationPct,
		"gpu_memory_mb": claims.GPUMetricsHealth.MemoryMB,
	}).Info("Unified-Identity - Phase 3: Evaluating AttestedClaims against policy")

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Check geolocation
	if len(e.config.AllowedGeolocations) > 0 {
		allowed := false
		for _, pattern := range e.config.AllowedGeolocations {
			if e.matchesGeolocation(claims.Geolocation, pattern) {
				allowed = true
				break
			}
		}
		if !allowed {
			e.config.Logger.WithFields(logrus.Fields{
				"geolocation": claims.Geolocation,
				"allowed":     e.config.AllowedGeolocations,
			}).Warn("Unified-Identity - Phase 3: Geolocation policy violation")
			return &PolicyResult{
				Allowed: false,
				Reason:  fmt.Sprintf("geolocation %s not in allowed list", claims.Geolocation),
			}, nil
		}
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Check host integrity
	if e.config.RequireIntegrity {
		if claims.HostIntegrityStatus != "passed_all_checks" {
			e.config.Logger.WithField("integrity", claims.HostIntegrityStatus).
				Warn("Unified-Identity - Phase 3: Host integrity policy violation")
			return &PolicyResult{
				Allowed: false,
				Reason:  fmt.Sprintf("host integrity status is %s, required passed_all_checks", claims.HostIntegrityStatus),
			}, nil
		}
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Check GPU metrics
	if e.config.MaxGPUUtilization > 0 {
		if claims.GPUMetricsHealth.UtilizationPct > e.config.MaxGPUUtilization {
			e.config.Logger.WithField("utilization", claims.GPUMetricsHealth.UtilizationPct).
				Warn("Unified-Identity - Phase 3: GPU utilization policy violation")
			return &PolicyResult{
				Allowed: false,
				Reason:  fmt.Sprintf("GPU utilization %.2f%% exceeds maximum %.2f%%", claims.GPUMetricsHealth.UtilizationPct, e.config.MaxGPUUtilization),
			}, nil
		}
	}

	if e.config.MinGPUMemoryMB > 0 {
		if claims.GPUMetricsHealth.MemoryMB < e.config.MinGPUMemoryMB {
			e.config.Logger.WithField("memory_mb", claims.GPUMetricsHealth.MemoryMB).
				Warn("Unified-Identity - Phase 3: GPU memory policy violation")
			return &PolicyResult{
				Allowed: false,
				Reason:  fmt.Sprintf("GPU memory %d MB is below minimum %d MB", claims.GPUMetricsHealth.MemoryMB, e.config.MinGPUMemoryMB),
			}, nil
		}
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// All checks passed
	e.config.Logger.Info("Unified-Identity - Phase 3: Policy evaluation passed")
	return &PolicyResult{
		Allowed: true,
		Reason:  "all policy checks passed",
	}, nil
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// matchesGeolocation checks if a geolocation matches a pattern
// Patterns can be exact matches or wildcards (e.g., "Spain:*" matches "Spain: N40.4168, W3.7038", "*" matches everything)
func (e *Engine) matchesGeolocation(geolocation, pattern string) bool {
	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Universal wildcard - matches everything
	if pattern == "*" {
		return true
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Exact match
	if geolocation == pattern {
		return true
	}

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	// Wildcard match (e.g., "Spain:*")
	if strings.HasSuffix(pattern, ":*") {
		prefix := strings.TrimSuffix(pattern, ":*")
		return strings.HasPrefix(geolocation, prefix+":")
	}

	return false
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// ConvertKeylimeAttestedClaims converts Keylime AttestedClaims to policy AttestedClaims
func ConvertKeylimeAttestedClaims(keylimeClaims *KeylimeAttestedClaims) *AttestedClaims {
	return &AttestedClaims{
		Geolocation:         keylimeClaims.Geolocation,
		HostIntegrityStatus: keylimeClaims.HostIntegrityStatus,
		GPUMetricsHealth: struct {
			Status        string
			UtilizationPct float64
			MemoryMB      int64
		}{
			Status:        keylimeClaims.GPUMetricsHealth.Status,
			UtilizationPct: keylimeClaims.GPUMetricsHealth.UtilizationPct,
			MemoryMB:      keylimeClaims.GPUMetricsHealth.MemoryMB,
		},
	}
}

// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// KeylimeAttestedClaims represents the AttestedClaims from Keylime client
type KeylimeAttestedClaims struct {
	Geolocation         string
	HostIntegrityStatus string
	GPUMetricsHealth    struct {
		Status        string
		UtilizationPct float64
		MemoryMB      int64
	}
}

