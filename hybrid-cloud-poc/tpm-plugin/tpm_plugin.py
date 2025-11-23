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
            app_key_public = f.read()
        
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
    
    def get_app_key_context(self) -> Optional[str]:
        """
        Get the App Key context file path.
        
        Returns:
            Path to App Key context file or None
        """
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        app_ctx_path = self.work_dir / "app.ctx"
        if app_ctx_path.exists():
            return str(app_ctx_path)
        return None


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

