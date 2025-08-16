"""
Public Key Allowlist Utilities

This module provides signature verification capabilities using a list of allowed public keys
for systems that don't have TPM2 access (like remote collectors).
"""

import os
import json
import subprocess
import tempfile
import hashlib
import structlog
from typing import Dict, Any, Optional, List
from dataclasses import dataclass
from datetime import datetime

logger = structlog.get_logger(__name__)


@dataclass
class AllowedPublicKey:
    """Represents an allowed public key with metadata."""
    id: str
    name: str
    description: str
    public_key_path: str
    fingerprint: str
    created_at: str
    status: str
    allowed_regions: List[str]
    allowed_services: List[str]


class PublicKeyAllowlistError(Exception):
    """Exception raised for public key allowlist errors."""
    pass


class PublicKeyAllowlistUtils:
    """
    Utility class for public key allowlist signature verification.
    
    This class provides methods to verify signatures using a list of allowed public keys
    without requiring TPM2 access, suitable for remote collectors.
    """
    
    def __init__(self, allowlist_file_path: str, verify_script_path: str):
        """
        Initialize PublicKeyAllowlistUtils.
        
        Args:
            allowlist_file_path: Path to the JSON file containing allowed public keys
            verify_script_path: Path to the verify_app_message_signature.sh script
        """
        self.allowlist_file_path = allowlist_file_path
        self.verify_script_path = verify_script_path
        self.allowed_keys: List[AllowedPublicKey] = []
        
        # Verify files exist
        if not os.path.exists(allowlist_file_path):
            raise FileNotFoundError(f"Allowlist file not found: {allowlist_file_path}")
        
        if not os.path.exists(verify_script_path):
            raise FileNotFoundError(f"Verify script not found: {verify_script_path}")
        
        # Make script executable
        os.chmod(verify_script_path, 0o755)
        
        # Load allowed keys
        self._load_allowed_keys()
        
        logger.info("PublicKeyAllowlistUtils initialization", 
                   allowlist_file_path=os.path.abspath(allowlist_file_path),
                   verify_script_path=os.path.abspath(verify_script_path),
                   allowed_keys_count=len(self.allowed_keys))
    
    def _load_allowed_keys(self):
        """Load allowed public keys from the JSON file."""
        try:
            with open(self.allowlist_file_path, 'r') as f:
                keys_data = json.load(f)
            
            self.allowed_keys = []
            for key_data in keys_data:
                if key_data.get("status") == "active":
                    allowed_key = AllowedPublicKey(
                        id=key_data["id"],
                        name=key_data["name"],
                        description=key_data["description"],
                        public_key_path=key_data["public_key_path"],
                        fingerprint=key_data["fingerprint"],
                        created_at=key_data["created_at"],
                        status=key_data["status"],
                        allowed_regions=key_data.get("allowed_regions", []),
                        allowed_services=key_data.get("allowed_services", [])
                    )
                    self.allowed_keys.append(allowed_key)
            
            logger.info("Loaded allowed public keys", count=len(self.allowed_keys))
            
        except Exception as e:
            logger.error("Failed to load allowed keys", error=str(e))
            raise PublicKeyAllowlistError(f"Failed to load allowed keys: {e}")
    
    def _verify_with_public_key(self, data: bytes, signature: bytes, public_key_path: str, algorithm: str = "sha256") -> bool:
        """
        Verify signature using a specific public key via verify_app_message_signature.sh script.
        
        Args:
            data: Original data that was signed
            signature: Signature to verify
            public_key_path: Path to the public key file
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
            
            # Use the specified public key file
            pubkey_file_path = os.path.abspath(public_key_path)
            
            try:
                # Set up environment for the script
                env = os.environ.copy()
                env['PUBKEY'] = pubkey_file_path
                env['MESSAGE'] = msg_file_path
                env['SIGNATURE'] = sig_file_path
                
                logger.debug("Running verification script", 
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
                
                logger.debug("Verification result", 
                           return_code=result.returncode,
                           stdout=result.stdout.strip(),
                           stderr=result.stderr.strip())
                
                success = result.returncode == 0
                if success:
                    logger.debug("Signature verification successful with key", key_path=public_key_path)
                else:
                    logger.debug("Signature verification failed with key", 
                               key_path=public_key_path,
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
            logger.error("Error during signature verification", error=str(e), key_path=public_key_path)
            return False
    
    def verify_signature(self, data: bytes, signature: bytes, algorithm: str = "sha256") -> Optional[AllowedPublicKey]:
        """
        Verify signature against all allowed public keys.
        
        Args:
            data: Original data that was signed
            signature: Signature to verify
            algorithm: Signature algorithm (currently only sha256 supported)
            
        Returns:
            AllowedPublicKey object if signature is valid, None otherwise
        """
        for allowed_key in self.allowed_keys:
            if self._verify_with_public_key(data, signature, allowed_key.public_key_path, algorithm):
                logger.info("Signature verified successfully", 
                           key_id=allowed_key.id,
                           key_name=allowed_key.name)
                return allowed_key
        
        logger.warning("Signature verification failed against all allowed keys")
        return None
    
    def verify_with_nonce(self, data: bytes, nonce: bytes, signature: bytes, algorithm: str = "sha256") -> Optional[AllowedPublicKey]:
        """
        Verify signature with nonce against all allowed public keys.
        
        Args:
            data: Original data that was signed
            nonce: Nonce that was used in signing
            signature: Signature to verify
            algorithm: Signature algorithm (currently only sha256 supported)
            
        Returns:
            AllowedPublicKey object if signature is valid, None otherwise
        """
        # Combine data and nonce as done in the agent
        combined_data = data + nonce
        return self.verify_signature(combined_data, signature, algorithm)
    
    def verify_with_public_key(self, data: bytes, nonce: bytes, signature: bytes, public_key_data: str, algorithm: str = "sha256") -> bool:
        """
        Verify signature with nonce using provided public key data.
        
        Args:
            data: Original data that was signed
            nonce: Nonce that was used in signing
            signature: Signature to verify
            public_key_data: Public key data (PEM format)
            algorithm: Signature algorithm (currently only sha256 supported)
            
        Returns:
            True if signature is valid, False otherwise
        """
        try:
            # Combine data and nonce as done in the agent
            combined_data = data + nonce
            
            # Create temporary public key file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as temp_key_file:
                temp_key_file.write(public_key_data)
                temp_key_path = temp_key_file.name
            
            try:
                # Create files with expected names in current directory
                script_dir = os.path.dirname(os.path.abspath(self.verify_script_path))
                if not script_dir:
                    script_dir = os.getcwd()
                
                # Create message file with expected name
                msg_file_path = os.path.join(script_dir, "appsig_info.bin")
                with open(msg_file_path, 'wb') as msg_file:
                    msg_file.write(combined_data)
                
                # Create signature file with expected name
                sig_file_path = os.path.join(script_dir, "appsig.bin")
                with open(sig_file_path, 'wb') as sig_file:
                    sig_file.write(signature)
                
                try:
                    # Set up environment for the script
                    env = os.environ.copy()
                    env['PUBKEY'] = temp_key_path
                    env['MESSAGE'] = msg_file_path
                    env['SIGNATURE'] = sig_file_path
                    
                    logger.debug("Running verification script with provided public key", 
                               script_path=self.verify_script_path,
                               script_dir=script_dir,
                               env_pubkey=temp_key_path,
                               env_message=env.get('MESSAGE'),
                               env_signature=env.get('SIGNATURE'))
                    
                    result = subprocess.run(
                        [os.path.abspath(self.verify_script_path)],
                        capture_output=True,
                        text=True,
                        env=env,
                        cwd=script_dir
                    )
                    
                    logger.debug("Verification result", 
                               return_code=result.returncode,
                               stdout=result.stdout.strip(),
                               stderr=result.stderr.strip())
                    
                    success = result.returncode == 0
                    if success:
                        logger.info("Signature verification successful with provided public key")
                    else:
                        logger.warning("Signature verification failed with provided public key", 
                                     return_code=result.returncode,
                                     stderr=result.stderr)
                    
                    return success
                    
                finally:
                    # Clean up files
                    for file_path in [msg_file_path, sig_file_path]:
                        if os.path.exists(file_path):
                            os.unlink(file_path)
                            logger.debug("Cleaned up file", file_path=file_path)
                            
            finally:
                # Clean up temporary public key file
                if os.path.exists(temp_key_path):
                    os.unlink(temp_key_path)
                    logger.debug("Cleaned up temporary public key file", file_path=temp_key_path)
                    
        except Exception as e:
            logger.error("Error during signature verification with provided public key", error=str(e))
            return False
    
    def verify_with_geographic_region(self, data: bytes, signature: bytes, geographic_region: Dict[str, Any], algorithm: str = "sha256") -> Optional[AllowedPublicKey]:
        """
        Verify signature with geographic region constraints.
        
        Args:
            data: Original data that was signed
            signature: Signature to verify
            geographic_region: Geographic region information
            algorithm: Signature algorithm (currently only sha256 supported)
            
        Returns:
            AllowedPublicKey object if signature is valid and region is allowed, None otherwise
        """
        region = geographic_region.get("region")
        
        # First verify signature against all keys
        for allowed_key in self.allowed_keys:
            if self._verify_with_public_key(data, signature, allowed_key.public_key_path, algorithm):
                # Check if region is allowed for this key
                if not allowed_key.allowed_regions or region in allowed_key.allowed_regions:
                    logger.info("Signature verified successfully with region check", 
                               key_id=allowed_key.id,
                               key_name=allowed_key.name,
                               region=region)
                    return allowed_key
                else:
                    logger.warning("Region not allowed for key", 
                                 key_id=allowed_key.id,
                                 region=region,
                                 allowed_regions=allowed_key.allowed_regions)
        
        logger.warning("Signature verification failed or region not allowed")
        return None
    
    def get_allowed_keys(self) -> List[AllowedPublicKey]:
        """Get list of all allowed public keys."""
        return self.allowed_keys.copy()
    
    def add_allowed_key(self, key_data: Dict[str, Any]) -> bool:
        """
        Add a new allowed public key to the allowlist.
        
        Args:
            key_data: Dictionary containing key information
            
        Returns:
            True if added successfully, False otherwise
        """
        try:
            # Load current allowlist
            with open(self.allowlist_file_path, 'r') as f:
                keys_data = json.load(f)
            
            # Add new key
            keys_data.append(key_data)
            
            # Write back to file
            with open(self.allowlist_file_path, 'w') as f:
                json.dump(keys_data, f, indent=2)
            
            # Reload allowed keys
            self._load_allowed_keys()
            
            logger.info("Added new allowed public key", key_id=key_data.get("id"))
            return True
            
        except Exception as e:
            logger.error("Failed to add allowed key", error=str(e))
            return False
    
    def remove_allowed_key(self, key_id: str) -> bool:
        """
        Remove an allowed public key from the allowlist.
        
        Args:
            key_id: ID of the key to remove
            
        Returns:
            True if removed successfully, False otherwise
        """
        try:
            # Load current allowlist
            with open(self.allowlist_file_path, 'r') as f:
                keys_data = json.load(f)
            
            # Remove key with matching ID
            keys_data = [key for key in keys_data if key.get("id") != key_id]
            
            # Write back to file
            with open(self.allowlist_file_path, 'w') as f:
                json.dump(keys_data, f, indent=2)
            
            # Reload allowed keys
            self._load_allowed_keys()
            
            logger.info("Removed allowed public key", key_id=key_id)
            return True
            
        except Exception as e:
            logger.error("Failed to remove allowed key", error=str(e))
            return False
