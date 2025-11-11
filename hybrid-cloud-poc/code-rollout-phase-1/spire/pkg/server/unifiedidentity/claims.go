package unifiedidentity

import (
	"encoding/base64"
	"encoding/json"
	"fmt"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

const (
	KeySourceTPMApp   = "tpm-app-key"
	KeySourceWorkload = "workload-key"
)

// BuildClaimsJSON constructs the grc.* Unified Identity claims blob described in
// docs/federated-jwt.md. The resulting JSON can be embedded directly into the
// SVID extension or other federated artifacts.
func BuildClaimsJSON(spiffeID, keySource, workloadPublicKeyPEM string, sovereignAttestation *types.SovereignAttestation, attestedClaims *types.AttestedClaims) ([]byte, error) {
	if keySource != KeySourceTPMApp && keySource != KeySourceWorkload {
		return nil, fmt.Errorf("unifiedidentity: unsupported key source %q", keySource)
	}

	claims := make(map[string]any)

	workload := map[string]any{
		"workload-id": spiffeID,
		"key-source":  keySource,
	}
	if keySource == KeySourceWorkload && workloadPublicKeyPEM != "" {
		workload["public-key"] = workloadPublicKeyPEM
	}
	if sovereignAttestation != nil && sovereignAttestation.WorkloadCodeHash != "" {
		workload["workload-code-hash"] = sovereignAttestation.WorkloadCodeHash
	}
	claims["grc.workload"] = workload

	tpm := map[string]any{}
	if sovereignAttestation != nil {
		if sovereignAttestation.AppKeyPublic != "" {
			tpm["app-key-public"] = sovereignAttestation.AppKeyPublic
		}
		if len(sovereignAttestation.AppKeyCertificate) > 0 {
			tpm["app-key-certificate"] = base64.StdEncoding.EncodeToString(sovereignAttestation.AppKeyCertificate)
		}
		if sovereignAttestation.TpmSignedAttestation != "" {
			tpm["quote"] = sovereignAttestation.TpmSignedAttestation
		}
		if sovereignAttestation.ChallengeNonce != "" {
			tpm["challenge-nonce"] = sovereignAttestation.ChallengeNonce
		}
	}

	if attestedClaims != nil {
		verified := map[string]any{}
		if attestedClaims.Geolocation != "" {
			verified["geolocation"] = attestedClaims.Geolocation
		}
		if attestedClaims.HostIntegrityStatus != types.AttestedClaims_HOST_INTEGRITY_UNSPECIFIED {
			verified["host_integrity_status"] = attestedClaims.HostIntegrityStatus.String()
		}
		if gpu := attestedClaims.GpuMetricsHealth; gpu != nil {
			gpuMap := map[string]any{
				"status": gpu.Status,
			}
			if gpu.UtilizationPct != 0 {
				gpuMap["utilization_pct"] = gpu.UtilizationPct
			}
			if gpu.MemoryMb != 0 {
				gpuMap["memory_mb"] = gpu.MemoryMb
			}
			verified["gpu_metrics_health"] = gpuMap
		}
		if len(verified) > 0 {
			tpm["verified-claims"] = verified
		}

		if attestedClaims.Geolocation != "" {
			claims["grc.geolocation"] = map[string]any{
				"raw": attestedClaims.Geolocation,
			}
		}
	}

	if len(tpm) > 0 {
		claims["grc.tpm-attestation"] = tpm
	}

	return json.Marshal(claims)
}
