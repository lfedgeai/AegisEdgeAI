"""
Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)

Unit tests for App Key Certificate validation and TPM Quote verification.
"""

import base64
import datetime
import unittest
from unittest.mock import MagicMock, patch

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric.padding import PKCS1v15
from cryptography.x509.oid import NameOID

from keylime import app_key_verification, config


class TestAppKeyVerification(unittest.TestCase):
    """Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)"""

    def setUp(self):
        """Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)"""
        # Generate test keys
        self.ak_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048, backend=None)
        self.ak_public_key = self.ak_private_key.public_key()
        self.ak_public_pem = self.ak_public_key.public_bytes(
            encoding=serialization.Encoding.PEM, format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode("utf-8")

        self.app_key_private = rsa.generate_private_key(public_exponent=65537, key_size=2048, backend=None)
        self.app_key_public = self.app_key_private.public_key()
        self.app_key_public_pem = self.app_key_public.public_bytes(
            encoding=serialization.Encoding.PEM, format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode("utf-8")

        # Create a self-signed certificate for the App Key (signed by AK)
        subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Test App Key")])
        now = datetime.datetime.now(datetime.timezone.utc)
        self.app_key_cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(self.app_key_public)
            .serial_number(x509.random_serial_number())
            .not_valid_before(now)
            .not_valid_after(now + datetime.timedelta(days=365))
            .sign(self.ak_private_key, hashes.SHA256())
        )

        self.app_key_cert_pem = self.app_key_cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
        self.app_key_cert_b64 = base64.b64encode(self.app_key_cert.public_bytes(serialization.Encoding.DER)).decode(
            "utf-8"
        )

    def test_feature_flag_check(self):
        """Unified-Identity - Phase 2: Test feature flag check"""
        with patch.object(config, "getboolean", return_value=True):
            self.assertTrue(app_key_verification.is_unified_identity_enabled())

        with patch.object(config, "getboolean", return_value=False):
            self.assertFalse(app_key_verification.is_unified_identity_enabled())

    def test_validate_app_key_certificate_success(self):
        """Unified-Identity - Phase 2: Test successful App Key Certificate validation"""
        valid, cert, error = app_key_verification.validate_app_key_certificate(
            self.app_key_cert_b64, self.ak_public_pem
        )

        self.assertTrue(valid)
        self.assertIsNotNone(cert)
        self.assertIsNone(error)
        self.assertIsInstance(cert, x509.Certificate)

    def test_validate_app_key_certificate_invalid_base64(self):
        """Unified-Identity - Phase 2: Test certificate validation with invalid base64"""
        valid, cert, error = app_key_verification.validate_app_key_certificate("invalid!!!", self.ak_public_pem)

        self.assertFalse(valid)
        self.assertIsNone(cert)
        self.assertIsNotNone(error)
        self.assertIn("decode", error.lower())

    def test_validate_app_key_certificate_invalid_signature(self):
        """Unified-Identity - Phase 2: Test certificate validation with invalid signature"""
        # Create a certificate signed by a different key
        other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048, backend=None)
        subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Test App Key")])
        now = datetime.datetime.now(datetime.timezone.utc)
        bad_cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(self.app_key_public)
            .serial_number(x509.random_serial_number())
            .not_valid_before(now)
            .not_valid_after(now + datetime.timedelta(days=365))
            .sign(other_key, hashes.SHA256())
        )

        bad_cert_b64 = base64.b64encode(bad_cert.public_bytes(serialization.Encoding.DER)).decode("utf-8")

        valid, cert, error = app_key_verification.validate_app_key_certificate(bad_cert_b64, self.ak_public_pem)

        self.assertFalse(valid)
        self.assertIsNotNone(error)

    def test_extract_app_key_public_from_cert(self):
        """Unified-Identity - Phase 2: Test extracting public key from certificate"""
        pubkey_pem = app_key_verification.extract_app_key_public_from_cert(self.app_key_cert)

        self.assertIsNotNone(pubkey_pem)
        self.assertIn("BEGIN PUBLIC KEY", pubkey_pem)
        self.assertIn("END PUBLIC KEY", pubkey_pem)

    def test_verify_app_key_public_matches_cert_success(self):
        """Unified-Identity - Phase 2: Test successful public key matching"""
        matches, error = app_key_verification.verify_app_key_public_matches_cert(
            self.app_key_public_pem, self.app_key_cert
        )

        self.assertTrue(matches)
        self.assertIsNone(error)

    def test_verify_app_key_public_matches_cert_mismatch(self):
        """Unified-Identity - Phase 2: Test public key mismatch"""
        # Use a different public key
        other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048, backend=None)
        other_public_pem = other_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM, format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode("utf-8")

        matches, error = app_key_verification.verify_app_key_public_matches_cert(other_public_pem, self.app_key_cert)

        self.assertFalse(matches)
        self.assertIsNotNone(error)

    @patch("keylime.app_key_verification.cloud_verifier_common.get_tpm_instance")
    def test_verify_quote_with_app_key_success(self, mock_get_tpm):
        """Unified-Identity - Phase 2: Test successful quote verification"""
        # Mock TPM instance
        mock_tpm = MagicMock()
        mock_tpm.check_quote.return_value = None  # No failure means success
        mock_get_tpm.return_value = mock_tpm

        # Create a properly formatted compound quote: r<quoteblob>:<sigblob>:<pcrblob>
        quoteblob = base64.b64encode(b"test_quoteblob_data").decode("utf-8")
        sigblob = base64.b64encode(b"test_sigblob_data").decode("utf-8")
        pcrblob = base64.b64encode(b"test_pcrblob_data").decode("utf-8")
        quote = f"r{quoteblob}:{sigblob}:{pcrblob}"
        nonce = "test_nonce_1234567890123456"
        hash_alg = "sha256"

        valid, error, failure = app_key_verification.verify_quote_with_app_key(
            quote, self.app_key_public_pem, nonce, hash_alg
        )

        self.assertTrue(valid)
        self.assertIsNone(error)
        self.assertIsNone(failure)
        mock_tpm.check_quote.assert_called_once()

    @patch("keylime.app_key_verification.cloud_verifier_common.get_tpm_instance")
    def test_verify_quote_with_app_key_failure(self, mock_get_tpm):
        """Unified-Identity - Phase 2: Test quote verification failure"""
        # Mock TPM instance with failure
        from keylime.failure import Component, Event, Failure

        mock_tpm = MagicMock()
        failure_obj = Failure(Component.QUOTE_VALIDATION)
        failure_obj.add_event("quote_error", {"message": "Invalid signature"}, False)
        mock_tpm.check_quote.return_value = failure_obj
        mock_get_tpm.return_value = mock_tpm

        # Create a properly formatted compound quote: r<quoteblob>:<sigblob>:<pcrblob>
        quoteblob = base64.b64encode(b"test_quoteblob_data").decode("utf-8")
        sigblob = base64.b64encode(b"test_sigblob_data").decode("utf-8")
        pcrblob = base64.b64encode(b"test_pcrblob_data").decode("utf-8")
        quote = f"r{quoteblob}:{sigblob}:{pcrblob}"
        nonce = "test_nonce_1234567890123456"
        hash_alg = "sha256"

        valid, error, failure = app_key_verification.verify_quote_with_app_key(
            quote, self.app_key_public_pem, nonce, hash_alg
        )

        self.assertFalse(valid)
        self.assertIsNotNone(error)
        self.assertIsNotNone(failure)


if __name__ == "__main__":
    unittest.main()

