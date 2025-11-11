#!/usr/bin/env python3
"""
Unified-Identity - Phase 3: Hardware Integration & Delegated Certification

Delegated Certification Client
This module handles the low-privilege side of delegated certification,
communicating with the rust-keylime Agent to obtain App Key certificates.
"""

import base64
import json
import logging
import os
import socket
import struct
import urllib.error
import urllib.request
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
# Feature flag check
def is_unified_identity_enabled() -> bool:
    """Check if Unified-Identity feature flag is enabled."""
    try:
        env_value = os.getenv("UNIFIED_IDENTITY_ENABLED", "false").lower()
        return env_value in ("true", "1", "yes")
    except Exception as e:
        logger.debug("Unified-Identity - Phase 3: Error checking feature flag: %s", e)
        return False


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
class DelegatedCertificationClient:
    """
    Client for requesting App Key certificates from rust-keylime Agent.
    
    This implements the low-privilege side of the delegated certification flow,
    where the SPIRE Agent requests a certificate for its App Key from the
    high-privilege rust-keylime Agent.
    """
    
    def __init__(self, endpoint: str = None):
        """
        Initialize Delegated Certification Client.
        
        Args:
            endpoint: rust-keylime Agent HTTP endpoint or UNIX socket path.
                     Defaults to HTTP endpoint on localhost:9002 if None.
                     For UNIX socket, use format: unix:///path/to/socket
                     For HTTP, use format: http://localhost:9002
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.warning("Unified-Identity - Phase 3: Feature flag disabled, delegated certification client will not function")
        
        # Default to rust-keylime agent HTTP endpoint
        if endpoint is None:
            # rust-keylime agent typically runs on port 9002
            self.endpoint = "http://localhost:9002/v2.2/delegated_certification/certify_app_key"
            self.use_unix_socket = False
            self.socket_path = None
        elif endpoint.startswith("unix://"):
            self.socket_path = endpoint[7:]  # Remove "unix://" prefix
            self.endpoint = None
            self.use_unix_socket = True
        elif endpoint.startswith("http://") or endpoint.startswith("https://"):
            # If full URL provided, use as-is, otherwise append path
            if "/delegated_certification" in endpoint:
                self.endpoint = endpoint
            else:
                self.endpoint = f"{endpoint}/v2.2/delegated_certification/certify_app_key"
            self.socket_path = None
            self.use_unix_socket = False
        else:
            # Legacy: treat as UNIX socket path
            self.socket_path = endpoint
            self.endpoint = None
            self.use_unix_socket = True
        
        logger.info("Unified-Identity - Phase 3: Delegated Certification Client initialized (rust-keylime agent)")
        if self.use_unix_socket:
            logger.info("Unified-Identity - Phase 3: Using UNIX socket: %s", self.socket_path)
        else:
            logger.info("Unified-Identity - Phase 3: Using HTTP endpoint: %s", self.endpoint)
    
    def request_certificate(self, app_key_public: str, app_key_context_path: str) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        Request App Key certificate from rust-keylime Agent.
        
        Args:
            app_key_public: PEM-encoded App Key public key
            app_key_context_path: Path to App Key context file
            
        Returns:
            Tuple of (success, base64_certificate, error_message)
        """
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if not is_unified_identity_enabled():
            logger.error("Unified-Identity - Phase 3: Feature flag disabled, cannot request certificate")
            return (False, None, "Feature flag disabled")
        
        logger.info("Unified-Identity - Phase 3: Requesting App Key certificate from rust-keylime Agent")
        
        # Prepare request (matching rust-keylime agent API format)
        request = {
            "api_version": "v1",
            "command": "certify_app_key",
            "app_key_public": app_key_public,
            "app_key_context_path": app_key_context_path  # rust-keylime agent will load from this path
        }
        
        request_json = json.dumps(request)
        
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        # Communicate with rust-keylime agent (HTTP or UNIX socket)
        try:
            if self.use_unix_socket:
                # UNIX socket communication (legacy or explicit)
                request_bytes = request_json.encode('utf-8')
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(10)
                sock.connect(self.socket_path)
                
                logger.debug("Unified-Identity - Phase 3: Connected to rust-keylime Agent UNIX socket")
                
                # Send request length (4 bytes, network byte order)
                length = struct.pack('>I', len(request_bytes))
                sock.sendall(length)
                sock.sendall(request_bytes)
                
                # Receive response
                length_bytes = sock.recv(4)
                if len(length_bytes) != 4:
                    sock.close()
                    return (False, None, "Failed to receive response length")
                
                response_length = struct.unpack('>I', length_bytes)[0]
                response_bytes = b''
                while len(response_bytes) < response_length:
                    chunk = sock.recv(response_length - len(response_bytes))
                    if not chunk:
                        break
                    response_bytes += chunk
                
                sock.close()
                
                if len(response_bytes) != response_length:
                    return (False, None, "Incomplete response")
                
                response_json = response_bytes.decode('utf-8')
            else:
                # HTTP communication with rust-keylime agent
                logger.debug("Unified-Identity - Phase 3: Sending HTTP request to rust-keylime Agent: %s", self.endpoint)
                
                req = urllib.request.Request(
                    self.endpoint,
                    data=request_json.encode('utf-8'),
                    headers={'Content-Type': 'application/json'}
                )
                
                with urllib.request.urlopen(req, timeout=10) as f:
                    response_json = f.read().decode('utf-8')
            
            # Parse response
            response = json.loads(response_json)
            
            if response.get("result") == "SUCCESS":
                cert_b64 = response.get("app_key_certificate")
                if cert_b64:
                    logger.info("Unified-Identity - Phase 3: App Key certificate received successfully from rust-keylime agent")
                    return (True, cert_b64, None)
                else:
                    logger.error("Unified-Identity - Phase 3: Certificate missing in response")
                    return (False, None, "Certificate missing in response")
            else:
                error_msg = response.get("error", "Unknown error")
                logger.error("Unified-Identity - Phase 3: Certificate request failed: %s", error_msg)
                return (False, None, error_msg)
                
        except FileNotFoundError:
            logger.error("Unified-Identity - Phase 3: rust-keylime Agent socket not found: %s", getattr(self, 'socket_path', 'N/A'))
            return (False, None, f"Socket not found: {getattr(self, 'socket_path', 'N/A')}")
        except ConnectionRefusedError:
            logger.error("Unified-Identity - Phase 3: Connection refused to rust-keylime Agent")
            return (False, None, "Connection refused - is rust-keylime agent running?")
        except socket.timeout:
            logger.error("Unified-Identity - Phase 3: Timeout connecting to rust-keylime Agent")
            return (False, None, "Connection timeout")
        except urllib.error.URLError as e:
            logger.error("Unified-Identity - Phase 3: HTTP error communicating with rust-keylime Agent: %s", e)
            return (False, None, f"HTTP error: {e}")
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Error communicating with rust-keylime Agent: %s", e)
            return (False, None, f"Communication error: {e}")


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
def create_delegated_cert_client(endpoint: Optional[str] = None) -> Optional[DelegatedCertificationClient]:
    """
    Create a DelegatedCertificationClient if feature flag is enabled.
    
    Args:
        endpoint: Optional endpoint (HTTP URL or unix://socket path)
        
    Returns:
        DelegatedCertificationClient instance or None if feature flag disabled
    """
    if not is_unified_identity_enabled():
        logger.debug("Unified-Identity - Phase 3: Feature flag disabled, not creating delegated cert client")
        return None
    
    return DelegatedCertificationClient(endpoint=endpoint)
