// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Package unifiedidentity provides server-side integration for Unified Identity features
package unifiedidentity

import (
	"fmt"
	"strings"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
)

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// PolicyConfig represents the configuration for policy evaluation
type PolicyConfig struct {
	// AllowedGeolocations is a list of allowed geolocation patterns (e.g., "Spain: *", "Germany: *")
	AllowedGeolocations []string
	// RequireHostIntegrityPassed requires that host integrity status is PASSED_ALL_CHECKS
	RequireHostIntegrityPassed bool
	// MinGPUUtilizationPct is the minimum GPU utilization percentage (0-100)
	MinGPUUtilizationPct float64
	// MaxGPUUtilizationPct is the maximum GPU utilization percentage (0-100)
	MaxGPUUtilizationPct float64
	// RequireHealthyGPU requires that GPU status is "healthy"
	RequireHealthyGPU bool
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// PolicyEvaluationResult represents the result of policy evaluation
type PolicyEvaluationResult struct {
	Allowed bool
	Reason  string
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// DefaultPolicyConfig returns a default policy configuration
func DefaultPolicyConfig() PolicyConfig {
	return PolicyConfig{
		AllowedGeolocations:        []string{"Spain: *", "Germany: *"},
		RequireHostIntegrityPassed:  true,
		MinGPUUtilizationPct:        0.0,
		MaxGPUUtilizationPct:        100.0,
		RequireHealthyGPU:           true,
	}
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// EvaluatePolicy evaluates attested claims against the configured policy
func EvaluatePolicy(claims *workload.AttestedClaims, config PolicyConfig, log logrus.FieldLogger) PolicyEvaluationResult {
	if claims == nil {
		log.Error("[Unified-Identity Phase 1] Claims are nil")
		return PolicyEvaluationResult{
			Allowed: false,
			Reason:  "claims are nil",
		}
	}

	log.WithFields(logrus.Fields{
		"geolocation":      claims.Geolocation,
		"integrity_status": claims.HostIntegrityStatus.String(),
		"has_gpu_metrics":  claims.GpuMetricsHealth != nil,
	}).Debug("[Unified-Identity Phase 1] Evaluating policy")

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Check geolocation
	if len(config.AllowedGeolocations) > 0 {
		geolocationAllowed := false
		for _, allowedPattern := range config.AllowedGeolocations {
			if matchesGeolocationPattern(claims.Geolocation, allowedPattern) {
				geolocationAllowed = true
				break
			}
		}
		if !geolocationAllowed {
			log.WithFields(logrus.Fields{
				"geolocation":      claims.Geolocation,
				"allowed_patterns": config.AllowedGeolocations,
			}).Warn("[Unified-Identity Phase 1] Geolocation policy violation")
			return PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("geolocation %s not in allowed list", claims.Geolocation),
			}
		}
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Check host integrity
	if config.RequireHostIntegrityPassed {
		if claims.HostIntegrityStatus != workload.AttestedClaims_PASSED_ALL_CHECKS {
			log.WithField("integrity_status", claims.HostIntegrityStatus.String()).
				Warn("[Unified-Identity Phase 1] Host integrity policy violation")
			return PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("host integrity status is %s, required PASSED_ALL_CHECKS", claims.HostIntegrityStatus.String()),
			}
		}
	}

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Check GPU metrics if present
	if claims.GpuMetricsHealth != nil {
		if config.RequireHealthyGPU {
			if claims.GpuMetricsHealth.Status != "healthy" {
				log.WithField("gpu_status", claims.GpuMetricsHealth.Status).
					Warn("[Unified-Identity Phase 1] GPU health policy violation")
				return PolicyEvaluationResult{
					Allowed: false,
					Reason:  fmt.Sprintf("GPU status is %s, required healthy", claims.GpuMetricsHealth.Status),
				}
			}
		}

		if claims.GpuMetricsHealth.UtilizationPct < config.MinGPUUtilizationPct {
			log.WithFields(logrus.Fields{
				"utilization": claims.GpuMetricsHealth.UtilizationPct,
				"min_required": config.MinGPUUtilizationPct,
			}).Warn("[Unified-Identity Phase 1] GPU utilization below minimum")
			return PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("GPU utilization %.2f%% below minimum %.2f%%", claims.GpuMetricsHealth.UtilizationPct, config.MinGPUUtilizationPct),
			}
		}

		if claims.GpuMetricsHealth.UtilizationPct > config.MaxGPUUtilizationPct {
			log.WithFields(logrus.Fields{
				"utilization": claims.GpuMetricsHealth.UtilizationPct,
				"max_allowed": config.MaxGPUUtilizationPct,
			}).Warn("[Unified-Identity Phase 1] GPU utilization above maximum")
			return PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("GPU utilization %.2f%% above maximum %.2f%%", claims.GpuMetricsHealth.UtilizationPct, config.MaxGPUUtilizationPct),
			}
		}
	}

	log.Info("[Unified-Identity Phase 1] Policy evaluation passed")
	return PolicyEvaluationResult{
		Allowed: true,
		Reason:  "all policy checks passed",
	}
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// matchesGeolocationPattern checks if a geolocation matches a pattern
// Pattern format: "Country: *" or "Country: City" or exact match
func matchesGeolocationPattern(geolocation, pattern string) bool {
	pattern = strings.TrimSpace(pattern)
	geolocation = strings.TrimSpace(geolocation)

	// Exact match
	if geolocation == pattern {
		return true
	}

	// Pattern match (e.g., "Spain: *")
	if strings.HasSuffix(pattern, ": *") {
		prefix := strings.TrimSuffix(pattern, ": *")
		if strings.HasPrefix(geolocation, prefix+":") {
			return true
		}
	}

	return false
}

