package credtemplate

import (
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/json"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

// Unified-Identity - Phase 1 & Phase 2: Embed AttestedClaims in X.509 Certificate Extension
// OID for AttestedClaims extension: 1.3.6.1.4.1.99999.1 (Private Enterprise Number - placeholder)
// In production, this should use a registered OID from IANA
var AttestedClaimsExtensionOID = asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 99999, 1}

// AttestedClaimsExtension embeds AttestedClaims as a certificate extension
// This implements Model 3 from federated-jwt.md: "The assurance claims (TPM/Geo) are then anchored to the certificate."
func AttestedClaimsExtension(claims *types.AttestedClaims) (pkix.Extension, error) {
	if claims == nil {
		return pkix.Extension{}, nil
	}

	// Marshal AttestedClaims to JSON
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return pkix.Extension{}, err
	}

	return pkix.Extension{
		Id:       AttestedClaimsExtensionOID,
		Value:    claimsJSON,
		Critical: false, // Non-critical extension - allows graceful degradation
	}, nil
}

// ExtractAttestedClaimsFromCertificate extracts AttestedClaims from a certificate extension
func ExtractAttestedClaimsFromCertificate(cert *x509.Certificate) (*types.AttestedClaims, error) {
	if cert == nil {
		return nil, nil
	}

	for _, ext := range cert.Extensions {
		if ext.Id.Equal(AttestedClaimsExtensionOID) {
			var claims types.AttestedClaims
			if err := json.Unmarshal(ext.Value, &claims); err != nil {
				return nil, err
			}
			return &claims, nil
		}
	}

	return nil, nil
}

