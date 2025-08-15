"""
TPM2 utilities for signing and verification operations.
Provides Python bindings for TPM2 operations used in the microservice architecture.
"""

import os
import hashlib
import subprocess
import tempfile
import logging
from typing import Tuple, Optional, Dict, Any
from pathlib import Path
import structlog

logger = structlog.get_logger(__name__)


class TPM2Error(Exception):
    """Custom exception for TPM2-related errors."""
    pass


class TPM2Utils:
    """TPM2 utility class for signing and verification operations."""
    
    def __init__(self, app_ctx_path: str = "app.ctx", device: str = "/dev/tpm0", use_swtpm: bool = True):
        """
        Initialize TPM2 utilities.
        
        Args:
            app_ctx_path: Path to the TPM2 application context file
            device: TPM2 device path (ignored when use_swtpm=True)
            use_swtpm: Whether to use software TPM (swtpm)
        """
        self.app_ctx_path = app_ctx_path
        self.device = device
        self.use_swtpm = use_swtpm
        self._validate_tpm2_setup()
    
    def _validate_tpm2_setup(self) -> None:
        """Validate TPM2 setup and required files."""
        if self.use_swtpm:
            # For software TPM, check if swtpm is running and accessible
            try:
                # Check if swtpm is running by testing TPM2 access
                result = subprocess.run(
                    ["tpm2_getcap", "properties-fixed"],
                    capture_output=True,
                    text=True,
                    env=dict(os.environ, TPM2TOOLS_TCTI=settings.tpm2tools_tcti)
                )
                if result.returncode != 0:
                    raise TPM2Error(f"Software TPM not accessible: {result.stderr}")
                
                logger.info("Software TPM (swtpm) is accessible")
            except (subprocess.CalledProcessError, FileNotFoundError) as e:
                raise TPM2Error(f"Software TPM setup failed: {e}")
        else:
            # For hardware TPM, check device file
            if not os.path.exists(self.device):
                raise TPM2Error(f"TPM2 device not found: {self.device}")
        
        if not os.path.exists(self.app_ctx_path):
            raise TPM2Error(f"TPM2 app context not found: {self.app_ctx_path}")
        
        # Check if tpm2 tools are available
        try:
            subprocess.run(["tpm2_hash", "--help"], 
                         capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            raise TPM2Error("TPM2 tools not found. Please install tpm2-tools.")
    
    def _run_tpm2_command(self, command: list, input_data: Optional[bytes] = None) -> Tuple[int, bytes, bytes]:
        """
        Run a TPM2 command and return the result.
        
        Args:
            command: List of command arguments
            input_data: Optional input data for the command
            
        Returns:
            Tuple of (return_code, stdout, stderr)
        """
        try:
            # Set environment for software TPM if needed
            env = os.environ.copy()
            if self.use_swtpm:
                env['TPM2TOOLS_TCTI'] = settings.tpm2tools_tcti
            
            result = subprocess.run(
                command,
                input=input_data,
                capture_output=True,
                check=False,
                env=env
            )
            return result.returncode, result.stdout, result.stderr
        except Exception as e:
            logger.error("Failed to run TPM2 command", command=command, error=str(e))
            raise TPM2Error(f"TPM2 command failed: {e}")
    
    def hash_data(self, data: bytes, algorithm: str = "sha256") -> bytes:
        """
        Hash data using TPM2.
        
        Args:
            data: Data to hash
            algorithm: Hash algorithm (sha256, sha384, sha512)
            
        Returns:
            Hash digest
        """
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            temp_file.write(data)
            temp_file.flush()
            
            command = [
                "tpm2_hash",
                "-C", "o",
                "-g", algorithm,
                "-o", "digest.ticket",
                temp_file.name
            ]
            
            return_code, stdout, stderr = self._run_tpm2_command(command)
            
            if return_code != 0:
                raise TPM2Error(f"TPM2 hash failed: {stderr.decode()}")
            
            # Read the digest
            with open("msg.digest", "rb") as digest_file:
                digest = digest_file.read()
            
            # Cleanup
            os.unlink(temp_file.name)
            if os.path.exists("msg.digest"):
                os.unlink("msg.digest")
            if os.path.exists("digest.ticket"):
                os.unlink("digest.ticket")
            
            return digest
    
    def sign_data(self, data: bytes, algorithm: str = "sha256") -> bytes:
        """
        Sign data using TPM2.
        
        Args:
            data: Data to sign
            algorithm: Signature algorithm (sha256, sha384, sha512)
            
        Returns:
            Signature
        """
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            temp_file.write(data)
            temp_file.flush()
            
            command = [
                "tpm2_sign",
                "-c", self.app_ctx_path,
                "-g", algorithm,
                "-o", "sig.bin",
                temp_file.name
            ]
            
            return_code, stdout, stderr = self._run_tpm2_command(command)
            
            if return_code != 0:
                raise TPM2Error(f"TPM2 sign failed: {stderr.decode()}")
            
            # Read the signature
            with open("sig.bin", "rb") as sig_file:
                signature = sig_file.read()
            
            # Cleanup
            os.unlink(temp_file.name)
            if os.path.exists("sig.bin"):
                os.unlink("sig.bin")
            
            return signature
    
    def verify_signature(self, data: bytes, signature: bytes, algorithm: str = "sha256") -> bool:
        """
        Verify signature using TPM2.
        
        Args:
            data: Original data
            signature: Signature to verify
            algorithm: Signature algorithm (sha256, sha384, sha512)
            
        Returns:
            True if signature is valid, False otherwise
        """
        with tempfile.NamedTemporaryFile(delete=False) as data_file:
            data_file.write(data)
            data_file.flush()
            
        with tempfile.NamedTemporaryFile(delete=False) as sig_file:
            sig_file.write(signature)
            sig_file.flush()
            
        command = [
            "tpm2_verifysignature",
            "-c", self.app_ctx_path,
            "-g", algorithm,
            "-m", data_file.name,
            "-s", sig_file.name
        ]
        
        return_code, stdout, stderr = self._run_tpm2_command(command)
        
        # Cleanup
        os.unlink(data_file.name)
        os.unlink(sig_file.name)
        
        return return_code == 0
    
    def sign_with_nonce(self, data: bytes, nonce: bytes, algorithm: str = "sha256") -> Dict[str, Any]:
        """
        Sign data with a nonce for additional security.
        
        Args:
            data: Data to sign
            nonce: Nonce to include in signature
            algorithm: Signature algorithm
            
        Returns:
            Dictionary containing signature and metadata
        """
        # Combine data and nonce
        combined_data = data + nonce
        
        # Hash the combined data
        digest = self.hash_data(combined_data, algorithm)
        
        # Sign the combined data
        signature = self.sign_data(combined_data, algorithm)
        
        return {
            "signature": signature.hex(),
            "digest": digest.hex(),
            "algorithm": algorithm,
            "data_length": len(data),
            "nonce_length": len(nonce)
        }
    
    def verify_with_nonce(self, data: bytes, nonce: bytes, signature: bytes, 
                         algorithm: str = "sha256") -> bool:
        """
        Verify signature with nonce.
        
        Args:
            data: Original data
            nonce: Nonce used in signature
            signature: Signature to verify
            algorithm: Signature algorithm
            
        Returns:
            True if signature is valid, False otherwise
        """
        # Combine data and nonce
        combined_data = data + nonce
        
        # Verify the signature
        return self.verify_signature(combined_data, signature, algorithm)
