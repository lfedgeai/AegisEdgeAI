"""
Public Key Signature Verification Utilities

This module provides signature verification capabilities using public keys
for systems that don't have TPM2 access (like remote collectors).
"""

import os
import subprocess
import tempfile
import structlog
from typing import Dict, Any, Optional

logger = structlog.get_logger(__name__)


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
        
        # Verify the signature
        return self.verify_signature(combined_data, signature, algorithm)
    
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


class PublicKeyError(Exception):
    """Exception raised for public key verification errors."""
    pass
