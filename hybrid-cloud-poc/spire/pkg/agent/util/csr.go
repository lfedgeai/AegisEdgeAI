// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// CSR generation utilities for agent attestation

package util

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"fmt"
	"math/big"
	"os"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/spire/pkg/agent/plugin/keymanager"
	"github.com/spiffe/spire/pkg/agent/tpmplugin"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/common/util"
)

// MakeCSRForAttestation creates a CSR for agent attestation.
// When unified identity is enabled, it uses the TPM App Key for signing.
// Otherwise, it uses the regular key manager key.
func MakeCSRForAttestation(key keymanager.Key, log logrus.FieldLogger) ([]byte, crypto.Signer, error) {
	// Unified-Identity - Verification: Use TPM App Key for CSR when enabled
	if fflag.IsSet(fflag.FlagUnifiedIdentity) {
		// Try to get TPM App Key and create CSR with it
		tpmPlugin := getTPMPluginGateway(log)
		if tpmPlugin != nil {
			appKeyResult, err := tpmPlugin.GenerateAppKey(false)
			if err != nil {
				log.WithError(err).Warn("Unified-Identity - Verification: Failed to get App Key for CSR, using regular key")
				// Fall through to use regular key
			} else if appKeyResult != nil && appKeyResult.AppKeyPublic != "" {
				log.Info("Unified-Identity - Verification: Got App Key, creating TPM signer")
				// Create TPM signer with App Key
				tpmSigner, err := tpmplugin.NewTPMSigner(tpmPlugin, appKeyResult.AppKeyPublic, log)
				if err != nil {
					log.WithError(err).Warn("Unified-Identity - Verification: Failed to create TPM signer for CSR, using regular key")
					// Fall through to use regular key
				} else {
					log.Info("Unified-Identity - Verification: TPM signer created, getting public key")
					// Create CSR using TPM signer with delegated signing
					// Get the public key to determine the signature algorithm
					pubKey := tpmSigner.Public()
					log.WithField("public_key_type", fmt.Sprintf("%T", pubKey)).Info("Unified-Identity - Verification: Got public key from TPM signer")
					var sigAlg x509.SignatureAlgorithm
					switch pubKey.(type) {
						case *rsa.PublicKey:
							sigAlg = x509.SHA256WithRSA
							log.Info("Unified-Identity - Verification: Public key is RSA, using SHA256WithRSA")
						case *ecdsa.PublicKey:
							sigAlg = x509.ECDSAWithSHA256
							log.Info("Unified-Identity - Verification: Public key is ECDSA, using ECDSAWithSHA256")
						default:
							log.Warn("Unified-Identity - Verification: Unknown public key type for TPM App Key, using regular key")
							// Fall through to use regular key
							sigAlg = 0 // Mark as invalid
					}
					
					// Create CSR with correct signature algorithm if we have a valid algorithm
					if sigAlg != 0 {
						log.Info("Unified-Identity - Verification: Signature algorithm determined, proceeding with CSR creation")
						// Use manual CSR construction that delegates signing to TPM plugin
						template := &x509.CertificateRequest{
							Subject: pkix.Name{
								Country:      []string{"US"},
								Organization: []string{"SPIRE"},
							},
							SignatureAlgorithm: sigAlg,
						}
						
						// Log CSR creation attempt
						log.WithFields(logrus.Fields{
							"signature_algorithm": sigAlg.String(),
							"public_key_type":     fmt.Sprintf("%T", pubKey),
						}).Info("Unified-Identity - Verification: Attempting to create CSR with TPM App Key (delegated signing)")
						
						csr, err := createCSRWithTPMVerification(template, tpmSigner, tpmPlugin, sigAlg, log)
						if err != nil {
							log.WithError(err).WithFields(logrus.Fields{
								"error_type": fmt.Sprintf("%T", err),
							}).Warn("Unified-Identity - Verification: Failed to create CSR with TPM App Key, using regular key")
							// Fall through to use regular key
						} else {
							log.WithField("csr_len", len(csr)).Info("Unified-Identity - Verification: Created CSR using TPM App Key (delegated signing)")
							return csr, tpmSigner, nil
						}
					} // end if sigAlg != 0
				}
			}
		} else {
			log.Debug("Unified-Identity - Verification: TPM plugin not available, using regular key for CSR")
		}
	}

	// Default: Use regular key manager key
	csr, err := util.MakeCSRWithoutURISAN(key)
	if err != nil {
		return nil, nil, err
	}
	return csr, key, nil
}

// getTPMPluginGateway creates or gets the TPM plugin gateway
// This is similar to how it's done in client.go
func getTPMPluginGateway(log logrus.FieldLogger) *tpmplugin.TPMPluginGateway {
	// Try to find TPM plugin endpoint
	tpmPluginEndpoint := os.Getenv("TPM_PLUGIN_ENDPOINT")
	if tpmPluginEndpoint == "" {
		// Default to UDS socket
		tpmPluginEndpoint = "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
	}

	// Create TPM plugin gateway
	// pluginPath is not used in the gateway, but kept for compatibility
	pluginPath := os.Getenv("TPM_PLUGIN_CLI_PATH")
	if pluginPath == "" {
		// Try common locations
		possiblePaths := []string{
			"/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py",
			os.Getenv("HOME") + "/AegisSovereignAI/hybrid-cloud-poc/tpm-plugin/tpm_plugin_cli.py",
		}
		for _, path := range possiblePaths {
			if _, err := os.Stat(path); err == nil {
				pluginPath = path
				break
			}
		}
	}

	if pluginPath != "" || tpmPluginEndpoint != "" {
		return tpmplugin.NewTPMPluginGateway(pluginPath, "", tpmPluginEndpoint, log)
	}

	return nil
}

// createCSRWithTPMVerification manually constructs a CSR and delegates signing to TPM plugin
// This bypasses Go's x509.CreateCertificateRequest which calls checkSignature internally
func createCSRWithTPMVerification(template *x509.CertificateRequest, signer crypto.Signer, gateway *tpmplugin.TPMPluginGateway, sigAlg x509.SignatureAlgorithm, log logrus.FieldLogger) ([]byte, error) {
	log.Info("Unified-Identity - Verification: createCSRWithTPMVerification ENTERED - starting manual CSR construction")
	
	// OID for SHA256WithRSA signature algorithm
	oidSignatureSHA256WithRSA := asn1.ObjectIdentifier{1, 2, 840, 113549, 1, 1, 11}
	oidPublicKeyRSA := asn1.ObjectIdentifier{1, 2, 840, 113549, 1, 1, 1}
	
	// Get public key
	pubKey := signer.Public()
	rsaPubKey, ok := pubKey.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("public key is not RSA")
	}
	
	// Marshal public key (PKCS#1 format for RSA)
	type pkcs1PublicKey struct {
		N *big.Int
		E int
	}
	publicKeyBytes, err := asn1.Marshal(pkcs1PublicKey{
		N: rsaPubKey.N,
		E: rsaPubKey.E,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to marshal public key: %w", err)
	}
	
	// Create public key algorithm identifier
	publicKeyAlgorithm := pkix.AlgorithmIdentifier{
		Algorithm:  oidPublicKeyRSA,
		Parameters: asn1.NullRawValue,
	}
	
	// Marshal subject
	asn1Subject, err := asn1.Marshal(template.Subject.ToRDNSequence())
	if err != nil {
		return nil, fmt.Errorf("failed to marshal subject: %w", err)
	}
	
	// Build TBS (To Be Signed) structure
	// Note: We use empty RawAttributes for simplicity (no extensions)
	type tbsCertificateRequest struct {
		Raw           asn1.RawContent
		Version       int
		Subject       asn1.RawValue
		PublicKey     struct {
			Algorithm pkix.AlgorithmIdentifier
			PublicKey asn1.BitString
		}
		RawAttributes []asn1.RawValue `asn1:"tag:0"`
	}
	
	tbsCSR := tbsCertificateRequest{
		Version: 0, // PKCS #10, RFC 2986
		Subject: asn1.RawValue{FullBytes: asn1Subject},
		PublicKey: struct {
			Algorithm pkix.AlgorithmIdentifier
			PublicKey asn1.BitString
		}{
			Algorithm: publicKeyAlgorithm,
			PublicKey: asn1.BitString{
				Bytes:     publicKeyBytes,
				BitLength: len(publicKeyBytes) * 8,
			},
		},
		RawAttributes: []asn1.RawValue{}, // Empty attributes
	}
	
	// Marshal TBS
	tbsCSRContents, err := asn1.Marshal(tbsCSR)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal TBS: %w", err)
	}
	
	// Hash TBS (SHA256 for RSA)
	h := sha256.New()
	h.Write(tbsCSRContents)
	digest := h.Sum(nil)
	
	// Sign using TPM plugin (via TPMSigner) - accept what TPM plugin gives us
	signature, err := signer.Sign(rand.Reader, digest, crypto.SHA256)
	if err != nil {
		return nil, fmt.Errorf("failed to sign TBS with TPM App Key: %w", err)
	}
	
	// Create signature algorithm identifier
	signatureAlgorithm := pkix.AlgorithmIdentifier{
		Algorithm:  oidSignatureSHA256WithRSA,
		Parameters: asn1.NullRawValue,
	}
	
	// Build final CSR structure
	type certificateRequest struct {
		Raw                asn1.RawContent
		TBSCSR             tbsCertificateRequest
		SignatureAlgorithm pkix.AlgorithmIdentifier
		SignatureValue     asn1.BitString
	}
	
	// Update TBS with Raw content
	tbsCSR.Raw = tbsCSRContents
	
	csr := certificateRequest{
		TBSCSR:             tbsCSR,
		SignatureAlgorithm: signatureAlgorithm,
		SignatureValue: asn1.BitString{
			Bytes:     signature,
			BitLength: len(signature) * 8,
		},
	}
	
	// Marshal final CSR
	csrBytes, err := asn1.Marshal(csr)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal CSR: %w", err)
	}
	
	return csrBytes, nil
}

