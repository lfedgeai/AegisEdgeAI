package credtemplate

import (
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/json"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// OID for AttestedClaims extension: 1.3.6.1.4.1.99999.1 (Private Enterprise Number - placeholder)
// In production, this should use a registered OID from IANA
var AttestedClaimsExtensionOID = asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 99999, 1}

// AttestedClaimsExtension embeds Unified Identity claims as a certificate extension.
// If unifiedJSON is provided it is embedded verbatim; otherwise the legacy
// AttestedClaims proto is marshalled to JSON.
func AttestedClaimsExtension(claims *types.AttestedClaims, unifiedJSON []byte) (pkix.Extension, error) {
	if len(unifiedJSON) > 0 {
		return pkix.Extension{
			Id:       AttestedClaimsExtensionOID,
			Value:    unifiedJSON,
			Critical: false,
		}, nil
	}

	if claims == nil {
		return pkix.Extension{}, nil
	}

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

// ExtractUnifiedIdentityJSONFromCertificate returns the raw unified identity
// JSON payload stored in the certificate extension, if present.
func ExtractUnifiedIdentityJSONFromCertificate(cert *x509.Certificate) ([]byte, error) {
	if cert == nil {
		return nil, nil
	}

	for _, ext := range cert.Extensions {
		if ext.Id.Equal(AttestedClaimsExtensionOID) {
			return ext.Value, nil
		}
	}
	return nil, nil
}

// ExtractAttestedClaimsFromCertificate parses the extension and returns a
// legacy AttestedClaims proto for backwards compatibility. If the extension is
// stored using the newer Unified Identity schema, it is converted into the
// proto representation best effort.
func ExtractAttestedClaimsFromCertificate(cert *x509.Certificate) (*types.AttestedClaims, error) {
	raw, err := ExtractUnifiedIdentityJSONFromCertificate(cert)
	if err != nil || raw == nil {
		return nil, err
	}

	var claims types.AttestedClaims
	if err := json.Unmarshal(raw, &claims); err == nil {
		return &claims, nil
	}

	// Attempt to interpret Unified Identity claims schema.
	var generic map[string]any
	if err := json.Unmarshal(raw, &generic); err != nil {
		return nil, err
	}
	converted := convertUnifiedJSONToAttestedClaims(generic)
	if converted == nil {
		return nil, nil
	}
	return converted, nil
}

func convertUnifiedJSONToAttestedClaims(data map[string]any) *types.AttestedClaims {
	if data == nil {
		return nil
	}

	claims := &types.AttestedClaims{}

	if geoRaw, ok := data["grc.geolocation"]; ok {
		if geoMap, ok := geoRaw.(map[string]any); ok {
			// Build Geolocation object from map
			geo := &types.Geolocation{}
			if typeVal, ok := geoMap["type"].(string); ok {
				geo.Type = typeVal
			}
			if sensorIdVal, ok := geoMap["sensor_id"].(string); ok {
				geo.SensorId = sensorIdVal
			}
			if valueVal, ok := geoMap["value"].(string); ok {
				geo.Value = valueVal
			}
			// Unified-Identity: Extract sensor_imei and sensor_imsi
			if sensorImeiVal, ok := geoMap["sensor_imei"].(string); ok {
				geo.SensorImei = sensorImeiVal
			}
			if sensorImsiVal, ok := geoMap["sensor_imsi"].(string); ok {
				geo.SensorImsi = sensorImsiVal
			}
			// Task 2f: Extract sensor_msisdn
			if sensorMsisdnVal, ok := geoMap["sensor_msisdn"].(string); ok {
				geo.SensorMsisdn = sensorMsisdnVal
			}
			if geo.Type != "" || geo.SensorId != "" {
				claims.Geolocation = geo
			}
		}
	}

	if tpmRaw, ok := data["grc.tpm-attestation"]; ok {
		if tpmMap, ok := tpmRaw.(map[string]any); ok {
			if verifiedRaw, ok := tpmMap["verified-claims"]; ok {
				if verifiedMap, ok := verifiedRaw.(map[string]any); ok {
					if geoMap, ok := verifiedMap["geolocation"].(map[string]any); ok && claims.Geolocation == nil {
						// Build Geolocation object from verified claims
						geo := &types.Geolocation{}
						if typeVal, ok := geoMap["type"].(string); ok {
							geo.Type = typeVal
						}
						if sensorIdVal, ok := geoMap["sensor_id"].(string); ok {
							geo.SensorId = sensorIdVal
							}
						if valueVal, ok := geoMap["value"].(string); ok {
							geo.Value = valueVal
							}
						// Unified-Identity: Extract sensor_imei and sensor_imsi
						if sensorImeiVal, ok := geoMap["sensor_imei"].(string); ok {
							geo.SensorImei = sensorImeiVal
						}
						if sensorImsiVal, ok := geoMap["sensor_imsi"].(string); ok {
							geo.SensorImsi = sensorImsiVal
						}
						// Task 2f: Extract sensor_msisdn
						if sensorMsisdnVal, ok := geoMap["sensor_msisdn"].(string); ok {
							geo.SensorMsisdn = sensorMsisdnVal
						}
						if geo.Type != "" || geo.SensorId != "" {
							claims.Geolocation = geo
						}
					}
				}
			}
		}
	}

	return claims
}
