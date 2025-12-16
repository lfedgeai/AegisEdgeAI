// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// TPM-based crypto.Signer implementation for mTLS
//
// This package provides a crypto.Signer implementation that uses the TPM App Key
// for signing TLS handshakes, enabling mTLS from SPIRE Agent to SPIRE Server.

package tpmplugin

import (
	"crypto"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io"

	"github.com/sirupsen/logrus"
)

// TPMSigner implements crypto.Signer using the TPM App Key via the TPM plugin
type TPMSigner struct {
	gateway    *TPMPluginGateway
	publicKey  *rsa.PublicKey
	log        logrus.FieldLogger
}

// NewTPMSigner creates a new TPM-based signer
// It requires the TPM plugin gateway and the App Key public key
func NewTPMSigner(gateway *TPMPluginGateway, publicKeyPEM string, log logrus.FieldLogger) (*TPMSigner, error) {
	if gateway == nil {
		return nil, fmt.Errorf("TPM plugin gateway is required")
	}

	// Parse the public key from PEM
	block, _ := pem.Decode([]byte(publicKeyPEM))
	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM public key")
	}

	pubKey, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key: %w", err)
	}

	rsaPubKey, ok := pubKey.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("public key is not RSA")
	}

	return &TPMSigner{
		gateway:   gateway,
		publicKey: rsaPubKey,
		log:       log,
	}, nil
}

// Public returns the public key
func (s *TPMSigner) Public() crypto.PublicKey {
	return s.publicKey
}

// Sign signs the digest using the TPM App Key
// The digest is expected to be a hash of the data to sign
// For TLS, this will be called with the hash of the handshake messages
func (s *TPMSigner) Sign(rand io.Reader, digest []byte, opts crypto.SignerOpts) ([]byte, error) {
	// Determine the hash algorithm from opts
	var hashAlg string
	if opts != nil {
		if h, ok := opts.(crypto.Hash); ok {
			switch h {
			case crypto.SHA256:
				hashAlg = "sha256"
			case crypto.SHA384:
				hashAlg = "sha384"
			case crypto.SHA512:
				hashAlg = "sha512"
			default:
				hashAlg = "sha256" // Default to SHA256
				s.log.WithField("hash_alg", h.String()).Warn("Unified-Identity - Verification: Unsupported hash algorithm, using SHA256")
			}
		} else {
			hashAlg = "sha256" // Default to SHA256
		}
	} else {
		hashAlg = "sha256" // Default to SHA256
	}

	// Determine signature scheme and salt length
	// TLS 1.3 and modern TLS 1.2 prefer RSA-PSS for RSA keys
	// TPM 2.0 supports both PKCS#1 v1.5 (rsassa) and RSA-PSS (rsapss)
	var scheme string = "rsassa" // Default to PKCS#1 v1.5 for backward compatibility
	var saltLength int = -1      // Default salt length (-1 means use hash length for PSS)
	
	if pssOpts, ok := opts.(*rsa.PSSOptions); ok {
		// RSA-PSS requested by TLS
		scheme = "rsapss"
		saltLength = pssOpts.SaltLength
		s.log.WithFields(logrus.Fields{
			"hash_alg":   hashAlg,
			"digest_len": len(digest),
			"pss_salt":   pssOpts.SaltLength,
			"scheme":     scheme,
		}).Info("Unified-Identity - Verification: TLS requested RSA-PSS, using TPM RSA-PSS signing")
	} else {
		s.log.WithFields(logrus.Fields{
			"hash_alg":   hashAlg,
			"digest_len": len(digest),
			"opts_type":  fmt.Sprintf("%T", opts),
			"scheme":     scheme,
		}).Debug("Unified-Identity - Verification: Signing digest using TPM App Key (PKCS#1 v1.5)")
	}

	// Log first few bytes of digest for debugging
	if len(digest) >= 8 {
		s.log.WithField("digest_prefix", fmt.Sprintf("%x", digest[:8])).Debug("Unified-Identity - Verification: Digest prefix")
	}

	// For TLS, we need to sign the digest directly
	// The TPM plugin will handle the signing using tpm2_sign with the appropriate scheme
	// TPM 2.0 supports both PKCS#1 v1.5 (rsassa) and RSA-PSS (rsapss)
	signature, err := s.gateway.SignDataWithHash(digest, hashAlg, scheme, saltLength)
	if err != nil {
		return nil, fmt.Errorf("failed to sign using TPM App Key: %w", err)
	}
	
	s.log.WithFields(logrus.Fields{
		"scheme":       scheme,
		"signature_len": len(signature),
	}).Debug("Unified-Identity - Verification: Signature generated successfully using TPM App Key")

	// Unified-Identity: When delegating to TPM plugin, accept what it gives us
	// The signature will be verified by SPIRE server (for CSRs) or TLS handshake (for mTLS)
	return signature, nil
}

