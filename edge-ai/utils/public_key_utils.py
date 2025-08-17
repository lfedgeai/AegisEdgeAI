"""
Public Key Signature Verification Utilities

This module provides signature verification capabilities using public keys
for systems that don't have TPM2 access (like remote collectors).
"""

import os
import subprocess
import tempfile
import structlog
import logging
import hashlib
from typing import Dict, Any, Optional

# Set log level to DEBUG
logging.basicConfig(level=logging.DEBUG)

logger = structlog.get_logger(__name__)


def generate_public_key_hash(public_key_content: str) -> str:
    """
    Generate a SHA-256 hash of the public key content.
    
    Args:
        public_key_content: Raw public key content (base64 without PEM headers)
        
    Returns:
        SHA-256 hash of the public key content
    """
    return hashlib.sha256(public_key_content.encode('utf-8')).hexdigest()


class PublicKeyUtils:
    """
    Utility class for public key signature verification.
    
    This class provides methods to verify signatures using public keys
    without requiring TPM2 access, suitable for remote collectors.
    """
    
    def __init__(self, public_key_path: str, verify_script_path: str):
        """
        Initialize PublicKeyUtils.
        
        Args:
            public_key_path: Path to the public key file (PEM format)
            verify_script_path: Path to the verify_app_message_signature.sh script
        """
        self.public_key_path = public_key_path
        self.verify_script_path = verify_script_path
        
        # Verify files exist
        if not os.path.exists(public_key_path):
            raise FileNotFoundError(f"Public key file not found: {public_key_path}")
        
        if not os.path.exists(verify_script_path):
            raise FileNotFoundError(f"Verify script not found: {verify_script_path}")
        
        # Make script executable
        os.chmod(verify_script_path, 0o755)
        
        logger.info("PublicKeyUtils initialization", 
                   public_key_path=os.path.abspath(public_key_path),
                   verify_script_path=os.path.abspath(verify_script_path))
        
        logger.info("PublicKeyUtils initialized", 
                   public_key_path=public_key_path,
                   verify_script_path=verify_script_path)
    
    def verify_signature(self, data: bytes, signature: bytes, algorithm: str = "sha256") -> bool:
        """
        Verify signature using public key via verify_app_message_signature.sh script.
        
        Args:
            data: Original data that was signed
            signature: Signature to verify
            algorithm: Signature algorithm (currently only sha256 supported)
            
        Returns:
            True if signature is valid, False otherwise
        """
        try:
            # Create files with expected names in current directory
            script_dir = os.path.dirname(os.path.abspath(self.verify_script_path))
            if not script_dir:
                script_dir = os.getcwd()
            
            # Create message file with expected name
            msg_file_path = os.path.join(script_dir, "appsig_info.bin")
            with open(msg_file_path, 'wb') as msg_file:
                msg_file.write(data)
            
            # Create signature file with expected name
            sig_file_path = os.path.join(script_dir, "appsig.bin")
            with open(sig_file_path, 'wb') as sig_file:
                sig_file.write(signature)
            
            # Use existing public key file
            pubkey_file_path = os.path.join(script_dir, "appsk_pubkey.pem")
            
            try:
                # Set up environment for the script
                env = os.environ.copy()
                env['PUBKEY'] = pubkey_file_path
                env['MESSAGE'] = msg_file_path
                env['SIGNATURE'] = sig_file_path
                
                # Run the verification script with absolute paths
                script_dir = os.path.dirname(os.path.abspath(self.verify_script_path))
                if not script_dir:
                    script_dir = os.getcwd()
                
                logger.info("Running verification script", 
                           script_path=self.verify_script_path,
                           script_dir=script_dir,
                           env_pubkey=env.get('PUBKEY'),
                           env_message=env.get('MESSAGE'),
                           env_signature=env.get('SIGNATURE'))
                
                result = subprocess.run(
                    [os.path.abspath(self.verify_script_path)],
                    capture_output=True,
                    text=True,
                    env=env,
                    cwd=script_dir
                )
                
                logger.info("Verification result", 
                           return_code=result.returncode,
                           stdout=result.stdout.strip(),
                           stderr=result.stderr.strip())
                
                success = result.returncode == 0
                if success:
                    logger.info("Signature verification successful")
                else:
                    logger.error("Signature verification failed", 
                               return_code=result.returncode,
                               stderr=result.stderr)
                
                return success
                
            finally:
                # Clean up files
                for file_path in [msg_file_path, sig_file_path]:
                    if os.path.exists(file_path):
                        os.unlink(file_path)
                        logger.debug("Cleaned up file", file_path=file_path)
                        
        except Exception as e:
            logger.error("Error verifying signature", error=str(e))
            return False
    
    def verify_with_nonce(self, data: bytes, nonce: bytes, signature: bytes, 
                         algorithm: str = "sha256") -> bool:
        """
        Verify signature with nonce (combines data + nonce before verification).
        
        Args:
            data: Original data
            nonce: Nonce used in signature
            signature: Signature to verify
            algorithm: Signature algorithm
            
        Returns:
            True if signature is valid, False otherwise
        """
        # Combine data and nonce (same as agent's signing process)
        combined_data = data + nonce
        
        # Use pure OpenSSL verification (no TPM files required)
        return self.verify_signature_pure_openssl(combined_data, signature, algorithm)
    
    def verify_with_nonce_and_public_key(self, data: bytes, nonce: bytes, signature: bytes, 
                                        public_key_content: str, algorithm: str = "sha256") -> bool:
        """
        Verify signature with nonce using a specific public key content.
        
        Args:
            data: Original data
            nonce: Nonce used in signature
            signature: Signature to verify
            public_key_content: Raw public key content (PEM format)
            algorithm: Signature algorithm
            
        Returns:
            True if signature is valid, False otherwise
        """
        logger.info("🔍 [PUBLIC_KEY_UTILS] Starting verification with nonce and public key", 
                   data_length=len(data),
                   nonce_length=len(nonce),
                   signature_length=len(signature),
                   public_key_length=len(public_key_content))
        
        # Combine data and nonce (same as agent's signing process)
        combined_data = data + nonce
        
        logger.info("🔍 [PUBLIC_KEY_UTILS] Combined data for verification", 
                   combined_data_length=len(combined_data))
        
        # Convert hex signature to bytes for verification
        signature_bytes = bytes.fromhex(signature)
        
        # Use pure OpenSSL verification with specific public key
        result = self.verify_signature_pure_openssl_with_key(combined_data, signature_bytes, public_key_content, algorithm)
        
        logger.info("🔍 [PUBLIC_KEY_UTILS] Verification result", result=result)
        
        return result
    
    def verify_signature_pure_openssl(self, data: bytes, signature: bytes, 
                                    algorithm: str = "sha256") -> bool:
        """
        Verify signature using pure OpenSSL (no TPM files required).
        
        Args:
            data: Data to verify
            signature: Signature to verify
            algorithm: Signature algorithm
            
        Returns:
            True if signature is valid, False otherwise
        """
        try:
            import hashlib
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import rsa, padding
            
            # Read the public key
            with open(self.public_key_path, 'rb') as f:
                public_key = serialization.load_pem_public_key(f.read())
            
            # Hash the data
            if algorithm == "sha256":
                hash_algorithm = hashes.SHA256()
            elif algorithm == "sha384":
                hash_algorithm = hashes.SHA384()
            elif algorithm == "sha512":
                hash_algorithm = hashes.SHA512()
            else:
                logger.error("Unsupported algorithm", algorithm=algorithm)
                return False
            
            # Verify the signature
            try:
                public_key.verify(
                    signature,
                    data,
                    padding.PKCS1v15(),
                    hash_algorithm
                )
                logger.info("Pure OpenSSL signature verification successful")
                return True
            except Exception as e:
                logger.warning("Pure OpenSSL signature verification failed", error=str(e))
                return False
                
        except Exception as e:
            logger.error("Error in pure OpenSSL verification", error=str(e))
            return False
    
    def verify_signature_pure_openssl_with_key(self, data: bytes, signature: bytes, 
                                             public_key_content: str, algorithm: str = "sha256") -> bool:
        """
        Verify signature using pure OpenSSL with specific public key content.
        Uses the same technique as verify_app_message_signature.sh.
        
        Args:
            data: Data to verify
            signature: Signature to verify (hex string)
            public_key_content: Raw public key content (PEM format)
            algorithm: Signature algorithm
            
        Returns:
            True if signature is valid, False otherwise
        """
        try:
            import tempfile
            import subprocess
            import hashlib
            
            # Create temporary files for the verification process
            with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as pubkey_file, \
                 tempfile.NamedTemporaryFile(mode='wb', suffix='.bin', delete=False) as data_file, \
                 tempfile.NamedTemporaryFile(mode='wb', suffix='.bin', delete=False) as sig_file, \
                 tempfile.NamedTemporaryFile(mode='wb', suffix='.hash', delete=False) as hash_file:
                
                # Write public key content to temporary file
                pubkey_file.write(public_key_content)
                pubkey_file.flush()
                
                # Write data to temporary file
                data_file.write(data)
                data_file.flush()
                
                # Convert hex signature to binary and write to temporary file
                signature_bytes = bytes.fromhex(signature)
                sig_file.write(signature_bytes)
                sig_file.flush()
                
                # Hash the data with SHA-256 (same as the shell script)
                hash_obj = hashlib.sha256()
                hash_obj.update(data)
                hash_bytes = hash_obj.digest()
                hash_file.write(hash_bytes)
                hash_file.flush()
                
                # Use openssl pkeyutl -verify (same as the shell script)
                cmd = [
                    'openssl', 'pkeyutl', '-verify',
                    '-pubin', '-inkey', pubkey_file.name,
                    '-sigfile', sig_file.name,
                    '-in', hash_file.name,
                    '-pkeyopt', 'digest:sha256'
                ]
                
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                # Clean up temporary files
                for temp_file in [pubkey_file.name, data_file.name, sig_file.name, hash_file.name]:
                    try:
                        os.unlink(temp_file)
                    except:
                        pass
                
                if result.returncode == 0:
                    logger.info("🔍 [PUBLIC_KEY_UTILS] OpenSSL pkeyutl signature verification successful")
                    return True
                else:
                    logger.warning("🔍 [PUBLIC_KEY_UTILS] OpenSSL pkeyutl signature verification failed", 
                                 stderr=result.stderr, stdout=result.stdout)
                    return False
                    
        except Exception as e:
            logger.error("Error in OpenSSL pkeyutl verification", error=str(e))
            return False
    
    def get_public_key_info(self) -> Dict[str, Any]:
        """
        Get information about the public key.
        
        Returns:
            Dictionary containing public key information
        """
        try:
            with open(self.public_key_path, 'r') as f:
                key_content = f.read()
            
            return {
                "public_key_path": self.public_key_path,
                "key_size": len(key_content),
                "format": "PEM",
                "algorithm": "RSA",
                "timestamp": os.path.getmtime(self.public_key_path)
            }
        except Exception as e:
            logger.error("Error getting public key info", error=str(e))
            return {
                "public_key_path": self.public_key_path,
                "error": str(e)
            }

    def extract_raw_public_key_content(self, pem_content: str) -> str:
        """
        Extract raw public key content from PEM format.
        
        Args:
            pem_content: PEM formatted public key
            
        Returns:
            Raw base64-encoded public key content (without headers)
        """
        try:
            # Remove PEM headers and footers
            lines = pem_content.strip().split('\n')
            content_lines = []
            in_content = False
            
            for line in lines:
                if line.startswith('-----BEGIN PUBLIC KEY-----'):
                    in_content = True
                    continue
                elif line.startswith('-----END PUBLIC KEY-----'):
                    break
                elif in_content:
                    content_lines.append(line)
            
            # Join all content lines and remove any remaining whitespace
            raw_content = ''.join(content_lines).strip()
            
            logger.info("🔧 [PUBLIC_KEY_UTILS] Extracted raw public key content", 
                       original_length=len(pem_content),
                       raw_length=len(raw_content))
            
            return raw_content
            
        except Exception as e:
            logger.error("Error extracting raw public key content", error=str(e))
            raise
    
    def raw_to_pem_format(self, raw_content: str) -> str:
        """
        Convert raw base64 public key content to PEM format.
        
        Args:
            raw_content: Raw base64-encoded public key content
            
        Returns:
            PEM formatted public key
        """
        try:
            # Add PEM headers and format with line breaks
            pem_content = f"-----BEGIN PUBLIC KEY-----\n{raw_content}\n-----END PUBLIC KEY-----"
            
            logger.info("🔧 [PUBLIC_KEY_UTILS] Converted raw content to PEM format", 
                       raw_length=len(raw_content),
                       pem_length=len(pem_content))
            
            return pem_content
            
        except Exception as e:
            logger.error("Error converting raw content to PEM format", error=str(e))
            raise


class PublicKeyError(Exception):
    """Exception raised for public key verification errors."""
    pass
