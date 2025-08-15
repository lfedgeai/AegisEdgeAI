"""
SSL/TLS utilities for certificate generation and management.
Provides functions for creating self-signed certificates and managing TLS connections.
"""

import os
import ssl
import tempfile
from datetime import datetime, timedelta
from typing import Tuple, Optional
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import structlog

logger = structlog.get_logger(__name__)


class SSLError(Exception):
    """Custom exception for SSL-related errors."""
    pass


class SSLUtils:
    """SSL utility class for certificate generation and management."""
    
    @staticmethod
    def generate_self_signed_certificate(
        common_name: str,
        organization: str = "OpenTelemetry Microservice",
        country: str = "US",
        state: str = "CA",
        city: str = "San Francisco",
        valid_days: int = 365,
        key_size: int = 2048
    ) -> Tuple[bytes, bytes]:
        """
        Generate a self-signed certificate and private key.
        
        Args:
            common_name: Common name for the certificate
            organization: Organization name
            country: Country code
            state: State or province
            city: City
            valid_days: Certificate validity in days
            key_size: RSA key size in bits
            
        Returns:
            Tuple of (certificate_pem, private_key_pem)
        """
        try:
            # Generate private key
            private_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=key_size,
            )
            
            # Create certificate subject
            subject = issuer = x509.Name([
                x509.NameAttribute(NameOID.COUNTRY_NAME, country),
                x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, state),
                x509.NameAttribute(NameOID.LOCALITY_NAME, city),
                x509.NameAttribute(NameOID.ORGANIZATION_NAME, organization),
                x509.NameAttribute(NameOID.COMMON_NAME, common_name),
            ])
            
            # Create certificate
            cert = x509.CertificateBuilder().subject_name(
                subject
            ).issuer_name(
                issuer
            ).public_key(
                private_key.public_key()
            ).serial_number(
                x509.random_serial_number()
            ).not_valid_before(
                datetime.utcnow()
            ).not_valid_after(
                datetime.utcnow() + timedelta(days=valid_days)
            ).add_extension(
                x509.SubjectAlternativeName([
                    x509.DNSName(common_name),
                    x509.IPAddress(x509.IPv4Address("127.0.0.1")),
                ]),
                critical=False,
            ).sign(private_key, hashes.SHA256())
            
            # Serialize certificate and private key
            cert_pem = cert.public_bytes(serialization.Encoding.PEM)
            key_pem = private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            )
            
            return cert_pem, key_pem
            
        except Exception as e:
            logger.error("Failed to generate self-signed certificate", error=str(e))
            raise SSLError(f"Certificate generation failed: {e}")
    
    @staticmethod
    def save_certificate_and_key(
        cert_pem: bytes,
        key_pem: bytes,
        cert_path: str,
        key_path: str
    ) -> None:
        """
        Save certificate and private key to files.
        
        Args:
            cert_pem: Certificate in PEM format
            key_pem: Private key in PEM format
            cert_path: Path to save certificate
            key_path: Path to save private key
        """
        try:
            # Save certificate
            with open(cert_path, 'wb') as cert_file:
                cert_file.write(cert_pem)
            
            # Save private key
            with open(key_path, 'wb') as key_file:
                key_file.write(key_pem)
            
            # Set proper permissions for private key
            os.chmod(key_path, 0o600)
            
            logger.info("Certificate and key saved", cert_path=cert_path, key_path=key_path)
            
        except Exception as e:
            logger.error("Failed to save certificate and key", error=str(e))
            raise SSLError(f"Failed to save certificate and key: {e}")
    
    @staticmethod
    def create_ssl_context(
        cert_path: Optional[str] = None,
        key_path: Optional[str] = None,
        ca_cert_path: Optional[str] = None,
        verify_mode: ssl.VerifyMode = ssl.CERT_REQUIRED,
        check_hostname: bool = True
    ) -> ssl.SSLContext:
        """
        Create SSL context for client or server connections.
        
        Args:
            cert_path: Path to certificate file
            key_path: Path to private key file
            ca_cert_path: Path to CA certificate file
            verify_mode: SSL verification mode
            check_hostname: Whether to check hostname
            
        Returns:
            SSL context
        """
        try:
            context = ssl.create_default_context()
            
            if cert_path and key_path:
                context.load_cert_chain(cert_path, key_path)
            
            if ca_cert_path:
                context.load_verify_locations(ca_cert_path)
            
            context.verify_mode = verify_mode
            context.check_hostname = check_hostname
            
            return context
            
        except Exception as e:
            logger.error("Failed to create SSL context", error=str(e))
            raise SSLError(f"SSL context creation failed: {e}")
    
    @staticmethod
    def generate_certificate_files(
        common_name: str,
        cert_path: str,
        key_path: str,
        **kwargs
    ) -> None:
        """
        Generate and save self-signed certificate files.
        
        Args:
            common_name: Common name for the certificate
            cert_path: Path to save certificate
            key_path: Path to save private key
            **kwargs: Additional arguments for certificate generation
        """
        cert_pem, key_pem = SSLUtils.generate_self_signed_certificate(
            common_name, **kwargs
        )
        SSLUtils.save_certificate_and_key(cert_pem, key_pem, cert_path, key_path)
    
    @staticmethod
    def create_temp_certificate(common_name: str, **kwargs) -> Tuple[str, str]:
        """
        Create temporary certificate files.
        
        Args:
            common_name: Common name for the certificate
            **kwargs: Additional arguments for certificate generation
            
        Returns:
            Tuple of (cert_path, key_path)
        """
        cert_pem, key_pem = SSLUtils.generate_self_signed_certificate(
            common_name, **kwargs
        )
        
        # Create temporary files
        cert_fd, cert_path = tempfile.mkstemp(suffix='.pem')
        key_fd, key_path = tempfile.mkstemp(suffix='.pem')
        
        # Write certificate and key
        os.write(cert_fd, cert_pem)
        os.write(key_fd, key_pem)
        
        # Close file descriptors
        os.close(cert_fd)
        os.close(key_fd)
        
        # Set proper permissions for private key
        os.chmod(key_path, 0o600)
        
        return cert_path, key_path
