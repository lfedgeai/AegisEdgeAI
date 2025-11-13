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
        logger.debug(
            "Unified-Identity - Phase 3: Error checking feature flag: %s", e
        )
        return False


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
# Interface: SPIRE TPM Plugin → Keylime Agent
# Status: 🆕 New (Phase 3)
# Transport: JSON over UDS (Phase 3)
# Protocol: JSON REST API
# Port/Path: UDS socket (default: /tmp/keylime-agent.sock)
class DelegatedCertificationClient:
    """
    Client for requesting App Key certificates from rust-keylime Agent.

    This implements the low-privilege side of the delegated certification flow,
    where the SPIRE Agent requests a certificate for its App Key from the
    high-privilege rust-keylime Agent.

    Interface Specification:
    - Transport: JSON over UDS (Phase 3)
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
                "Unified-Identity - Phase 3: Feature flag disabled, delegated certification client will not function"
            )

        if endpoint is None:
            endpoint = "unix:///tmp/keylime-agent.sock"

        if endpoint.startswith("unix://"):
            self.socket_path = endpoint[7:]
        elif endpoint.startswith("/"):
            self.socket_path = endpoint
        else:
            raise ValueError(
                "DelegatedCertificationClient endpoint must be a UNIX domain socket path "
                "(e.g., unix:///tmp/keylime-agent.sock)"
            )

        if not os.path.exists(self.socket_path):
            logger.warning(
                "Unified-Identity - Phase 3: UDS socket path does not exist: %s",
                self.socket_path,
            )

        self.api_path = "/v2.2/delegated_certification/certify_app_key"

        logger.info(
            "Unified-Identity - Phase 3: Delegated Certification Client initialized (rust-keylime agent)"
        )
        logger.info(
            "Unified-Identity - Phase 3: Using UNIX socket: %s", self.socket_path
        )

    def request_certificate(
        self, app_key_public: str, app_key_context_path: str
    ) -> Tuple[bool, Optional[str], Optional[str]]:
        """
        Request App Key certificate from rust-keylime Agent.

        Args:
            app_key_public: PEM-encoded App Key public key
            app_key_context_path: Path to App Key context file

        Returns:
            Tuple of (success, base64_certificate, error_message)
        """
        if not is_unified_identity_enabled():
            logger.error(
                "Unified-Identity - Phase 3: Feature flag disabled, cannot request certificate"
            )
            return (False, None, "Feature flag disabled")

        logger.info(
            "Unified-Identity - Phase 3: Requesting App Key certificate from rust-keylime Agent"
        )

        request = {
            "api_version": "v1",
            "command": "certify_app_key",
            "app_key_public": app_key_public,
            "app_key_context_path": app_key_context_path,
        }

        request_json = json.dumps(request)

        try:
            request_bytes = request_json.encode("utf-8")

            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(10)
            sock.connect(self.socket_path)

            logger.debug(
                "Unified-Identity - Phase 3: Connected to rust-keylime Agent UNIX socket: %s",
                self.socket_path,
            )

            http_request = (
                f"POST {self.api_path} HTTP/1.1\r\n"
                f"Host: localhost\r\n"
                f"Content-Type: application/json\r\n"
                f"Content-Length: {len(request_bytes)}\r\n"
                f"\r\n"
            ).encode("utf-8") + request_bytes

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
                    headers = response_data[:header_end].decode("utf-8")
                    body = response_data[header_end + 4 :]

                    content_length = None
                    for line in headers.split("\r\n"):
                        if line.lower().startswith("content-length:"):
                            content_length = int(line.split(":", 1)[1].strip())
                            break

                    if content_length is not None:
                        while len(body) < content_length:
                            chunk = sock.recv(content_length - len(body))
                            if not chunk:
                                break
                            body += chunk
                        response_json = body[:content_length].decode("utf-8")
                    else:
                        response_json = body.decode("utf-8")
                    break

            sock.close()

            if not response_json:
                logger.error(
                    "Unified-Identity - Phase 3: Empty response from rust-keylime Agent"
                )
                return (False, None, "Empty response")

            response = json.loads(response_json)

            if response.get("result") == "SUCCESS":
                cert_b64 = response.get("app_key_certificate")
                if cert_b64:
                    logger.info(
                        "Unified-Identity - Phase 3: App Key certificate received successfully from rust-keylime agent"
                    )
                    return (True, cert_b64, None)
                logger.error(
                    "Unified-Identity - Phase 3: Certificate missing in response"
                )
                return (False, None, "Certificate missing in response")

            error_msg = response.get("error", "Unknown error")
            logger.error(
                "Unified-Identity - Phase 3: Certificate request failed: %s",
                error_msg,
            )
            return (False, None, error_msg)

        except FileNotFoundError:
            logger.error(
                "Unified-Identity - Phase 3: rust-keylime Agent socket not found: %s",
                self.socket_path,
            )
            return (False, None, f"Socket not found: {self.socket_path}")
        except ConnectionRefusedError:
            logger.error(
                "Unified-Identity - Phase 3: Connection refused to rust-keylime Agent"
            )
            return (False, None, "Connection refused - is rust-keylime agent running?")
        except socket.timeout:
            logger.error(
                "Unified-Identity - Phase 3: Timeout connecting to rust-keylime Agent"
            )
            return (False, None, "Connection timeout")
        except Exception as e:
            logger.error(
                "Unified-Identity - Phase 3: Error communicating with rust-keylime Agent via UDS: %s",
                e,
            )
            return (False, None, f"UDS communication error: {e}")


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
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
            "Unified-Identity - Phase 3: Feature flag disabled, not creating delegated cert client"
        )
        return None

    return DelegatedCertificationClient(endpoint=endpoint)
