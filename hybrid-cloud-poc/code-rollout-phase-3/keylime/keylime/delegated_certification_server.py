#!/usr/bin/env python3
"""
Unified-Identity - Phase 3: Hardware Integration & Delegated Certification

Keylime Agent Local API Server for Delegated Certification
This module implements the high-privilege side of delegated certification,
providing a UNIX socket server that signs App Key certificates using the AK.
"""

import base64
import json
import logging
import os
import socket
import struct
import subprocess
import tempfile
import threading
from pathlib import Path
from typing import Dict, Optional, Tuple

from keylime import config, keylime_logging

logger = keylime_logging.init_logging("delegated_certification_server")

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
        try:
            return config.getboolean("agent", "unified_identity_enabled", fallback=False)
        except Exception:
            pass
        
        return False
    except Exception as e:
        logger.debug("Unified-Identity - Phase 3: Error checking feature flag: %s", e)
        return False


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
class DelegatedCertificationServer:
    """
    UNIX socket server for handling App Key certification requests.
    
    This server runs as part of the Keylime Agent and provides a secure
    local API for SPIRE Agent to request App Key certificates signed by the AK.
    """
    
    def __init__(self, socket_path: str = "/var/run/keylime/keylime-agent-certify.sock",
                 ak_ctx_path: Optional[str] = None, work_dir: Optional[str] = None):
        """
        Initialize Delegated Certification Server.
        
        Args:
            socket_path: Path to UNIX socket
            ak_ctx_path: Path to AK context file (if None, will use handle)
            work_dir: Working directory for temporary files
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.warning("Unified-Identity - Phase 3: Feature flag disabled, certification server will not start")
            return
        
        self.socket_path = socket_path
        self.ak_ctx_path = ak_ctx_path
        self.work_dir = Path(work_dir) if work_dir else Path(tempfile.mkdtemp(prefix="keylime-cert-"))
        self.work_dir.mkdir(parents=True, exist_ok=True)
        
        # AK handle (default from config or environment)
        self.ak_handle = os.getenv("AK_HANDLE", "0x8101000A")
        
        # TPM device detection
        self.tpm_device = self._detect_tpm_device()
        
        # Server socket
        self.server_socket = None
        self.running = False
        
        logger.info("Unified-Identity - Phase 3: Delegated Certification Server initialized")
        logger.info("Unified-Identity - Phase 3: Socket path: %s", self.socket_path)
        logger.info("Unified-Identity - Phase 3: AK handle: %s", self.ak_handle)
    
    def _detect_tpm_device(self) -> str:
        """Detect available TPM device"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if os.path.exists("/dev/tpmrm0"):
            logger.info("Unified-Identity - Phase 3: Using hardware TPM resource manager: /dev/tpmrm0")
            return "device:/dev/tpmrm0"
        elif os.path.exists("/dev/tpm0"):
            logger.info("Unified-Identity - Phase 3: Using hardware TPM: /dev/tpm0")
            return "device:/dev/tpm0"
        else:
            swtpm_port = os.getenv("SWTPM_PORT", "2321")
            logger.info("Unified-Identity - Phase 3: Using swtpm on port %s", swtpm_port)
            return f"swtpm:host=127.0.0.1,port={swtpm_port}"
    
    def _run_tpm_command(self, cmd: list, check: bool = True) -> Tuple[bool, str, str]:
        """Run a TPM command using tpm2-tools"""
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
            logger.error("Unified-Identity - Phase 3: tpm2-tools not found")
            return (False, "", "tpm2-tools not found")
    
    def _certify_app_key(self, app_key_public: str, app_key_context_data: bytes) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        Certify an App Key using the AK.
        
        Args:
            app_key_public: PEM-encoded App Key public key
            app_key_context_data: App Key context file data
            
        Returns:
            Tuple of (success, base64_certificate, error_message)
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        logger.info("Unified-Identity - Phase 3: Certifying App Key with AK")
        
        # Save App Key context to temporary file
        app_ctx_path = self.work_dir / "app_ctx_temp.ctx"
        with open(app_ctx_path, 'wb') as f:
            f.write(app_key_context_data)
        
        # Determine AK context path
        if self.ak_ctx_path and os.path.exists(self.ak_ctx_path):
            ak_ctx = self.ak_ctx_path
        else:
            # Try to use AK handle directly
            ak_ctx = self.ak_handle
        
        # Output files for certification
        cert_out = self.work_dir / "app_certify.out"
        cert_sig = self.work_dir / "app_certify.sig"
        
        # Flush contexts
        self._run_tpm_command(["tpm2", "flushcontext", "-t"], check=False)
        
        # Run tpm2_certify
        logger.debug("Unified-Identity - Phase 3: Running tpm2_certify")
        success, stdout, stderr = self._run_tpm_command(
            ["tpm2_certify", "-C", ak_ctx, "-c", str(app_ctx_path),
             "-g", "sha256", "-o", str(cert_out), "-s", str(cert_sig)]
        )
        
        if not success:
            logger.error("Unified-Identity - Phase 3: tpm2_certify failed: %s", stderr)
            return (False, None, f"Certification failed: {stderr}")
        
        # Read certification output
        try:
            with open(cert_out, 'rb') as f:
                cert_data = f.read()
            with open(cert_sig, 'rb') as f:
                sig_data = f.read()
            
            # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
            # Create certificate structure compatible with Phase 2
            # Phase 2 expects base64-encoded X.509 certificate (DER or PEM)
            # For now, we create a structure that Phase 2 can parse
            # The certificate contains the certify data and signature from tpm2_certify
            # In production, this would be a proper X.509 certificate
            # For Phase 2 compatibility, we encode the certify data as the certificate body
            cert_structure = {
                "app_key_public": app_key_public,
                "certify_data": base64.b64encode(cert_data).decode('utf-8'),
                "signature": base64.b64encode(sig_data).decode('utf-8'),
                "hash_alg": "sha256",
                "format": "phase2_compatible"
            }
            
            # Encode as base64 for Phase 2 compatibility
            cert_json = json.dumps(cert_structure)
            cert_b64 = base64.b64encode(cert_json.encode('utf-8')).decode('utf-8')
            
            logger.info("Unified-Identity - Phase 3: App Key certified successfully")
            return (True, cert_b64, None)
            
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Failed to read certification output: %s", e)
            return (False, None, f"Failed to read output: {e}")
    
    def _handle_request(self, client_socket: socket.socket, address: str):
        """
        Handle a single client request.
        
        Args:
            client_socket: Client socket
            address: Client address (for logging)
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        logger.debug("Unified-Identity - Phase 3: Handling request from %s", address)
        
        try:
            # Receive request length
            length_bytes = client_socket.recv(4)
            if len(length_bytes) != 4:
                logger.error("Unified-Identity - Phase 3: Failed to receive request length")
                return
            
            request_length = struct.unpack('>I', length_bytes)[0]
            
            # Receive request
            request_bytes = b''
            while len(request_bytes) < request_length:
                chunk = client_socket.recv(request_length - len(request_bytes))
                if not chunk:
                    break
                request_bytes += chunk
            
            if len(request_bytes) != request_length:
                logger.error("Unified-Identity - Phase 3: Incomplete request received")
                return
            
            # Parse request
            request_json = request_bytes.decode('utf-8')
            request = json.loads(request_json)
            
            logger.debug("Unified-Identity - Phase 3: Received request: %s", request.get("command"))
            
            # Process request
            if request.get("command") == "certify_app_key":
                app_key_public = request.get("app_key_public")
                app_key_context_b64 = request.get("app_key_context")
                
                if not app_key_public or not app_key_context_b64:
                    response = {
                        "result": "ERROR",
                        "error": "Missing app_key_public or app_key_context"
                    }
                else:
                    app_key_context_data = base64.b64decode(app_key_context_b64)
                    success, cert_b64, error = self._certify_app_key(app_key_public, app_key_context_data)
                    
                    if success:
                        response = {
                            "result": "SUCCESS",
                            "app_key_certificate": cert_b64
                        }
                    else:
                        response = {
                            "result": "ERROR",
                            "error": error or "Unknown error"
                        }
            else:
                response = {
                    "result": "ERROR",
                    "error": f"Unknown command: {request.get('command')}"
                }
            
            # Send response
            response_json = json.dumps(response)
            response_bytes = response_json.encode('utf-8')
            
            # Send response length
            length = struct.pack('>I', len(response_bytes))
            client_socket.sendall(length)
            
            # Send response
            client_socket.sendall(response_bytes)
            
            logger.debug("Unified-Identity - Phase 3: Response sent to %s", address)
            
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Error handling request: %s", e)
        finally:
            client_socket.close()
    
    def start(self):
        """Start the certification server"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.warning("Unified-Identity - Phase 3: Feature flag disabled, server not started")
            return
        
        # Create socket directory
        socket_dir = os.path.dirname(self.socket_path)
        try:
            os.makedirs(socket_dir, exist_ok=True)
        except PermissionError:
            # Fallback to user-writable directory
            logger.warning("Unified-Identity - Phase 3: Cannot create %s, using user directory", socket_dir)
            user_socket_dir = os.path.expanduser("~/.keylime/run")
            os.makedirs(user_socket_dir, exist_ok=True)
            self.socket_path = os.path.join(user_socket_dir, "keylime-agent-certify.sock")
            socket_dir = user_socket_dir
            logger.info("Unified-Identity - Phase 3: Using socket path: %s", self.socket_path)
        
        # Remove existing socket
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)
        
        # Create UNIX socket
        self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket.bind(self.socket_path)
        self.server_socket.listen(5)
        
        # Set socket permissions (read/write for keylime group)
        os.chmod(self.socket_path, 0o660)
        
        self.running = True
        logger.info("Unified-Identity - Phase 3: Delegated Certification Server started on %s", self.socket_path)
        
        # Accept connections
        while self.running:
            try:
                client_socket, address = self.server_socket.accept()
                # Handle each request in a separate thread
                thread = threading.Thread(
                    target=self._handle_request,
                    args=(client_socket, str(address))
                )
                thread.daemon = True
                thread.start()
            except Exception as e:
                if self.running:
                    logger.error("Unified-Identity - Phase 3: Error accepting connection: %s", e)
    
    def stop(self):
        """Stop the certification server"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        self.running = False
        if self.server_socket:
            self.server_socket.close()
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)
        logger.info("Unified-Identity - Phase 3: Delegated Certification Server stopped")


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
def start_certification_server(socket_path: Optional[str] = None,
                              ak_ctx_path: Optional[str] = None) -> Optional[DelegatedCertificationServer]:
    """
    Start the delegated certification server.
    
    Args:
        socket_path: Path to UNIX socket (optional)
        ak_ctx_path: Path to AK context file (optional)
        
    Returns:
        DelegatedCertificationServer instance or None if feature flag is disabled
    """
    if not is_unified_identity_enabled():
        logger.warning("Unified-Identity - Phase 3: Feature flag disabled, server not started")
        return None
    
    server = DelegatedCertificationServer(
        socket_path=socket_path,
        ak_ctx_path=ak_ctx_path
    )
    
    # Start server in background thread
    server_thread = threading.Thread(target=server.start)
    server_thread.daemon = True
    server_thread.start()
    
    return server

