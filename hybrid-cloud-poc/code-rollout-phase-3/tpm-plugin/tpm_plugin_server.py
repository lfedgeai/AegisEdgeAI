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
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse, parse_qs

from tpm_plugin import TPMPlugin, is_unified_identity_enabled
from delegated_certification import DelegatedCertificationClient

logger = logging.getLogger(__name__)


class TPMPluginHTTPHandler(BaseHTTPRequestHandler):
    """HTTP request handler for TPM Plugin API"""
    
    def __init__(self, *args, work_dir: str = None, **kwargs):
        self.work_dir = work_dir or "/tmp/spire-data/tpm-plugin"
        super().__init__(*args, **kwargs)
    
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
        
        if path == "/generate-app-key":
            self.handle_generate_app_key(request_data)
        elif path == "/generate-quote":
            self.handle_generate_quote(request_data)
        elif path == "/request-certificate":
            self.handle_request_certificate(request_data)
        else:
            self.send_error(404, f"Unknown endpoint: {path}")
    
    def handle_generate_app_key(self, request_data: dict):
        """Handle /generate-app-key endpoint"""
        try:
            work_dir = request_data.get("work_dir", self.work_dir)
            force = request_data.get("force", False)
            
            plugin = TPMPlugin(work_dir=work_dir)
            success, app_key_public, app_key_ctx = plugin.generate_app_key(force=force)
            
            if not success:
                self.send_error(500, "Unified-Identity - Phase 3: Failed to generate App Key")
                return
            
            response = {
                "status": "success",
                "app_key_public": app_key_public,
                "app_key_context": app_key_ctx
            }
            
            self.send_json_response(200, response)
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Error generating App Key: %s", e)
            self.send_error(500, f"Internal error: {e}")
    
    def handle_generate_quote(self, request_data: dict):
        """Handle /generate-quote endpoint"""
        try:
            nonce = request_data.get("nonce")
            if not nonce:
                self.send_error(400, "Unified-Identity - Phase 3: Nonce is required")
                return
            
            work_dir = request_data.get("work_dir", self.work_dir)
            pcr_list = request_data.get("pcr_list", "sha256:0,1")
            app_key_context = request_data.get("app_key_context")
            
            plugin = TPMPlugin(work_dir=work_dir)
            success, quote_b64, metadata = plugin.generate_quote(
                nonce=nonce,
                pcr_list=pcr_list,
                app_key_context=app_key_context
            )
            
            if not success:
                self.send_error(500, "Unified-Identity - Phase 3: Failed to generate quote")
                return
            
            response = {
                "status": "success",
                "quote": quote_b64
            }
            
            self.send_json_response(200, response)
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Error generating quote: %s", e)
            self.send_error(500, f"Internal error: {e}")
    
    def handle_request_certificate(self, request_data: dict):
        """Handle /request-certificate endpoint"""
        try:
            app_key_public = request_data.get("app_key_public")
            app_key_context_path = request_data.get("app_key_context_path")
            endpoint = request_data.get("endpoint")
            
            if not app_key_public or not app_key_context_path:
                self.send_error(400, "Unified-Identity - Phase 3: app_key_public and app_key_context_path are required")
                return
            
            client = DelegatedCertificationClient(endpoint=endpoint)
            success, cert_b64, error = client.request_certificate(
                app_key_public=app_key_public,
                app_key_context_path=app_key_context_path
            )
            
            if not success:
                self.send_error(500, f"Unified-Identity - Phase 3: Failed to request certificate: {error}")
                return
            
            response = {
                "status": "success",
                "app_key_certificate": cert_b64
            }
            
            self.send_json_response(200, response)
        except Exception as e:
            logger.error("Unified-Identity - Phase 3: Error requesting certificate: %s", e)
            self.send_error(500, f"Internal error: {e}")
    
    def send_json_response(self, status_code: int, data: dict):
        """Send JSON response"""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))
    
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
            # Create a dummy address for HTTPServer
            HTTPServer.__init__(self, ("localhost", 0), RequestHandlerClass, bind_and_activate=False)
        else:
            self.socket_path = None
            HTTPServer.__init__(self, server_address, RequestHandlerClass, bind_and_activate=bind_and_activate)
    
    def server_bind(self):
        if self.socket_path:
            # Remove socket file if it exists
            if os.path.exists(self.socket_path):
                os.unlink(self.socket_path)
            
            # Create socket
            self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.socket.bind(self.socket_path)
            # Set socket permissions (read/write for owner and group)
            os.chmod(self.socket_path, 0o660)
        else:
            HTTPServer.server_bind(self)
    
    def server_close(self):
        HTTPServer.server_close(self)
        if self.socket_path and os.path.exists(self.socket_path):
            os.unlink(self.socket_path)


def create_handler_class(work_dir: str):
    """Create a handler class with work_dir bound"""
    class Handler(TPMPluginHTTPHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, work_dir=work_dir, **kwargs)
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
    
    HandlerClass = create_handler_class(work_dir)
    
    if socket_path:
        # Use UNIX domain socket
        socket_path = os.path.abspath(socket_path)
        logger.info("Unified-Identity - Phase 3: Starting TPM Plugin server on UDS: %s", socket_path)
        server = UnixHTTPServer(socket_path, HandlerClass)
        # Explicitly bind the socket so it's created immediately (before serve_forever)
        server.server_bind()
        # Call server_activate to listen on the socket (this creates the socket file)
        if hasattr(server, 'server_activate'):
            server.server_activate()
        else:
            # Fallback: manually call listen if server_activate doesn't exist
            server.socket.listen(5)
    elif http_port:
        # HTTP over localhost is not supported for security reasons
        logger.error("Unified-Identity - Phase 3: HTTP over localhost is not supported for security reasons. Use UDS only (--socket-path)")
        sys.exit(1)
    else:
        # Default to UDS
        default_socket = os.path.join(work_dir, "tpm-plugin.sock")
        logger.info("Unified-Identity - Phase 3: Starting TPM Plugin server on UDS (default): %s", default_socket)
        server = UnixHTTPServer(default_socket, HandlerClass)
        # Explicitly bind the socket so it's created immediately (before serve_forever)
        server.server_bind()
        # Call server_activate to listen on the socket (this creates the socket file)
        if hasattr(server, 'server_activate'):
            server.server_activate()
        else:
            # Fallback: manually call listen if server_activate doesn't exist
            server.socket.listen(5)
    
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

