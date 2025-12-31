// Package tlspolicy provides for configuration and enforcement of policies
// relating to TLS.
package tlspolicy

import (
	"crypto/tls"

	"github.com/hashicorp/go-hclog"
)

// Policy describes policy options to be applied to a TLS configuration.
//
// A zero-initialised Policy provides reasonable defaults.
type Policy struct {
	// RequirePQKEM determines if a post-quantum-safe KEM should be required for
	// TLS connections.
	RequirePQKEM bool

	// PreferPKCS1v15 forces TLS to prefer PKCS#1 v1.5 signatures over RSA-PSS.
	// This is useful when using TPM keys that only support PKCS#1 v1.5 (rsassa scheme).
	// Setting this to true will limit TLS to version 1.2 (which better supports PKCS#1 v1.5).
	PreferPKCS1v15 bool
}

// Not exported by crypto/tls, so we define it here from the I-D.
const x25519Kyber768Draft00 tls.CurveID = 0x6399

// LogPolicy logs an informational message reporting the configured policy,
// aiding administrators to determine what policy options have been
// successfully enabled.
func LogPolicy(policy Policy, logger hclog.Logger) {
	if policy.RequirePQKEM {
		logger.Debug("Experimental option 'require_pq_kem' is enabled; all TLS connections will require use of a post-quantum safe KEM")
	}
	if policy.PreferPKCS1v15 {
		logger.Debug("Option 'prefer_pkcs1v15' is enabled; TLS will prefer PKCS#1 v1.5 signatures (limited to TLS 1.2)")
	}
}

// ApplyPolicy applies the policy options in policy to a given tls.Config,
// which is assumed to have already been obtained from the go-spiffe tlsconfig
// package.
func ApplyPolicy(config *tls.Config, policy Policy) error {
	if policy.RequirePQKEM {
		// List only known PQ-safe KEMs as valid curves.
		config.CurvePreferences = []tls.CurveID{
			x25519Kyber768Draft00,
		}

		// Require TLS 1.3, as all PQ-safe KEMs require it anyway.
		if config.MinVersion < tls.VersionTLS13 {
			config.MinVersion = tls.VersionTLS13
		}
	}

	if policy.PreferPKCS1v15 {
		// Limit to TLS 1.2 to better support PKCS#1 v1.5 signatures
		// TLS 1.3 requires RSA-PSS for RSA keys, but TPM only supports PKCS#1 v1.5
		if config.MinVersion < tls.VersionTLS12 {
			config.MinVersion = tls.VersionTLS12
		}
		// Set MaxVersion to TLS 1.2 to prevent TLS 1.3 negotiation
		config.MaxVersion = tls.VersionTLS12
	}

	return nil
}
