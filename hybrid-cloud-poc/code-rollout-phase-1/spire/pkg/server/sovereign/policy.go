// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Package sovereign provides policy evaluation for the Unified Identity feature.
package sovereign

import (
	"fmt"
	"strings"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
	"github.com/spiffe/spire/pkg/common/fflag"
)

// PolicyConfig holds configuration for sovereign policy evaluation
type PolicyConfig struct {
	// AllowedGeolocations is a list of allowed geolocation patterns
	// Empty list means all geolocations are allowed
	AllowedGeolocations []string

	// MinGPUUtilizationPct is the minimum GPU utilization percentage required
	MinGPUUtilizationPct float64

	// MinGPUMemoryMB is the minimum GPU memory in MB required
	MinGPUMemoryMB int64

	// RequireHealthyGPUStatus requires GPU status to be "healthy"
	RequireHealthyGPUStatus bool
}

// DefaultPolicyConfig returns a default policy configuration for Phase 1
func DefaultPolicyConfig() *PolicyConfig {
	return &PolicyConfig{
		AllowedGeolocations:    []string{"Spain"}, // Default: allow Spain for Phase 1
		MinGPUUtilizationPct:   0.0,                // No minimum for Phase 1
		MinGPUMemoryMB:         0,                  // No minimum for Phase 1
		RequireHealthyGPUStatus: false,             // Not required for Phase 1
	}
}

// PolicyEvaluationResult represents the result of policy evaluation
type PolicyEvaluationResult struct {
	Allowed bool
	Reason  string
	Claims  *workload.AttestedClaims
}

// EvaluatePolicy evaluates the attested claims against the configured policy
func EvaluatePolicy(log logrus.FieldLogger, claims *workload.AttestedClaims, config *PolicyConfig) (*PolicyEvaluationResult, error) {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	if !fflag.IsSet(fflag.FlagUnifiedIdentity) {
		log.Debug("Unified-Identity feature flag is not enabled, skipping policy evaluation")
		return &PolicyEvaluationResult{
			Allowed: true,
			Reason:  "Unified-Identity feature flag not enabled",
		}, nil
	}

	if claims == nil {
		return &PolicyEvaluationResult{
			Allowed: false,
			Reason:  "claims cannot be nil",
		}, fmt.Errorf("claims cannot be nil")
	}

	log.WithFields(logrus.Fields{
		"geolocation":        claims.Geolocation,
		"host_integrity":     claims.HostIntegrityStatus.String(),
		"gpu_status":         getGPUStatus(claims),
		"gpu_utilization":    getGPUUtilization(claims),
		"gpu_memory_mb":      getGPUMemory(claims),
	}).Info("Unified-Identity - Phase 1: Evaluating policy for attested claims")

	// Evaluate host integrity
	if claims.HostIntegrityStatus != workload.AttestedClaims_PASSED_ALL_CHECKS {
		log.WithField("host_integrity", claims.HostIntegrityStatus.String()).
			Warn("Unified-Identity - Phase 1: Host integrity check failed")
		return &PolicyEvaluationResult{
			Allowed: false,
			Reason:  fmt.Sprintf("host integrity check failed: %s", claims.HostIntegrityStatus.String()),
			Claims:  claims,
		}, nil
	}

	// Evaluate geolocation if configured
	if len(config.AllowedGeolocations) > 0 {
		allowed := false
		for _, allowedGeo := range config.AllowedGeolocations {
			if strings.Contains(claims.Geolocation, allowedGeo) {
				allowed = true
				break
			}
		}
		if !allowed {
			log.WithFields(logrus.Fields{
				"geolocation":        claims.Geolocation,
				"allowed_locations": config.AllowedGeolocations,
			}).Warn("Unified-Identity - Phase 1: Geolocation policy violation")
			return &PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("geolocation '%s' not in allowed list: %v", claims.Geolocation, config.AllowedGeolocations),
				Claims:  claims,
			}, nil
		}
	}

	// Evaluate GPU metrics if present
	if claims.GpuMetricsHealth != nil {
		// Check GPU status
		if config.RequireHealthyGPUStatus && claims.GpuMetricsHealth.Status != "healthy" {
			log.WithField("gpu_status", claims.GpuMetricsHealth.Status).
				Warn("Unified-Identity - Phase 1: GPU status check failed")
			return &PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("GPU status '%s' is not healthy", claims.GpuMetricsHealth.Status),
				Claims:  claims,
			}, nil
		}

		// Check GPU utilization
		if claims.GpuMetricsHealth.UtilizationPct < config.MinGPUUtilizationPct {
			log.WithField("gpu_utilization", claims.GpuMetricsHealth.UtilizationPct).
				Warn("Unified-Identity - Phase 1: GPU utilization below minimum")
			return &PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("GPU utilization %.2f%% is below minimum %.2f%%", claims.GpuMetricsHealth.UtilizationPct, config.MinGPUUtilizationPct),
				Claims:  claims,
			}, nil
		}

		// Check GPU memory
		if claims.GpuMetricsHealth.MemoryMb < config.MinGPUMemoryMB {
			log.WithField("gpu_memory_mb", claims.GpuMetricsHealth.MemoryMb).
				Warn("Unified-Identity - Phase 1: GPU memory below minimum")
			return &PolicyEvaluationResult{
				Allowed: false,
				Reason:  fmt.Sprintf("GPU memory %d MB is below minimum %d MB", claims.GpuMetricsHealth.MemoryMb, config.MinGPUMemoryMB),
				Claims:  claims,
			}, nil
		}
	}

	log.Info("Unified-Identity - Phase 1: Policy evaluation passed")
	return &PolicyEvaluationResult{
		Allowed: true,
		Reason:  "all policy checks passed",
		Claims:  claims,
	}, nil
}

// Helper functions to safely access GPU metrics
func getGPUStatus(claims *workload.AttestedClaims) string {
	if claims.GpuMetricsHealth == nil {
		return "not_available"
	}
	return claims.GpuMetricsHealth.Status
}

func getGPUUtilization(claims *workload.AttestedClaims) float64 {
	if claims.GpuMetricsHealth == nil {
		return 0.0
	}
	return claims.GpuMetricsHealth.UtilizationPct
}

func getGPUMemory(claims *workload.AttestedClaims) int64 {
	if claims.GpuMetricsHealth == nil {
		return 0
	}
	return claims.GpuMetricsHealth.MemoryMb
}

