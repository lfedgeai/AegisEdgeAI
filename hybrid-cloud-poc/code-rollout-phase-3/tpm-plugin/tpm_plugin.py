#!/usr/bin/env python3
"""
Unified-Identity - Phase 3: Hardware Integration & Delegated Certification

TPM Plugin for SPIRE Agent
This module provides TPM-based functionality for generating App Keys,
TPM Quotes, and handling delegated certification flows.
"""

import base64
import hashlib
import json
import logging
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, Optional, Tuple, Union

logger = logging.getLogger(__name__)

# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
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
        logger.debug("Unified-Identity - Phase 3: Error checking feature flag: %s", e)
        return False


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
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
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.warning("Unified-Identity - Phase 3: Feature flag disabled, TPM plugin will not function")
        
        self.work_dir = Path(work_dir) if work_dir else Path(tempfile.mkdtemp(prefix="tpm-plugin-"))
        self.work_dir.mkdir(parents=True, exist_ok=True)
        
        self.ak_handle = ak_handle
        self.app_handle = app_handle
        self.hash_alg = "sha256"
        
        # TPM device detection
        self.tpm_device = self._detect_tpm_device()
        
        logger.info("Unified-Identity - Phase 3: TPM Plugin initialized")
        logger.info("Unified-Identity - Phase 3: Work directory: %s", self.work_dir)
        logger.info("Unified-Identity - Phase 3: TPM device: %s", self.tpm_device)
    
    def _detect_tpm_device(self) -> str:
        """
        Detect available TPM device.
        
        Returns:
            TPM device path or swtpm connection string
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if os.path.exists("/dev/tpmrm0"):
            logger.info("Unified-Identity - Phase 3: Using hardware TPM resource manager: /dev/tpmrm0")
            return "device:/dev/tpmrm0"
        elif os.path.exists("/dev/tpm0"):
            logger.info("Unified-Identity - Phase 3: Using hardware TPM: /dev/tpm0")
            return "device:/dev/tpm0"
        else:
            # Fallback to swtpm
            swtpm_port = os.getenv("SWTPM_PORT", "2321")
            logger.info("Unified-Identity - Phase 3: Using swtpm on port %s", swtpm_port)
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
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        env = os.environ.copy()
        env["TPM2TOOLS_TCTI"] = self.tpm_device
        
        logger.debug("Unified-Identity - Phase 3: Running TPM command: %s", " ".join(cmd))
        
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
            logger.error("Unified-Identity - Phase 3: TPM command failed: %s", e)
            return (False, e.stdout, e.stderr)
        except FileNotFoundError:
            logger.error("Unified-Identity - Phase 3: tpm2-tools not found. Please install tpm2-tools.")
            return (False, "", "tpm2-tools not found")
    
    def _normalize_pcr_selection(self, pcr_list: Union[str, list]) -> str:
        """Normalize PCR selection input for tpm2_quote."""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
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
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.error("Unified-Identity - Phase 3: Feature flag disabled, cannot generate App Key")
            return (False, None, None)
        
        logger.info("Unified-Identity - Phase 3: Generating App Key at handle %s", self.app_handle)
        
        app_ctx_path = self.work_dir / "app.ctx"
        app_pub_path = self.work_dir / "app_pub.pem"
        
        # Check if App Key already exists
        if not force:
            success, _, _ = self._run_tpm_command(
                ["tpm2_readpublic", "-c", self.app_handle],
                check=False
            )
            if success:
                logger.info("Unified-Identity - Phase 3: App Key already exists, exporting public key")
                success, stdout, stderr = self._run_tpm_command(
                    ["tpm2_readpublic", "-c", self.app_handle, "-f", "pem", "-o", str(app_pub_path)]
                )
                if success and app_pub_path.exists():
                    with open(app_pub_path, 'r') as f:
                        app_key_public = f.read()
                    logger.info("Unified-Identity - Phase 3: App Key public key exported successfully")
                    return (True, app_key_public, str(app_ctx_path))
                else:
                    logger.warning("Unified-Identity - Phase 3: Failed to export existing App Key public key")
        
        # Flush contexts
        self._run_tpm_command(["tpm2", "flushcontext", "-t"], check=False)
        
        # Create primary key
        primary_ctx = self.work_dir / "primary.ctx"
        logger.debug("Unified-Identity - Phase 3: Creating primary key")
        success, _, _ = self._run_tpm_command(
            ["tpm2_createprimary", "-C", "o", "-G", "rsa", "-c", str(primary_ctx)]
        )
        if not success:
            logger.error("Unified-Identity - Phase 3: Failed to create primary key")
            return (False, None, None)
        
        # Create App Key under primary
        app_pub_file = self.work_dir / "app.pub"
        app_priv_file = self.work_dir / "app.priv"
        logger.debug("Unified-Identity - Phase 3: Creating App Key")
        success, _, _ = self._run_tpm_command(
            ["tpm2_create", "-C", str(primary_ctx), "-G", "rsa", 
             "-u", str(app_pub_file), "-r", str(app_priv_file)]
        )
        if not success:
            logger.error("Unified-Identity - Phase 3: Failed to create App Key")
            return (False, None, None)
        
        # Flush transients before loading
        self._run_tpm_command(["tpm2", "flushcontext", "-t"], check=False)
        
        # Load App Key
        logger.debug("Unified-Identity - Phase 3: Loading App Key")
        success, _, _ = self._run_tpm_command(
            ["tpm2_load", "-C", str(primary_ctx), "-u", str(app_pub_file),
             "-r", str(app_priv_file), "-c", str(app_ctx_path)]
        )
        if not success:
            logger.error("Unified-Identity - Phase 3: Failed to load App Key")
            return (False, None, None)
        
        # Persist App Key
        logger.debug("Unified-Identity - Phase 3: Persisting App Key at handle %s", self.app_handle)
        success, _, _ = self._run_tpm_command(
            ["tpm2_evictcontrol", "-C", "o", "-c", str(app_ctx_path), self.app_handle]
        )
        if not success:
            logger.error("Unified-Identity - Phase 3: Failed to persist App Key")
            return (False, None, None)
        
        # Export public key
        logger.debug("Unified-Identity - Phase 3: Exporting App Key public key")
        success, _, _ = self._run_tpm_command(
            ["tpm2_readpublic", "-c", str(app_ctx_path), "-f", "pem", "-o", str(app_pub_path)]
        )
        if not success:
            logger.error("Unified-Identity - Phase 3: Failed to export App Key public key")
            return (False, None, None)
        
        with open(app_pub_path, 'r') as f:
            app_key_public = f.read()
        
        logger.info("Unified-Identity - Phase 3: App Key generated and persisted successfully")
        return (True, app_key_public, str(app_ctx_path))
    
    def generate_quote(self, nonce: str, pcr_list: Union[str, list] = "sha256:0,1") -> Tuple[bool, Optional[str], Optional[Dict]]:
        """
        Generate a TPM Quote using the App Key.
        
        Args:
            nonce: Challenge nonce from SPIRE Server
            pcr_list: PCR selection (default: sha256:0,1)
            
        Returns:
            Tuple of (success, base64_encoded_quote, quote_metadata)
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.error("Unified-Identity - Phase 3: Feature flag disabled, cannot generate quote")
            return (False, None, None)
        
        logger.info("Unified-Identity - Phase 3: Generating TPM Quote with nonce")
        
        # Validate nonce
        if not nonce or len(nonce) < 16:
            logger.error("Unified-Identity - Phase 3: Invalid nonce provided")
            return (False, None, None)
        
        # Convert nonce to hex if needed
        if len(nonce) % 2 == 0 and all(c in '0123456789abcdefABCDEF' for c in nonce):
            nonce_hex = nonce
        else:
            nonce_hex = nonce.encode('utf-8').hex()
        
        quote_msg = self.work_dir / "quote.msg"
        quote_sig = self.work_dir / "quote.sig"
        quote_pcrs = self.work_dir / "quote.pcrs"
        
        # Flush contexts
        self._run_tpm_command(["tpm2", "flushcontext", "-t"], check=False)
        
        # Generate quote using App Key
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        # Ensure pcr_list is a string (handle both string and list inputs)
        logger.debug("Unified-Identity - Phase 3: Generating quote with App Key at handle %s", self.app_handle)
        try:
            pcr_selection = self._normalize_pcr_selection(pcr_list)
        except ValueError as exc:
            logger.error("Unified-Identity - Phase 3: Invalid PCR selection: %s", exc)
            return (False, None, None)

        success, stdout, stderr = self._run_tpm_command(
            ["tpm2_quote", "-c", self.app_handle, "-l", pcr_selection,
             "-m", str(quote_msg), "-s", str(quote_sig), "-o", str(quote_pcrs),
             "-q", nonce_hex, "-g", "sha256"]
        )
        
        if not success:
            logger.error("Unified-Identity - Phase 3: Failed to generate quote: %s", stderr)
            return (False, None, None)
        
        # Read quote files and encode
        try:
            with open(quote_msg, 'rb') as f:
                quote_msg_data = f.read()
            with open(quote_sig, 'rb') as f:
                quote_sig_data = f.read()
            with open(quote_pcrs, 'rb') as f:
                quote_pcrs_data = f.read()
            
            # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
            # Format quote for Phase 2 compatibility
            # Phase 2 expects format: rTPM_QUOTE:TPM_SIG:TPM_PCRS
            # Where each component is base64-encoded
            quote_msg_b64 = base64.b64encode(quote_msg_data).decode('utf-8')
            quote_sig_b64 = base64.b64encode(quote_sig_data).decode('utf-8')
            quote_pcrs_b64 = base64.b64encode(quote_pcrs_data).decode('utf-8')
            
            # Combine in Phase 2 expected format: r<message>:<signature>:<pcrs>
            quote_formatted = f"r{quote_msg_b64}:{quote_sig_b64}:{quote_pcrs_b64}"
            
            metadata = {
                "nonce": nonce,
                "pcr_list": pcr_list,
                "hash_alg": "sha256",
                "format": "phase2_compatible"
            }
            
            logger.info("Unified-Identity - Phase 3: TPM Quote generated successfully (Phase 2 compatible format)")
            return (True, quote_formatted, metadata)
            
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Failed to encode quote: %s", e)
            return (False, None, None)
    
    def get_app_key_context(self) -> Optional[str]:
        """
        Get the App Key context file path.
        
        Returns:
            Path to App Key context file or None
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        app_ctx_path = self.work_dir / "app.ctx"
        if app_ctx_path.exists():
            return str(app_ctx_path)
        return None


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
def create_tpm_plugin(work_dir: Optional[str] = None) -> Optional[TPMPlugin]:
    """
    Factory function to create a TPM Plugin instance.
    
    Args:
        work_dir: Working directory for TPM context files
        
    Returns:
        TPMPlugin instance or None if feature flag is disabled
    """
    if not is_unified_identity_enabled():
        logger.warning("Unified-Identity - Phase 3: Feature flag disabled, TPM plugin not created")
        return None
    
    return TPMPlugin(work_dir=work_dir)

