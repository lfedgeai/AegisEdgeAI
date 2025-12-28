#!/usr/bin/env python3
"""
Unified-Identity - Verification: Hardware Integration & Delegated Certification

TPM Plugin for SPIRE Agent
This module provides TPM-based functionality for generating App Keys,
TPM Quotes, and handling delegated certification flows.
"""

import base64
import hashlib
import json
import logging
import os
import socket
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, Optional, Tuple, Union

logger = logging.getLogger(__name__)

# Unified-Identity - Verification: Hardware Integration & Delegated Certification
# Feature flag check
def is_unified_identity_enabled() -> bool:
    """Check if Unified-Identity feature flag is enabled"""
    try:
        # Check environment variable first
        env_flag = os.getenv("UNIFIED_IDENTITY_ENABLED", "false").lower()
        if env_flag in ("true", "1", "yes"):
            return True
        
        # Check config file if available
        config_path = os.getenv("SPIRE_AGENT_CONFIG", "/opt/spire/conf/agent/agent.conf")
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                content = f.read()
                if 'feature_flags = ["Unified-Identity"]' in content or \
                   'feature_flags = [ "Unified-Identity" ]' in content:
                    return True
        return False
    except Exception as e:
        logger.debug("Unified-Identity - Verification: Error checking feature flag: %s", e)
        return False


# Unified-Identity - Verification: Hardware Integration & Delegated Certification
class TPMPlugin:
    """
    TPM Plugin for generating App Keys and TPM Quotes.
    
    This plugin handles:
    - App Key generation in TPM
    - TPM Quote generation with challenge nonce
    - Integration with Keylime Agent for delegated certification
    """
    
    def __init__(self, work_dir: Optional[str] = None, ak_handle: str = "0x8101000A", 
                 app_handle: str = "0x8101000B"):
        """
        Initialize TPM Plugin.
        
        Args:
            work_dir: Working directory for TPM context files (default: temp dir)
            ak_handle: Persistent handle for Attestation Key
            app_handle: Persistent handle for App Key
        """
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.warning("Unified-Identity - Verification: Feature flag disabled, TPM plugin will not function")
        
        self.work_dir = Path(work_dir) if work_dir else Path(tempfile.mkdtemp(prefix="tpm-plugin-"))
        self.work_dir.mkdir(parents=True, exist_ok=True)
        
        self.ak_handle = ak_handle
        self.app_handle = app_handle
        self.hash_alg = "sha256"
        
        # TPM device detection
        self.tpm_device = self._detect_tpm_device()
        
        # Store app key information (generated on startup)
        self._app_key_public = None
        self._app_key_context = None
        
        logger.info("Unified-Identity - Verification: TPM Plugin initialized")
        logger.info("Unified-Identity - Verification: Work directory: %s", self.work_dir)
        logger.info("Unified-Identity - Verification: TPM device: %s", self.tpm_device)
    
    def _detect_tpm_device(self) -> str:
        """
        Detect available TPM device.
        
        Returns:
            TPM device path or swtpm connection string
        """
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        if os.path.exists("/dev/tpmrm0"):
            logger.info("Unified-Identity - Verification: Using hardware TPM resource manager: /dev/tpmrm0")
            return "device:/dev/tpmrm0"
        elif os.path.exists("/dev/tpm0"):
            logger.info("Unified-Identity - Verification: Using hardware TPM: /dev/tpm0")
            return "device:/dev/tpm0"
        else:
            # Fallback to swtpm
            swtpm_port = os.getenv("SWTPM_PORT", "2321")
            logger.info("Unified-Identity - Verification: Using swtpm on port %s", swtpm_port)
            return f"swtpm:host=127.0.0.1,port={swtpm_port}"
    
    def _run_tpm_command(self, cmd: list, check: bool = True) -> Tuple[bool, str, str]:
        """
        Run a TPM command using tpm2-tools.
        
        Args:
            cmd: Command and arguments
            check: Whether to raise exception on failure
            
        Returns:
            Tuple of (success, stdout, stderr)
        """
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        env = os.environ.copy()
        env["TPM2TOOLS_TCTI"] = self.tpm_device
        
        logger.debug("Unified-Identity - Verification: Running TPM command: %s", " ".join(cmd))
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                env=env,
                check=check
            )
            return (result.returncode == 0, result.stdout, result.stderr)
        except subprocess.CalledProcessError as e:
            logger.error("Unified-Identity - Verification: TPM command failed: %s", e)
            return (False, e.stdout, e.stderr)
        except FileNotFoundError:
            logger.error("Unified-Identity - Verification: tpm2-tools not found. Please install tpm2-tools.")
            return (False, "", "tpm2-tools not found")
    
    def _normalize_pcr_selection(self, pcr_list: Union[str, list]) -> str:
        """Normalize PCR selection input for tpm2_quote."""
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        if isinstance(pcr_list, list):
            entries = []
            for p in pcr_list:
                try:
                    entries.append(str(int(p)))
                except (ValueError, TypeError):
                    raise ValueError(f"Invalid PCR value: {p}") from None
            selection = ",".join(entries)
        else:
            selection = str(pcr_list).strip()

        if not selection:
            selection = "0"

        if ":" not in selection:
            selection = f"{self.hash_alg}:{selection}"

        return selection

    def generate_app_key(self, force: bool = False) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        Generate or retrieve an App Key in the TPM.
        
        Args:
            force: Force regeneration even if key exists
            
        Returns:
            Tuple of (success, app_key_public_pem, app_key_context_path)
        """
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.error("Unified-Identity - Verification: Feature flag disabled, cannot generate App Key")
            return (False, None, None)
        
        logger.info("Unified-Identity - Verification: Generating App Key at handle %s", self.app_handle)
        
        app_ctx_path = self.work_dir / "app.ctx"
        app_pub_path = self.work_dir / "app_pub.pem"
        
        # Check if App Key already exists
        if not force:
            success, _, _ = self._run_tpm_command(
                ["tpm2_readpublic", "-c", self.app_handle],
                check=False
            )
            if success:
                logger.info("Unified-Identity - Verification: App Key already exists, exporting public key")
                success, stdout, stderr = self._run_tpm_command(
                    ["tpm2_readpublic", "-c", self.app_handle, "-f", "pem", "-o", str(app_pub_path)]
                )
                if success and app_pub_path.exists():
                    with open(app_pub_path, 'r') as f:
                        app_key_public = f.read()
                    # Store for later retrieval
                    self._app_key_public = app_key_public
                    # Use handle if context file doesn't exist (key is persisted)
                    if app_ctx_path.exists():
                        self._app_key_context = str(app_ctx_path)
                    else:
                        self._app_key_context = self.app_handle
                    logger.info("Unified-Identity - Verification: App Key public key exported successfully")
                    return (True, app_key_public, self._app_key_context)
                else:
                    logger.warning("Unified-Identity - Verification: Failed to export existing App Key public key")
        
        # Flush contexts
        self._run_tpm_command(["tpm2", "flushcontext", "-t"], check=False)
        
        # Create primary key
        primary_ctx = self.work_dir / "primary.ctx"
        logger.debug("Unified-Identity - Verification: Creating primary key")
        success, _, _ = self._run_tpm_command(
            ["tpm2_createprimary", "-C", "o", "-G", "rsa", "-c", str(primary_ctx)]
        )
        if not success:
            logger.error("Unified-Identity - Verification: Failed to create primary key")
            return (False, None, None)
        
        # Create App Key under primary
        app_pub_file = self.work_dir / "app.pub"
        app_priv_file = self.work_dir / "app.priv"
        logger.debug("Unified-Identity - Verification: Creating App Key")
        success, _, _ = self._run_tpm_command(
            ["tpm2_create", "-C", str(primary_ctx), "-G", "rsa", 
             "-u", str(app_pub_file), "-r", str(app_priv_file)]
        )
        if not success:
            logger.error("Unified-Identity - Verification: Failed to create App Key")
            return (False, None, None)
        
        # Flush transients before loading
        self._run_tpm_command(["tpm2", "flushcontext", "-t"], check=False)
        
        # Load App Key
        logger.debug("Unified-Identity - Verification: Loading App Key")
        success, _, _ = self._run_tpm_command(
            ["tpm2_load", "-C", str(primary_ctx), "-u", str(app_pub_file),
             "-r", str(app_priv_file), "-c", str(app_ctx_path)]
        )
        if not success:
            logger.error("Unified-Identity - Verification: Failed to load App Key")
            return (False, None, None)
        
        # Persist App Key
        logger.debug("Unified-Identity - Verification: Persisting App Key at handle %s", self.app_handle)
        success, _, _ = self._run_tpm_command(
            ["tpm2_evictcontrol", "-C", "o", "-c", str(app_ctx_path), self.app_handle]
        )
        if not success:
            logger.error("Unified-Identity - Verification: Failed to persist App Key")
            return (False, None, None)
        
        # After persistence, we can use the handle directly, but keep context file for delegated certification
        # The context file is still needed for operations that require loading the key
        # Export public key using persistent handle (more reliable after persistence)
        logger.debug("Unified-Identity - Verification: Exporting App Key public key from persistent handle")
        success, _, _ = self._run_tpm_command(
            ["tpm2_readpublic", "-c", self.app_handle, "-f", "pem", "-o", str(app_pub_path)]
        )
        if not success:
            # Fallback: try using context file
            logger.debug("Unified-Identity - Verification: Fallback: Exporting from context file")
            success, _, _ = self._run_tpm_command(
                ["tpm2_readpublic", "-c", str(app_ctx_path), "-f", "pem", "-o", str(app_pub_path)]
            )
            if not success:
                logger.error("Unified-Identity - Verification: Failed to export App Key public key")
                return (False, None, None)
        
        with open(app_pub_path, 'r') as f:
            app_key_public = f.read().strip()
        
        # Store for later retrieval
        self._app_key_public = app_key_public
        
        # After persistence, the context file may not exist anymore
        # The rust-keylime agent can handle both context files and persistent handles
        # If context file exists, use it; otherwise, use the persistent handle
        if app_ctx_path.exists():
            self._app_key_context = str(app_ctx_path)
            logger.debug("Unified-Identity - Verification: Using context file for delegated certification: %s", app_ctx_path)
        else:
            # Context file doesn't exist (key is persisted), use handle instead
            # rust-keylime agent's load_app_key_from_context will handle the handle format
            self._app_key_context = self.app_handle
            logger.debug("Unified-Identity - Verification: Context file not found, using persistent handle %s for delegated certification", self.app_handle)
        
        logger.info("Unified-Identity - Verification: App Key generated and persisted successfully")
        return (True, app_key_public, self._app_key_context)
    
    def get_app_key_public(self) -> Optional[str]:
        """
        Get the stored App Key public key.
        
        Returns:
            PEM-encoded public key or None if not generated
        """
        if self._app_key_public:
            return self._app_key_public
        
        # Try to read from file if not in memory
        app_pub_path = self.work_dir / "app_pub.pem"
        if app_pub_path.exists():
            try:
                with open(app_pub_path, 'r') as f:
                    self._app_key_public = f.read()
                return self._app_key_public
            except Exception as e:
                logger.warning("Unified-Identity - Verification: Failed to read app key public: %s", e)
        
        return None
    
    def get_app_key_context(self) -> Optional[str]:
        """
        Get the stored App Key context path or persistent handle.
        
        Returns:
            Path to app key context file, or persistent handle (0x8101000B) if context file doesn't exist.
            The rust-keylime agent can handle both formats.
        """
        try:
            # First, check if _app_key_context is already set
            if self._app_key_context:
                # If it's a handle (starts with 0x), return it directly
                if isinstance(self._app_key_context, str) and self._app_key_context.startswith("0x"):
                    logger.info("Unified-Identity - Verification: get_app_key_context() returning persistent handle: %s", self._app_key_context)
                    return self._app_key_context
                # If it's a file path, check if it exists
                if isinstance(self._app_key_context, str) and os.path.exists(self._app_key_context):
                    logger.info("Unified-Identity - Verification: get_app_key_context() returning context file: %s", self._app_key_context)
                    return self._app_key_context
                # If it's a string but file doesn't exist, assume it's a handle or use default handle
                if isinstance(self._app_key_context, str):
                    logger.warning("Unified-Identity - Verification: _app_key_context is set but file doesn't exist: %s, using handle %s", 
                                 self._app_key_context, self.app_handle)
                    self._app_key_context = self.app_handle
                    return self.app_handle
        except Exception as e:
            logger.error("Unified-Identity - Verification: Exception in get_app_key_context(): %s", e, exc_info=True)
            # Fall through to check handle
        
        # Check if context file exists
        app_ctx_path = self.work_dir / "app.ctx"
        if app_ctx_path.exists():
            self._app_key_context = str(app_ctx_path)
            logger.debug("Unified-Identity - Verification: Found context file, returning: %s", self._app_key_context)
            return self._app_key_context
        
        # If context file doesn't exist but key was persisted, use handle
        # Check if key exists at persistent handle
        logger.debug("Unified-Identity - Verification: Checking if App Key exists at persistent handle %s", self.app_handle)
        try:
            result = subprocess.run(
                ["tpm2_readpublic", "-c", self.app_handle],
                capture_output=True,
                timeout=5,
                check=False
            )
            if result.returncode == 0:
                logger.debug("Unified-Identity - Verification: App Key found at persistent handle %s", self.app_handle)
                self._app_key_context = self.app_handle
                return self.app_handle
            else:
                logger.warning("Unified-Identity - Verification: App Key not found at persistent handle %s (exit code: %d)", 
                             self.app_handle, result.returncode)
        except Exception as e:
            logger.warning("Unified-Identity - Verification: Could not verify persistent handle: %s", e)
        
        logger.warning("Unified-Identity - Verification: get_app_key_context() returning None - no context file or handle found")
        return None
    
    def sign_data(self, data: bytes, hash_alg: str = "sha256", is_digest: bool = False, scheme: str = "rsassa", salt_length: int = -1) -> Tuple[bool, Optional[bytes], Optional[str]]:
        """
        Sign data using the TPM App Key.
        
        Args:
            data: Data to sign (raw data or digest, depending on is_digest)
            hash_alg: Hash algorithm to use (default: sha256)
            is_digest: If True, data is already a digest and should not be hashed again
            scheme: Signature scheme to use - "rsassa" for PKCS#1 v1.5 (default) or "rsapss" for RSA-PSS
            salt_length: Salt length for RSA-PSS (-1 for default, which is hash length)
            
        Returns:
            Tuple of (success, signature_bytes, error_message)
        """
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.error("Unified-Identity - Verification: Feature flag disabled, cannot sign data")
            return (False, None, "Feature flag disabled")
        
        app_key_context = self.get_app_key_context()
        if not app_key_context:
            logger.error("Unified-Identity - Verification: App Key context unavailable for signing")
            return (False, None, "App Key context unavailable")
        
        logger.debug("Unified-Identity - Verification: Signing data using App Key at context %s (is_digest=%s)", app_key_context, is_digest)
        
        # Create temporary files for data, hash, and signature
        data_file = self.work_dir / "sign_data.tmp"
        hash_file = self.work_dir / "sign_data.hash"
        sig_file = self.work_dir / "sign_data.sig"
        
        try:
            # Write data to file (for debugging, but we'll use hash_file for signing)
            with open(data_file, 'wb') as f:
                f.write(data)
            
            # Determine if we need to hash the data
            if is_digest:
                # Data is already a digest, use it directly
                digest_bytes = data
                logger.debug("Unified-Identity - Verification: Using provided data as digest (length: %d)", len(digest_bytes))
            else:
                # Hash the data first using hashlib
                # Reference: sign_app_message.sh uses openssl dgst -sha256 -binary
                import hashlib
                hash_obj = hashlib.new(hash_alg)
                hash_obj.update(data)
                digest_bytes = hash_obj.digest()
                logger.debug("Unified-Identity - Verification: Hashed data to digest (length: %d)", len(digest_bytes))
            
            # Write digest to file
            with open(hash_file, 'wb') as f:
                f.write(digest_bytes)
            
            # Sign the hash using the App Key
            # Reference: sign_app_message.sh uses: tpm2_sign -c "$KEY_CTX" -g sha256 --scheme rsassa -d "$DIGEST" -f plain -o "$SIGNATURE"
            # For RSA keys, tpm2_sign supports:
            #   --scheme rsassa: PKCS#1 v1.5 (default, backward compatible)
            #   --scheme rsapss: RSA-PSS (for TLS 1.3 and modern TLS 1.2)
            # For RSA-PSS, salt length is typically set to the hash length (e.g., 32 for SHA256)
            # If salt_length is -1, use default (hash length for RSA-PSS, ignored for RSASSA)
            scheme_arg = scheme  # "rsassa" or "rsapss"
            tpm_cmd = ["tpm2_sign", "-c", app_key_context, "-g", hash_alg, "--scheme", scheme_arg, 
                      "-d", str(hash_file), "-f", "plain", "-o", str(sig_file)]
            
            # For RSA-PSS, add salt length if specified (some TPM implementations require it)
            if scheme == "rsapss" and salt_length >= 0:
                # tpm2_sign doesn't directly support salt length parameter in the command line
                # The salt length is typically determined by the hash algorithm
                # For SHA256, salt length is 32 bytes (256 bits / 8)
                # For SHA384, salt length is 48 bytes (384 bits / 8)
                # For SHA512, salt length is 64 bytes (512 bits / 8)
                # TPM 2.0 typically uses salt length equal to hash length (PSS standard)
                logger.debug("Unified-Identity - Verification: RSA-PSS signing with scheme=%s, hash_alg=%s, salt_length=%d", 
                            scheme_arg, hash_alg, salt_length)
            else:
                logger.debug("Unified-Identity - Verification: Signing with scheme=%s, hash_alg=%s", scheme_arg, hash_alg)
            
            success, stdout, stderr = self._run_tpm_command(tpm_cmd)
            if not success:
                logger.error("Unified-Identity - Verification: Failed to sign data: %s", stderr)
                return (False, None, f"Failed to sign data: {stderr}")
            
            # Read the signature file
            if not sig_file.exists():
                logger.error("Unified-Identity - Verification: Signature file not created")
                return (False, None, "Signature file not created")
            
            with open(sig_file, 'rb') as f:
                signature_bytes = f.read()
            
            logger.debug("Unified-Identity - Verification: Raw signature from tpm2_sign, length: %d bytes", len(signature_bytes))
            
            # Check if signature has a TPM header (6 bytes: sig_alg + hash_alg + sig_size)
            # tpm2_sign -f plain should return raw bytes, but some versions might include header
            # For RSA signatures, the header format is:
            # - sig_alg (2 bytes, big-endian): 0x0014 for TPM_ALG_RSASSA
            # - hash_alg (2 bytes, big-endian): 0x000B for TPM_ALG_SHA256
            # - sig_size (2 bytes, big-endian): size of signature data
            if len(signature_bytes) >= 6:
                import struct
                try:
                    sig_alg = struct.unpack('>H', signature_bytes[0:2])[0]
                    hash_alg = struct.unpack('>H', signature_bytes[2:4])[0]
                    sig_size = struct.unpack('>H', signature_bytes[4:6])[0]
                    
                    logger.debug("Unified-Identity - Verification: Signature header check: sig_alg=0x%04x, hash_alg=0x%04x, sig_size=%d, total_len=%d", 
                                sig_alg, hash_alg, sig_size, len(signature_bytes))
                    
                    # Check if this looks like a TPM signature header
                    # 0x0014 = TPM_ALG_RSASSA, 0x000B = TPM_ALG_SHA256
                    if sig_alg == 0x0014 and hash_alg == 0x000B and sig_size > 0:
                        # Verify the total size matches
                        if len(signature_bytes) == 6 + sig_size:
                            # Strip the header and use only the signature bytes
                            signature_bytes = signature_bytes[6:]
                            logger.info("Unified-Identity - Verification: Stripped TPM signature header (6 bytes), raw signature length: %d", len(signature_bytes))
                        else:
                            logger.warning("Unified-Identity - Verification: TPM header found but size mismatch (expected %d, got %d), using raw bytes", 6 + sig_size, len(signature_bytes))
                    # If it doesn't match the expected header format, assume it's already raw
                except Exception as e:
                    logger.debug("Unified-Identity - Verification: Could not parse signature header (assuming raw): %s", e)
            
            # Log first few bytes for debugging
            if len(signature_bytes) >= 16:
                logger.debug("Unified-Identity - Verification: Signature first 16 bytes (hex): %s", signature_bytes[:16].hex())
            
            # Verify the signature using Python's cryptography library (same method Go uses)
            # This helps catch format issues early before Go tries to verify
            try:
                from cryptography.hazmat.primitives.asymmetric import rsa, padding
                from cryptography.hazmat.primitives.asymmetric.utils import Prehashed
                from cryptography.hazmat.backends import default_backend
                from cryptography.hazmat.primitives import serialization, hashes
                
                # Get the App Key public key
                app_key_public_pem = self.get_app_key_public()
                if app_key_public_pem:
                    public_key = serialization.load_pem_public_key(app_key_public_pem.encode(), backend=default_backend())
                    
                    # Verify using the same method Go uses: VerifyPKCS1v15
                    # Go's checkSignature does: rsa.VerifyPKCS1v15(pub, hashType, signed, signature)
                    # where 'signed' is the original data (not digest), and it hashes internally
                    # But we're signing a digest, so we use Prehashed
                    hash_alg_obj = hashes.SHA256()
                    if hash_alg == "sha384":
                        hash_alg_obj = hashes.SHA384()
                    elif hash_alg == "sha512":
                        hash_alg_obj = hashes.SHA512()
                    
                    # Verify signature against digest (what we signed)
                    # Use the same padding scheme as was used for signing
                    if scheme == "rsapss":
                        # RSA-PSS verification
                        # Salt length for PSS is typically equal to hash length
                        # SHA256 = 32 bytes, SHA384 = 48 bytes, SHA512 = 64 bytes
                        salt_len = len(digest_bytes)  # Default to hash length
                        if salt_length >= 0:
                            salt_len = salt_length
                        public_key.verify(
                            signature_bytes,
                            digest_bytes,  # The digest we signed
                            padding.PSS(
                                mgf=padding.MGF1(hash_alg_obj),
                                salt_length=salt_len
                            ),
                            Prehashed(hash_alg_obj)
                        )
                        logger.info("Unified-Identity - Verification: Python RSA-PSS verification SUCCESSFUL (Go-compatible method)")
                    else:
                        # PKCS#1 v1.5 verification (default)
                        # This matches Go's rsa.VerifyPKCS1v15(pub, hashFunc, digest, signature)
                        public_key.verify(
                            signature_bytes,
                            digest_bytes,  # The digest we signed
                            padding.PKCS1v15(),
                            Prehashed(hash_alg_obj)
                        )
                        logger.info("Unified-Identity - Verification: Python PKCS#1 v1.5 verification SUCCESSFUL (Go-compatible method)")
                else:
                    logger.warning("Unified-Identity - Verification: Could not get App Key public key for verification")
            except Exception as verify_err:
                logger.error("Unified-Identity - Verification: Python verification FAILED (Go-compatible method): %s", verify_err)
                logger.error("Unified-Identity - Verification: This signature will likely fail Go's verification too")
                # Continue anyway - let Go's verification provide the final error message
                # But log the issue for debugging
            
            logger.debug("Unified-Identity - Verification: Data signed successfully, final signature length: %d", len(signature_bytes))
            return (True, signature_bytes, None)
            
        except Exception as e:
            logger.error("Unified-Identity - Verification: Exception during signing: %s", e, exc_info=True)
            return (False, None, f"Exception during signing: {str(e)}")
    
    def verify_signature(self, data: bytes, signature: bytes, hash_alg: str = "sha256", is_digest: bool = False) -> Tuple[bool, Optional[str]]:
        """
        Verify a signature using the TPM App Key public key.
        
        Args:
            data: Data that was signed (raw data or digest, depending on is_digest)
            signature: Signature bytes to verify
            hash_alg: Hash algorithm used (default: sha256)
            is_digest: If True, data is already a digest and should not be hashed again
            
        Returns:
            Tuple of (success, error_message)
        """
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.error("Unified-Identity - Verification: Feature flag disabled, cannot verify signature")
            return (False, "Feature flag disabled")
        
        try:
            from cryptography.hazmat.primitives.asymmetric import rsa, padding
            from cryptography.hazmat.primitives.asymmetric.utils import Prehashed
            from cryptography.hazmat.backends import default_backend
            from cryptography.hazmat.primitives import serialization, hashes
            import hashlib
            
            # Get the App Key public key
            app_key_public_pem = self.get_app_key_public()
            if not app_key_public_pem:
                return (False, "App Key public key unavailable")
            
            public_key = serialization.load_pem_public_key(app_key_public_pem.encode(), backend=default_backend())
            
            if not isinstance(public_key, rsa.RSAPublicKey):
                return (False, "App Key is not RSA")
            
            # Determine if we need to hash the data
            if is_digest:
                # Data is already a digest, use it directly
                digest_bytes = data
                logger.debug("Unified-Identity - Verification: Using provided data as digest (length: %d)", len(digest_bytes))
            else:
                # Hash the data first
                hash_obj = hashlib.new(hash_alg)
                hash_obj.update(data)
                digest_bytes = hash_obj.digest()
                logger.debug("Unified-Identity - Verification: Hashed data to digest (length: %d)", len(digest_bytes))
            
            # Get hash algorithm object
            hash_alg_obj = hashes.SHA256()
            if hash_alg == "sha384":
                hash_alg_obj = hashes.SHA384()
            elif hash_alg == "sha512":
                hash_alg_obj = hashes.SHA512()
            
            # Verify signature against digest (what we signed)
            # Try PKCS#1 v1.5 first (most common), then RSA-PSS if that fails
            # This allows verification of signatures created with either scheme
            try:
                # Try PKCS#1 v1.5 first (default)
                public_key.verify(
                    signature,
                    digest_bytes,  # The digest we signed
                    padding.PKCS1v15(),
                    Prehashed(hash_alg_obj)
                )
                logger.info("Unified-Identity - Verification: TPM plugin verification SUCCESSFUL (PKCS#1 v1.5)")
                return (True, None)
            except Exception as pkcs_err:
                # If PKCS#1 v1.5 fails, try RSA-PSS
                logger.debug("Unified-Identity - Verification: PKCS#1 v1.5 verification failed, trying RSA-PSS: %s", pkcs_err)
                try:
                    # For RSA-PSS, salt length is typically equal to hash length
                    salt_len = len(digest_bytes)  # Default to hash length
                    public_key.verify(
                        signature,
                        digest_bytes,  # The digest we signed
                        padding.PSS(
                            mgf=padding.MGF1(hash_alg_obj),
                            salt_length=salt_len
                        ),
                        Prehashed(hash_alg_obj)
                    )
                    logger.info("Unified-Identity - Verification: TPM plugin verification SUCCESSFUL (RSA-PSS)")
                    return (True, None)
                except Exception as pss_err:
                    logger.error("Unified-Identity - Verification: TPM plugin verification FAILED (both PKCS#1 v1.5 and RSA-PSS): PKCS#1 v1.5 error: %s, RSA-PSS error: %s", pkcs_err, pss_err)
                    return (False, f"Verification failed: {str(pss_err)}")
                
        except Exception as e:
            logger.error("Unified-Identity - Verification: Exception during verification: %s", e, exc_info=True)
            return (False, f"Exception during verification: {str(e)}")


# Unified-Identity - Verification: Hardware Integration & Delegated Certification
def create_tpm_plugin(work_dir: Optional[str] = None) -> Optional[TPMPlugin]:
    """
    Factory function to create a TPM Plugin instance.
    
    Args:
        work_dir: Working directory for TPM context files
        
    Returns:
        TPMPlugin instance or None if feature flag is disabled
    """
    if not is_unified_identity_enabled():
        logger.warning("Unified-Identity - Verification: Feature flag disabled, TPM plugin not created")
        return None
    
    return TPMPlugin(work_dir=work_dir)

