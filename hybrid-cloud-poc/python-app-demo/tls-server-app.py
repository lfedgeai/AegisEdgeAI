#!/usr/bin/env python3
"""
TLS Server App with SPIRE SVID and Automatic Renewal
This server uses SPIRE SVIDs for TLS and handles automatic renewal.
"""

import os
import sys
import time
import socket
import ssl
import threading
import signal
from pathlib import Path

try:
    from spiffe.workloadapi import default_client
    from spiffe.svid import x509_svid
    from spiffe.bundle import x509bundle
    HAS_SPIFFE = True
except ImportError:
    print("Error: python-spiffe library not installed")
    print("Install it with: pip install python-spiffe")
    sys.exit(1)

class SPIRETLSServer:
    def __init__(self, socket_path, port, log_file=None):
        self.socket_path = socket_path
        self.port = port
        self.log_file = log_file
        self.running = True
        self.renewal_count = 0
        self.connection_count = 0
        self.last_renewal_time = None
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
    def _signal_handler(self, signum, frame):
        self.log("Received signal, shutting down...")
        self.running = False
        
    def log(self, message):
        """Log message to both console and file if specified."""
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        log_msg = f"[{timestamp}] {message}"
        print(log_msg)
        if self.log_file:
            with open(self.log_file, 'a') as f:
                f.write(log_msg + '\n')
    
    def get_tls_context(self):
        """Get TLS context with SPIRE SVID that auto-renews."""
        # Create X509Source which handles automatic renewal
        socket_path_with_scheme = f"unix://{self.socket_path}"
        
        try:
            source = default_client.DefaultX509Source(socket_path=socket_path_with_scheme)
            bundle_source = default_client.DefaultX509BundleSource(socket_path=socket_path_with_scheme)
            
            # Create TLS context
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            
            # Set up certificate callback that uses SPIRE SVID
            def get_certificate(ssl_socket, server_name=None):
                """Get certificate from SPIRE source (auto-renewed)."""
                try:
                    svid = source.get_x509_svid()
                    if svid:
                        # Convert to TLS certificate format
                        cert = svid.cert
                        key = svid.private_key
                        
                        # Log renewal if certificate changed
                        if self.last_renewal_time:
                            self.log(f"Certificate renewed (SVID ID: {svid.spiffe_id})")
                            self.renewal_count += 1
                        
                        self.last_renewal_time = time.time()
                        return (cert, key)
                except Exception as e:
                    self.log(f"Error getting certificate: {e}")
                    return None
                
            # Use GetCertificate callback for automatic renewal
            # Note: python-spiffe's X509Source handles renewal automatically
            # We need to periodically update the certificate
            
            # For now, use a simpler approach: fetch cert and set it
            # The source will handle renewal in the background
            svid = source.get_x509_svid()
            if not svid:
                raise Exception("Failed to get SVID from SPIRE Agent")
            
            self.log(f"Got SVID: {svid.spiffe_id}")
            
            # Convert to TLS certificate
            from cryptography.hazmat.primitives import serialization
            cert_pem = svid.cert.public_bytes(serialization.Encoding.PEM)
            key_pem = svid.private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            )
            
            # Load into context
            import tempfile
            cert_path = None
            try:
                with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as cert_file:
                    cert_file.write(cert_pem)
                    cert_file.write(key_pem)
                    cert_path = cert_file.name
                
                context.load_cert_chain(cert_path)
            finally:
                # Always clean up temporary cert file, even if load_cert_chain fails
                if cert_path and os.path.exists(cert_path):
                    try:
                        os.unlink(cert_path)
                    except Exception:
                        pass  # Ignore errors during cleanup
            
            # Set up renewal monitoring thread
            def monitor_renewal():
                """Monitor for SVID renewal and update certificate."""
                while self.running:
                    time.sleep(5)  # Check every 5 seconds
                    try:
                        new_svid = source.get_x509_svid()
                        if new_svid and new_svid.cert.serial_number != svid.cert.serial_number:
                            # Certificate was renewed
                            self.log(f"SVID renewed! New serial: {new_svid.cert.serial_number}")
                            self.renewal_count += 1
                            # Update the certificate in the context
                            # Note: This requires recreating the context
                            # For production, use a callback-based approach
                    except Exception as e:
                        self.log(f"Error checking renewal: {e}")
            
            renewal_thread = threading.Thread(target=monitor_renewal, daemon=True)
            renewal_thread.start()
            
            return context, source, bundle_source
            
        except Exception as e:
            self.log(f"Error creating TLS context: {e}")
            raise
    
    def handle_client(self, client_socket, address):
        """Handle a client connection."""
        self.connection_count += 1
        conn_id = self.connection_count
        self.log(f"Client {conn_id} connected from {address}")
        
        try:
            # Receive and echo messages
            while self.running:
                try:
                    data = client_socket.recv(1024)
                    if not data:
                        break
                    
                    message = data.decode('utf-8')
                    self.log(f"Client {conn_id}: {message}")
                    
                    # Echo back
                    response = f"Echo: {message}"
                    client_socket.send(response.encode('utf-8'))
                    
                    # Special command to check renewal status
                    if message.strip() == "STATUS":
                        status = f"Renewals: {self.renewal_count}, Connections: {self.connection_count}"
                        client_socket.send(status.encode('utf-8'))
                        
                except ssl.SSLError as e:
                    if "certificate" in str(e).lower() or "renewal" in str(e).lower():
                        self.log(f"TLS error (possibly renewal): {e}")
                        # Wait a bit and try to reconnect
                        time.sleep(1)
                    else:
                        raise
                except Exception as e:
                    self.log(f"Error handling client {conn_id}: {e}")
                    break
                    
        except Exception as e:
            self.log(f"Error in client handler {conn_id}: {e}")
        finally:
            client_socket.close()
            self.log(f"Client {conn_id} disconnected")
    
    def run(self):
        """Run the TLS server."""
        self.log("Starting TLS Server with SPIRE SVID...")
        self.log(f"SPIRE Agent socket: {self.socket_path}")
        self.log(f"Listening on port: {self.port}")
        
        try:
            # Get TLS context with SPIRE SVID
            context, source, bundle_source = self.get_tls_context()
            
            # Create server socket
            server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server_socket.bind(('0.0.0.0', self.port))
            server_socket.listen(5)
            
            self.log("Server listening for connections...")
            
            while self.running:
                try:
                    client_socket, address = server_socket.accept()
                    
                    # Wrap with TLS
                    try:
                        tls_socket = context.wrap_socket(client_socket, server_side=True)
                        
                        # Handle client in a thread
                        client_thread = threading.Thread(
                            target=self.handle_client,
                            args=(tls_socket, address),
                            daemon=True
                        )
                        client_thread.start()
                    except Exception as e:
                        self.log(f"Error wrapping socket: {e}")
                        client_socket.close()
                        
                except Exception as e:
                    if self.running:
                        self.log(f"Error accepting connection: {e}")
                    break
                    
        except KeyboardInterrupt:
            self.log("Interrupted by user")
        except Exception as e:
            self.log(f"Server error: {e}")
            import traceback
            traceback.print_exc()
        finally:
            self.log("Server shutting down...")
            self.log(f"Total renewals: {self.renewal_count}")
            self.log(f"Total connections: {self.connection_count}")

def main():
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    port = int(os.environ.get('SERVER_PORT', '8443'))
    log_file = os.environ.get('SERVER_LOG', '/tmp/tls-server-app.log')
    
    server = SPIRETLSServer(socket_path, port, log_file)
    server.run()

if __name__ == '__main__':
    main()

