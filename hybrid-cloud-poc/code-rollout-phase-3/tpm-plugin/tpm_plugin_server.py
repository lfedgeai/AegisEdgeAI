#!/usr/bin/env python3
"""
Unified-Identity - Phase 3: Hardware Integration & Delegated Certification

TPM Plugin HTTP/UDS Server
This module provides an HTTP/UDS server for the TPM plugin,
allowing SPIRE Agent to communicate via JSON over HTTP/UDS instead of subprocess execution.

Interface: SPIRE Agent → SPIRE TPM Plugin
Status: 🆕 New (Phase 3)
Transport: JSON over HTTP/UDS (Phase 3)
Protocol: JSON REST API
Port/Path: UDS socket (default: /tmp/spire-data/tpm-plugin/tpm-plugin.sock) or localhost HTTP
"""

import json
import logging
import os
import socket
import sys
import socketserver
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse, parse_qs

from tpm_plugin import TPMPlugin, is_unified_identity_enabled
from delegated_certification import DelegatedCertificationClient

logger = logging.getLogger(__name__)


class TPMPluginHTTPHandler(BaseHTTPRequestHandler):
    """HTTP request handler for TPM Plugin API"""
    
    def __init__(self, *args, work_dir: str = None, plugin: TPMPlugin = None, **kwargs):
        self.work_dir = work_dir or "/tmp/spire-data/tpm-plugin"
        self.plugin = plugin  # Store plugin instance with app key already generated
        super().__init__(*args, **kwargs)
    
    def address_string(self):
        """Override to handle UDS addresses properly"""
        # For UDS, client_address might be empty or a string
        if isinstance(self.client_address, tuple) and len(self.client_address) > 0:
            return str(self.client_address[0])
        elif isinstance(self.client_address, str):
            return self.client_address
        else:
            return "uds-client"
    
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info("%s - %s", self.address_string(), format % args)
    
    def do_POST(self):
        """Handle POST requests"""
        if not is_unified_identity_enabled():
            self.send_error(403, "Unified-Identity - Phase 3: Feature flag disabled")
            return
        
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            request_data = json.loads(body.decode('utf-8'))
        except (ValueError, json.JSONDecodeError) as e:
            self.send_error(400, f"Invalid JSON: {e}")
            return
        
        # Route to appropriate handler
        path = urlparse(self.path).path
        
        if path == "/get-app-key":
            self.handle_get_app_key(request_data)
        elif path == "/request-certificate":
            self.handle_request_certificate(request_data)
        else:
            self.send_error(404, f"Unknown endpoint: {path}")
    
    def handle_get_app_key(self, request_data: dict):
        """Handle /get-app-key endpoint - returns App Key public key and context"""
        try:
            plugin = self.plugin
            if plugin is None:
                self.send_error(500, "Unified-Identity - Phase 3: Plugin not initialized")
                return
            
            app_key_public = plugin.get_app_key_public()
            
            if not app_key_public:
                self.send_error(500, "Unified-Identity - Phase 3: App Key not generated")
                return
            
            response = {
                "status": "success",
                "app_key_public": app_key_public
            }
            
            self.send_json_response(200, response)
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Error getting App Key: %s", e)
            self.send_error(500, f"Internal error: {e}")
    
    def handle_request_certificate(self, request_data: dict):
        """Handle /request-certificate endpoint"""
        try:
            app_key_public = request_data.get("app_key_public")
            challenge_nonce = request_data.get("challenge_nonce")
            endpoint = request_data.get("endpoint")
            
            if not app_key_public or not challenge_nonce:
                self.send_error(400, "Unified-Identity - Phase 3: app_key_public and challenge_nonce are required")
                return
            
            app_key_context_path = None
            plugin = self.plugin
            if plugin is not None:
                app_key_context_path = plugin.get_app_key_context()
            if not app_key_context_path:
                self.send_error(500, "Unified-Identity - Phase 3: App Key context unavailable")
                return
            
            # Default to HTTP endpoint if not provided or if it's the old UDS default
            if not endpoint or endpoint == "unix:///tmp/keylime-agent.sock":
                endpoint = "http://127.0.0.1:9002"
                logger.info("Unified-Identity - Phase 3: Using default HTTP endpoint: %s", endpoint)
            elif endpoint.startswith("https://"):
                # Convert HTTPS to HTTP for simplicity
                endpoint = endpoint.replace("https://", "http://")
                logger.info("Unified-Identity - Phase 3: Converting HTTPS to HTTP endpoint: %s", endpoint)
            
            client = DelegatedCertificationClient(endpoint=endpoint)
            success, cert_b64, agent_uuid, error = client.request_certificate(
                app_key_public=app_key_public,
                app_key_context_path=app_key_context_path,
                challenge_nonce=challenge_nonce
            )
            
            if not success:
                self.send_error(500, f"Unified-Identity - Phase 3: Failed to request certificate: {error}")
                return
            
            response = {
                "status": "success",
                "app_key_certificate": cert_b64
            }
            if agent_uuid:
                response["agent_uuid"] = agent_uuid
            
            self.send_json_response(200, response)
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Error requesting certificate: %s", e)
            self.send_error(500, f"Internal error: {e}")
    
    def send_json_response(self, status_code: int, data: dict):
        """Send JSON response"""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        response_body = json.dumps(data).encode('utf-8')
        self.wfile.write(response_body)
        self.wfile.flush()  # Ensure response is sent immediately
    
    def do_GET(self):
        """Handle GET requests (health check)"""
        if self.path == "/health":
            self.send_json_response(200, {"status": "ok"})
        else:
            self.send_error(404, "Not found")


class UnixHTTPServer(HTTPServer):
    """HTTP Server that works with UNIX domain sockets"""
    
    def __init__(self, server_address, RequestHandlerClass, bind_and_activate=True):
        # If server_address is a string, treat it as a UDS path
        if isinstance(server_address, str):
            self.socket_path = server_address
            # Remove socket file if it exists
            if os.path.exists(self.socket_path):
                os.unlink(self.socket_path)
            
            # Create a dummy address for HTTPServer (but don't let it bind/activate)
            HTTPServer.__init__(self, ("localhost", 0), RequestHandlerClass, bind_and_activate=False)
            
            # Manually set up UDS socket
            if bind_and_activate:
                self.server_bind()
                self.server_activate()
        else:
            self.socket_path = None
            HTTPServer.__init__(self, server_address, RequestHandlerClass, bind_and_activate=bind_and_activate)
    
    def server_bind(self):
        if self.socket_path:
            # Create UDS socket
            self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.socket.bind(self.socket_path)
            # Set socket permissions (read/write for owner and group)
            os.chmod(self.socket_path, 0o660)
            # IMPORTANT: Call listen() immediately after bind() for UDS sockets
            self.socket.listen(5)
            logger.info("Unified-Identity - Phase 3: UDS socket bound and listening: %s", self.socket_path)
        else:
            HTTPServer.server_bind(self)
    
    def server_activate(self):
        """Override to handle UDS sockets - socket is already listening from server_bind()"""
        if self.socket_path:
            # For UDS, listen() was already called in server_bind()
            # Verify socket is ready
            if self.socket and self.socket.fileno() >= 0:
                logger.debug("Unified-Identity - Phase 3: UDS socket activated and ready for connections")
            else:
                logger.error("Unified-Identity - Phase 3: UDS socket not properly initialized")
        else:
            # For regular TCP sockets, use default behavior
            HTTPServer.server_activate(self)
    
    def get_request(self):
        """Override to handle UDS connections properly"""
        if self.socket_path:
            # For UDS, accept connection and return it with a dummy address
            # BaseHTTPRequestHandler expects (request, (host, port)) tuple
            conn, addr = self.socket.accept()
            # Return connection and dummy address tuple for UDS
            return conn, ("uds-client", 0)
        else:
            # For TCP, use default behavior
            return HTTPServer.get_request(self)
    
    def server_close(self):
        HTTPServer.server_close(self)
        if self.socket_path and os.path.exists(self.socket_path):
            os.unlink(self.socket_path)


def create_handler_class(work_dir: str, plugin: TPMPlugin):
    """Create a handler class with work_dir and plugin instance bound"""
    class Handler(TPMPluginHTTPHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, work_dir=work_dir, plugin=plugin, **kwargs)
    return Handler


def run_server(socket_path: Optional[str] = None, http_port: Optional[int] = None, work_dir: str = None):
    """
    Run the TPM Plugin UDS server
    
    Args:
        socket_path: UNIX domain socket path (e.g., /tmp/spire-data/tpm-plugin/tpm-plugin.sock)
        http_port: Deprecated - not supported for security reasons. Use UDS only.
        work_dir: Working directory for TPM operations
    """
    if not is_unified_identity_enabled():
        logger.error("Unified-Identity - Phase 3: Feature flag disabled, server will not start")
        sys.exit(1)
    
    if work_dir is None:
        work_dir = os.getenv("TPM_PLUGIN_WORK_DIR", "/tmp/spire-data/tpm-plugin")
    
    # Ensure work directory exists
    os.makedirs(work_dir, mode=0o755, exist_ok=True)
    
    # Generate App Key on startup (Step 3: Automatic on Startup)
    logger.info("Unified-Identity - Phase 3: Generating App Key on startup...")
    plugin = TPMPlugin(work_dir=work_dir)
    success, app_key_public, app_key_ctx = plugin.generate_app_key(force=False)
    
    if not success:
        logger.error("Unified-Identity - Phase 3: Failed to generate App Key on startup")
        sys.exit(1)
    
    logger.info("Unified-Identity - Phase 3: App Key generated successfully on startup")
    logger.info("Unified-Identity - Phase 3: App Key context: %s", app_key_ctx)
    
    HandlerClass = create_handler_class(work_dir, plugin)
    
    if socket_path:
        # Use UNIX domain socket
        socket_path = os.path.abspath(socket_path)
        logger.info("Unified-Identity - Phase 3: Starting TPM Plugin server on UDS: %s", socket_path)
        server = UnixHTTPServer(socket_path, HandlerClass, bind_and_activate=True)
        # server_bind() is called automatically by __init__ with bind_and_activate=True
        # This creates the socket, binds it, and calls listen()
        # server_activate() is also called automatically, which we've overridden for UDS
    elif http_port:
        # HTTP over localhost is not supported for security reasons
        logger.error("Unified-Identity - Phase 3: HTTP over localhost is not supported for security reasons. Use UDS only (--socket-path)")
        sys.exit(1)
    else:
        # Default to UDS
        default_socket = os.path.join(work_dir, "tpm-plugin.sock")
        logger.info("Unified-Identity - Phase 3: Starting TPM Plugin server on UDS (default): %s", default_socket)
        server = UnixHTTPServer(default_socket, HandlerClass, bind_and_activate=True)
        # server_bind() is called automatically by __init__ with bind_and_activate=True
        # This creates the socket, binds it, and calls listen()
        # server_activate() is also called automatically, which we've overridden for UDS
    
    try:
        logger.info("Unified-Identity - Phase 3: TPM Plugin server started")
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Unified-Identity - Phase 3: TPM Plugin server shutting down")
        server.shutdown()


if __name__ == "__main__":
    import argparse
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        stream=sys.stderr
    )
    
    parser = argparse.ArgumentParser(
        description="Unified-Identity - Phase 3: TPM Plugin HTTP/UDS Server"
    )
    parser.add_argument(
        "--socket-path",
        type=str,
        help="UNIX domain socket path (e.g., /tmp/spire-data/tpm-plugin/tpm-plugin.sock)"
    )
    parser.add_argument(
        "--http-port",
        type=int,
        help="[Deprecated] HTTP port for localhost is not supported for security reasons. Use --socket-path for UDS."
    )
    parser.add_argument(
        "--work-dir",
        type=str,
        help="Working directory for TPM operations (default: /tmp/spire-data/tpm-plugin)"
    )
    
    args = parser.parse_args()
    
    run_server(
        socket_path=args.socket_path,
        http_port=args.http_port,
        work_dir=args.work_dir
    )

