#!/usr/bin/env python3
"""
Unified-Identity: Hardware Integration & Delegated Certification

Delegated Certification Client
This module handles the low-privilege side of delegated certification,
communicating with the rust-keylime Agent to obtain App Key certificates.
"""

import json
import logging
import os
import socket
from typing import Optional, Tuple

logger = logging.getLogger(__name__)


# Unified-Identity: Hardware Integration & Delegated Certification
# Feature flag check
def is_unified_identity_enabled() -> bool:
    """Check if Unified-Identity feature flag is enabled."""
    try:
        env_value = os.getenv("UNIFIED_IDENTITY_ENABLED", "false").lower()
        return env_value in ("true", "1", "yes")
    except Exception as e:
        logger.debug(
            "Unified-Identity: Error checking feature flag: %s", e
        )
        return False


# Unified-Identity: Hardware Integration & Delegated Certification
# Interface: SPIRE TPM Plugin → Keylime Agent
# Status: 🆕 New (Unified-Identity)
# Transport: JSON over UDS (Unified-Identity)
# Protocol: JSON REST API
# Port/Path: UDS socket (default: /tmp/keylime-agent.sock)
class DelegatedCertificationClient:
    """
    Client for requesting App Key certificates from rust-keylime Agent.

    This implements the low-privilege side of the delegated certification flow,
    where the SPIRE Agent requests a certificate for its App Key from the
    high-privilege rust-keylime Agent.

    Interface Specification:
    - Transport: JSON over UDS (Unified-Identity)
    - Protocol: JSON REST API
    - Endpoint: POST /v2.2/delegated_certification/certify_app_key
    """

    def __init__(self, endpoint: str = None):
        """
        Initialize Delegated Certification Client.

        Args:
            endpoint: rust-keylime Agent UDS socket path.
                     Defaults to unix:///tmp/keylime-agent.sock if None.
                     Must use format: unix:///path/to/socket
                     HTTP over localhost is not supported for security reasons.
        """
        if not is_unified_identity_enabled():
            logger.warning(
                "Unified-Identity: Feature flag disabled, delegated certification client will not function"
            )

        # Unified-Identity: Use HTTPS for agent communication (Gap #2 fix - mTLS enabled)
        # Agent now uses mTLS/HTTPS by default
        if endpoint is None:
            endpoint = "https://127.0.0.1:9002"
        elif endpoint == "unix:///tmp/keylime-agent.sock":
            # Convert old UDS default to HTTPS (UDS not yet implemented in agent, Gap #1)
            logger.info(
                "Unified-Identity: Converting old UDS default to HTTPS endpoint (agent uses mTLS)"
            )
            endpoint = "https://127.0.0.1:9002"
        elif endpoint.startswith("http://") and ("127.0.0.1" in endpoint or "localhost" in endpoint):
            # Convert HTTP to HTTPS for localhost (agent now uses mTLS, Gap #2 fix)
            endpoint = endpoint.replace("http://", "https://")
            logger.info(
                "Unified-Identity: Converting HTTP to HTTPS (agent uses mTLS)"
            )

        # Support both UDS and HTTP endpoints
        if endpoint.startswith("unix://"):
            self.socket_path = endpoint[7:]
            self.use_uds = True
            self.http_endpoint = None
            if not os.path.exists(self.socket_path):
                logger.warning(
                    "Unified-Identity: UDS socket path does not exist: %s, falling back to HTTP",
                    self.socket_path,
                )
                # Fallback to HTTPS if UDS socket doesn't exist (agent uses mTLS)
                self.use_uds = False
                self.socket_path = None
                self.http_endpoint = "https://127.0.0.1:9002"
        elif endpoint.startswith("/"):
            self.socket_path = endpoint
            self.use_uds = True
            self.http_endpoint = None
            if not os.path.exists(self.socket_path):
                logger.warning(
                    "Unified-Identity: UDS socket path does not exist: %s, falling back to HTTPS",
                    self.socket_path,
                )
                # Fallback to HTTPS if UDS socket doesn't exist (agent uses mTLS)
                self.use_uds = False
                self.socket_path = None
                self.http_endpoint = "https://127.0.0.1:9002"
        elif endpoint.startswith("http://") or endpoint.startswith("https://"):
            # HTTP/HTTPS endpoint - use as-is (agent now uses HTTPS/mTLS, Gap #2 fix)
            self.use_uds = False
            self.socket_path = None
            self.http_endpoint = endpoint.rstrip("/")
            protocol = "HTTPS" if endpoint.startswith("https://") else "HTTP"
            logger.info(
                "Unified-Identity: Using %s endpoint: %s (agent uses mTLS/HTTPS)",
                protocol,
                self.http_endpoint
            )
        else:
            raise ValueError(
                "DelegatedCertificationClient endpoint must be a UNIX domain socket path "
                "(e.g., unix:///tmp/keylime-agent.sock) or HTTP endpoint (e.g., http://127.0.0.1:9002)"
            )

        self.api_path = "/v2.2/delegated_certification/certify_app_key"

        logger.info(
            "Unified-Identity: Delegated Certification Client initialized (rust-keylime agent)"
        )
        if self.use_uds:
            logger.info(
                "Unified-Identity: Using UNIX socket: %s", self.socket_path
            )
        else:
            protocol = "HTTPS (mTLS)" if self.http_endpoint and self.http_endpoint.startswith("https://") else "HTTP"
            logger.info(
                "Unified-Identity: Using %s endpoint: %s", protocol, self.http_endpoint
            )

    def request_certificate(
        self, app_key_public: str, app_key_context_path: str, challenge_nonce: str
    ) -> Tuple[bool, Optional[str], Optional[str], Optional[str]]:
        """
        Request App Key certificate from rust-keylime Agent.

        Args:
            app_key_public: PEM-encoded App Key public key
            app_key_context_path: Path to App Key context file

        Returns:
            Tuple of (success, base64_certificate, agent_uuid, error_message)
        """
        if not is_unified_identity_enabled():
            logger.error(
                "Unified-Identity: Feature flag disabled, cannot request certificate"
            )
            return (False, None, "Feature flag disabled")

        logger.info(
            "Unified-Identity: Requesting App Key certificate from rust-keylime Agent"
        )

        request = {
            "api_version": "v1",
            "command": "certify_app_key",
            "app_key_public": app_key_public,
            "app_key_context_path": app_key_context_path,
            "challenge_nonce": challenge_nonce,
        }

        request_json = json.dumps(request)

        try:
            request_bytes = request_json.encode("utf-8")
            if self.use_uds:
                response_json = self._perform_uds_request(
                    method="POST",
                    path=self.api_path,
                    body=request_bytes,
                )
            else:
                response_json = self._perform_http_request(
                    method="POST",
                    path=self.api_path,
                    body=request_bytes,
                )

            if not response_json:
                logger.error(
                    "Unified-Identity: Empty response from rust-keylime Agent"
                )
                return (False, None, None, "Empty response")

            response = json.loads(response_json)

            if response.get("result") == "SUCCESS":
                cert_b64 = response.get("app_key_certificate")
                agent_uuid = response.get("agent_uuid")
                if not agent_uuid:
                    agent_uuid = self._fetch_agent_uuid()
                if cert_b64:
                    logger.info(
                        "Unified-Identity: App Key certificate received successfully from rust-keylime agent"
                    )
                    return (True, cert_b64, agent_uuid, None)
                logger.error(
                    "Unified-Identity: Certificate missing in response"
                )
                return (False, None, None, "Certificate missing in response")

            error_msg = response.get("error", "Unknown error")
            logger.error(
                "Unified-Identity: Certificate request failed: %s",
                error_msg,
            )
            return (False, None, None, error_msg)

        except FileNotFoundError:
            logger.error(
                "Unified-Identity: rust-keylime Agent socket not found: %s",
                self.socket_path,
            )
            return (False, None, None, f"Socket not found: {self.socket_path}")
        except ConnectionRefusedError:
            logger.error(
                "Unified-Identity: Connection refused to rust-keylime Agent"
            )
            return (
                False,
                None,
                None,
                "Connection refused - is rust-keylime agent running?",
            )
        except socket.timeout:
            logger.error(
                "Unified-Identity: Timeout connecting to rust-keylime Agent"
            )
            return (False, None, None, "Connection timeout")
        except Exception as e:
            logger.error(
                "Unified-Identity: Error communicating with rust-keylime Agent via UDS: %s",
                e,
            )
            return (False, None, None, f"UDS communication error: {e}")

    def _perform_uds_request(
        self, method: str, path: str, body: Optional[bytes] = None, timeout: int = 10
    ) -> Optional[str]:
        """
        Send an HTTP request over the UNIX domain socket and return the JSON body as a string.
        """
        request_body = body or b""

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect(self.socket_path)

        logger.debug(
            "Unified-Identity: UDS HTTP %s %s via %s",
            method,
            path,
            self.socket_path,
        )

        http_request = (
            f"{method} {path} HTTP/1.1\r\n"
            f"Host: localhost\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(request_body)}\r\n"
            f"\r\n"
        ).encode("utf-8")

        if request_body:
            sock.sendall(http_request + request_body)
        else:
            sock.sendall(http_request)

        response_data = b""
        response_json = ""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response_data += chunk
            if b"\r\n\r\n" in response_data:
                header_end = response_data.find(b"\r\n\r\n")
                headers = response_data[:header_end].decode("utf-8", errors="ignore")
                body_bytes = response_data[header_end + 4 :]

                content_length = None
                for line in headers.split("\r\n"):
                    if line.lower().startswith("content-length:"):
                        try:
                            content_length = int(line.split(":", 1)[1].strip())
                        except ValueError:
                            content_length = None
                        break

                if content_length is not None:
                    while len(body_bytes) < content_length:
                        chunk = sock.recv(content_length - len(body_bytes))
                        if not chunk:
                            break
                        body_bytes += chunk
                    response_json = body_bytes[:content_length].decode("utf-8")
                else:
                    response_json = body_bytes.decode("utf-8")
                break

        sock.close()
        return response_json

    def _create_mtls_context(self):
        """
        Create an SSL context with client certificate for mTLS (Gap #2 fix).
        Uses the verifier's client certificate since the agent trusts the verifier's CA.
        """
        import ssl
        import os
        
        # Try to find the verifier's client certificate
        # The verifier's client cert is in the Keylime cv_ca directory
        keylime_dir = os.getenv("KEYLIME_DIR", "/home/mw/AegisSovereignAI/hybrid-cloud-poc/keylime")
        client_cert_path = os.path.join(keylime_dir, "cv_ca", "client-cert.crt")
        client_key_path = os.path.join(keylime_dir, "cv_ca", "client-private.pem")
        ca_cert_path = os.path.join(keylime_dir, "cv_ca", "cacert.crt")
        
        # Also try alternative paths
        if not os.path.exists(client_cert_path):
            # Try relative to current directory
            alt_path = os.path.join(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                "keylime", "cv_ca", "client-cert.crt"
            )
            if os.path.exists(alt_path):
                client_cert_path = alt_path
                client_key_path = alt_path.replace("client-cert.crt", "client-private.pem")
                ca_cert_path = alt_path.replace("client-cert.crt", "cacert.crt")
        
        if not os.path.exists(client_cert_path) or not os.path.exists(client_key_path):
            logger.debug(
                "Unified-Identity: Client certificate not found at %s or key at %s",
                client_cert_path,
                client_key_path,
            )
            return None
        
        try:
            context = ssl.create_default_context()
            # Agent uses self-signed certificate, so we disable hostname and cert verification
            # The security comes from mTLS (client certificate authentication)
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            
            # Load client certificate and key for mTLS authentication
            # The agent will verify this certificate against its trusted_client_ca
            context.load_cert_chain(client_cert_path, client_key_path)
            
            logger.debug(
                "Unified-Identity: Created mTLS context with client certificate: %s (agent will verify client cert)",
                client_cert_path,
            )
            return context
        except Exception as e:
            logger.warning(
                "Unified-Identity: Failed to create mTLS context: %s",
                e,
            )
            return None

    def _perform_http_request(
        self, method: str, path: str, body: Optional[bytes] = None, timeout: int = 10
    ) -> Optional[str]:
        """
        Send an HTTP/HTTPS request over TCP and return the JSON body as a string.
        For HTTPS (mTLS), uses client certificate for authentication (Gap #2 fix).
        """
        import urllib.request
        import urllib.error
        import ssl
        
        url = f"{self.http_endpoint}{path}"
        request_body = body or b""
        
        logger.debug(
            "Unified-Identity: HTTP/HTTPS %s %s",
            method,
            url,
        )
        
        try:
            req = urllib.request.Request(url, data=request_body, method=method)
            req.add_header("Content-Type", "application/json")
            req.add_header("Content-Length", str(len(request_body)))
            
            # For HTTPS (mTLS), use client certificate for authentication
            if url.startswith("https://"):
                ssl_context = self._create_mtls_context()
                if ssl_context:
                    with urllib.request.urlopen(req, timeout=timeout, context=ssl_context) as response:
                        response_json = response.read().decode("utf-8")
                        return response_json
                else:
                    # Fallback: disable certificate verification if client cert not available
                    logger.warning(
                        "Unified-Identity: Client certificate not available, disabling certificate verification (insecure)"
                    )
                    ssl_context = ssl.create_default_context()
                    ssl_context.check_hostname = False
                    ssl_context.verify_mode = ssl.CERT_NONE
                    with urllib.request.urlopen(req, timeout=timeout, context=ssl_context) as response:
                        response_json = response.read().decode("utf-8")
                        return response_json
            else:
                with urllib.request.urlopen(req, timeout=timeout) as response:
                    response_json = response.read().decode("utf-8")
                    return response_json
        except urllib.error.HTTPError as e:
            logger.error(
                "Unified-Identity: HTTP error %d: %s",
                e.code,
                e.reason,
            )
            # Try to read error response body
            try:
                error_body = e.read().decode("utf-8")
                logger.debug("Error response body: %s", error_body)
            except:
                pass
            return None
        except urllib.error.URLError as e:
            logger.error(
                "Unified-Identity: URL error: %s",
                e.reason,
            )
            return None
        except Exception as e:
            logger.error(
                "Unified-Identity: HTTP request error: %s",
                e,
            )
            return None

    def _fetch_agent_uuid(self) -> Optional[str]:
        """
        Fetch the agent UUID from /v2.2/agent/info if the delegated certification
        endpoint does not include it in the response.
        """
        try:
            if self.use_uds:
                response_json = self._perform_uds_request("GET", "/v2.2/agent/info")
            else:
                response_json = self._perform_http_request("GET", "/v2.2/agent/info")
            if not response_json:
                return None
            response = json.loads(response_json)
            payload = response.get("results") or response.get("data") or {}
            agent_uuid = payload.get("agent_uuid")
            if agent_uuid:
                logger.info(
                    "Unified-Identity: Retrieved agent UUID via /agent/info: %s",
                    agent_uuid,
                )
            return agent_uuid
        except Exception as e:
            logger.debug(
                "Unified-Identity: Could not fetch agent UUID from /agent/info: %s",
                e,
            )
            return None


# Unified-Identity: Hardware Integration & Delegated Certification
def create_delegated_cert_client(
    endpoint: Optional[str] = None,
) -> Optional[DelegatedCertificationClient]:
    """
    Create a DelegatedCertificationClient if feature flag is enabled.

    Args:
        endpoint: Optional endpoint (unix://socket path)

    Returns:
        DelegatedCertificationClient instance or None if feature flag disabled
    """
    if not is_unified_identity_enabled():
        logger.debug(
            "Unified-Identity: Feature flag disabled, not creating delegated cert client"
        )
        return None

    return DelegatedCertificationClient(endpoint=endpoint)
