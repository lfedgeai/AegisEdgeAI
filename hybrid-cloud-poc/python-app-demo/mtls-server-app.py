#!/usr/bin/env python3
"""
mTLS Server App with SPIRE SVID and Automatic Renewal
This server uses SPIRE SVIDs for mTLS and automatically renews when agent SVID renews.
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
    from spiffe.workloadapi.x509_source import X509Source
    HAS_SPIFFE = True
except ImportError:
    print("Error: spiffe library not installed")
    print("Install it with: pip install spiffe")
    sys.exit(1)

class SPIREmTLSServer:
    def __init__(self, socket_path, port, log_file=None):
        self.socket_path = socket_path
        self.port = port
        self.log_file = log_file
        self.running = True
        self.renewal_count = 0
        self.connection_count = 0
        self.last_svid_serial = None
        self.source = None
        self.bundle_path = None  # Keep bundle file path for SSL context lifetime
        self.active_connections = []  # Track active client connections for renewal blips
        self.connections_lock = threading.Lock()  # Lock for thread-safe access
        self.context_lock = threading.Lock()
        self.context = None
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
    def _signal_handler(self, signum, frame):
        self.log("Received signal, shutting down...")
        self.running = False
        if self.source:
            self.source.close()
        
    def log(self, message):
        """Log message to both console and file if specified."""
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        log_msg = f"[{timestamp}] {message}"
        print(log_msg)
        if self.log_file:
            with open(self.log_file, 'a') as f:
                f.write(log_msg + '\n')
    
    def get_certificate_callback(self):
        """Return a callback that provides the current SVID certificate."""
        def get_cert(ssl_socket, server_name=None):
            """Get certificate from SPIRE source (auto-renewed)."""
            try:
                svid = self.source.svid
                if not svid:
                    self.log("Error: No SVID available")
                    return None
                
                # Check if SVID was renewed
                current_serial = svid.leaf.serial_number
                if self.last_svid_serial and current_serial != self.last_svid_serial:
                    self.log(f"SVID renewed! Old serial: {self.last_svid_serial}, New serial: {current_serial}")
                    self.renewal_count += 1
                
                self.last_svid_serial = current_serial
                
                # Convert to TLS certificate format
                from cryptography.hazmat.primitives import serialization
                cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM)
                key_pem = svid.private_key.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.PKCS8,
                    encryption_algorithm=serialization.NoEncryption()
                )
                
                # Create TLS certificate
                import tempfile
                with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as cert_file:
                    cert_file.write(cert_pem)
                    cert_file.write(key_pem)
                    cert_path = cert_file.name
                
                # Load and return
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(cert_path)
                os.unlink(cert_path)
                
                return context.get_cert_chain()[0]
                
            except Exception as e:
                self.log(f"Error getting certificate: {e}")
                return None
        
        return get_cert
    
    def verify_client_certificate(self, cert_chain, hostname):
        """Verify client certificate using SPIRE bundle."""
        try:
            # Parse the peer certificate
            from cryptography import x509
            from cryptography.hazmat.backends import default_backend
            
            if not cert_chain or len(cert_chain) == 0:
                return False
            
            # Get the leaf certificate
            cert_bytes = cert_chain[0]
            cert = x509.load_der_x509_certificate(cert_bytes, default_backend())
            
                    # Extract SPIFFE ID from certificate
            try:
                from spiffe.spiffe_id import SpiffeId
                spiffe_id_str = None
                for ext in cert.extensions:
                    if ext.oid._name == 'subjectAltName':
                        for name in ext.value:
                            if isinstance(name, x509.UniformResourceIdentifier):
                                uri = name.value
                                if uri.startswith('spiffe://'):
                                    spiffe_id_str = uri
                                    break
                
                if spiffe_id_str:
                    self.log(f"Client SPIFFE ID: {spiffe_id_str}")
                    # Verify against bundle
                    # For now, just log - full verification would use bundle_source
                    return True
            except Exception as e:
                self.log(f"Error verifying client cert: {e}")
                return False
            
            return True
        except Exception as e:
            self.log(f"Error in certificate verification: {e}")
            return False

    def _load_server_certificate(self, context, svid):
        """Load the provided SVID into the TLS context."""
        from cryptography.hazmat.primitives import serialization
        import tempfile
        cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM)
        key_pem = svid.private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as cert_file:
            cert_file.write(cert_pem)
            cert_file.write(key_pem)
            cert_path = cert_file.name
        try:
            context.load_cert_chain(cert_path)
        finally:
            try:
                os.unlink(cert_path)
            except OSError:
                pass
    
    def setup_tls_context(self):
        """Setup TLS context with SPIRE SVID source."""
        socket_path_with_scheme = f"unix://{self.socket_path}"
        
        try:
            # Create X509Source which handles automatic renewal
            self.source = X509Source(socket_path=socket_path_with_scheme)
            
            # Get initial SVID
            svid = self.source.svid
            if not svid:
                raise Exception("Failed to get SVID from SPIRE Agent")
            
            self.log(f"Got initial SVID: {svid.spiffe_id}")
            self.log(f"  Initial Certificate Serial: {svid.leaf.serial_number}")
            self.log(f"  Certificate Expires: {svid.leaf.not_valid_after}")
            self.log("  Monitoring for automatic SVID renewal...")
            self.last_svid_serial = svid.leaf.serial_number
            
            # Get trust bundle for peer certificate verification
            trust_domain = svid.spiffe_id.trust_domain
            bundle = None
            try:
                # Wait a moment for bundle to be available
                import time
                time.sleep(0.5)
                
                bundle = self.source.get_bundle_for_trust_domain(trust_domain)
                if bundle:
                    # Load CA certificates from bundle into SSL context
                    from cryptography.hazmat.primitives import serialization
                    import tempfile
                    x509_authorities = bundle.x509_authorities  # Property, not method
                    if x509_authorities and len(x509_authorities) > 0:
                        bundle_pem = b""
                        for cert in x509_authorities:
                            bundle_pem += cert.public_bytes(serialization.Encoding.PEM)
                        
                        with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as bundle_file:
                            bundle_file.write(bundle_pem)
                            self.bundle_path = bundle_file.name  # Store as instance variable
                        
                        self.log(f"  ✓ Loaded trust bundle with {len(x509_authorities)} CA certificate(s)")
                        self.log(f"  Bundle file: {self.bundle_path}")
                    else:
                        self.log(f"  ⚠ Warning: Bundle has no X509 authorities")
                else:
                    self.log(f"  ⚠ Warning: Could not get bundle for trust domain: {trust_domain}")
            except Exception as e:
                self.log(f"  ⚠ Warning: Could not load trust bundle: {e}")
                import traceback
                self.log(f"  Traceback: {traceback.format_exc()}")
            
            # Create TLS context
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.check_hostname = False
            
            # Load trust bundle for peer verification
            if self.bundle_path:
                try:
                    context.load_verify_locations(self.bundle_path)
                    context.verify_mode = ssl.CERT_OPTIONAL  # Request client cert and verify it
                    self.log(f"  ✓ Trust bundle loaded into SSL context")
                except Exception as e:
                    self.log(f"  ⚠ Error loading bundle into SSL context: {e}")
                    context.verify_mode = ssl.CERT_NONE  # Fallback: don't verify if bundle load fails
            else:
                self.log(f"  ⚠ No bundle path available, using CERT_NONE (no peer verification)")
                context.verify_mode = ssl.CERT_NONE  # Don't verify if no bundle
            
            # Load initial certificate into context
            self._load_server_certificate(context, svid)
            
            # Monitor for renewal and update context
            def monitor_and_update():
                """Monitor for SVID renewal and update TLS context."""
                while self.running:
                    time.sleep(2)  # Check every 2 seconds
                    try:
                        new_svid = self.source.svid
                        if new_svid and new_svid.leaf.serial_number != self.last_svid_serial:
                            # DEMO: Show renewal blip clearly
                            old_serial = self.last_svid_serial
                            new_serial = new_svid.leaf.serial_number
                            old_expiry = None
                            new_expiry = new_svid.leaf.not_valid_after
                            
                            if old_serial:
                                self.log("")
                                self.log("╔════════════════════════════════════════════════════════════════╗")
                                self.log("║  🔄 SVID RENEWAL DETECTED - RENEWAL BLIP EVENT                  ║")
                                self.log("╚════════════════════════════════════════════════════════════════╝")
                                self.log(f"  Old Certificate Serial: {old_serial}")
                                self.log(f"  New Certificate Serial: {new_serial}")
                                self.log(f"  New Certificate Expires: {new_expiry}")
                                self.log(f"  SPIFFE ID: {new_svid.spiffe_id}")
                                self.log("  ⚠️  RENEWAL BLIP: Existing connections may experience brief interruption")
                                self.log("  ✓  New connections will automatically use renewed certificate")
                                self.log("")
                            
                            self.renewal_count += 1
                            self.last_svid_serial = new_svid.leaf.serial_number
                            
                            # DEMO: Close existing connections to force renewal blip
                            # This makes the renewal visible to clients
                            self.log("  🔄 Closing existing connections to demonstrate renewal blip...")
                            with self.connections_lock:
                                connections_to_close = list(self.active_connections)
                            for conn in connections_to_close:
                                try:
                                    # Properly shutdown and close connection
                                    conn.shutdown(socket.SHUT_RDWR)
                                except:
                                    pass
                                try:
                                    conn.close()
                                    self.log(f"  ✓ Closed connection to force client reconnection (renewal blip)")
                                except:
                                    pass
                            with self.connections_lock:
                                self.active_connections.clear()
                            
                            with self.context_lock:
                                self._load_server_certificate(self.context, new_svid)
                                self.log("  ✓ TLS context updated with renewed certificate")
                    except Exception as e:
                        if self.running:
                            self.log(f"Error checking renewal: {e}")
            
            renewal_thread = threading.Thread(target=monitor_and_update, daemon=True)
            renewal_thread.start()
            
            return context
            
        except Exception as e:
            self.log(f"Error setting up TLS context: {e}")
            import traceback
            traceback.print_exc()
            raise
    
    def handle_client(self, client_socket, address):
        """Handle a client connection."""
        self.connection_count += 1
        conn_id = self.connection_count
        self.log(f"Client {conn_id} connected from {address}")
        
        # Track this connection for renewal blip handling
        with self.connections_lock:
            self.active_connections.append(client_socket)
        
        try:
            # Receive and echo messages
            while self.running:
                try:
                    data = client_socket.recv(1024)
                    if not data:
                        break
                    
                    message = data.decode('utf-8', errors='replace').strip()
                    self.log(f"🔊 Client {conn_id} says: {message}")
                    
                    # Echo back
                    response = f"SERVER ACK: {message}"
                    client_socket.sendall(response.encode('utf-8'))
                    self.log(f"✅ Responded to client {conn_id}: {response}")
                    
                    # Special command to check renewal status
                    if message.upper() == "STATUS":
                        status = f"Renewals: {self.renewal_count}, Connections: {self.connection_count}"
                        client_socket.sendall(status.encode('utf-8'))
                        
                except ssl.SSLError as e:
                    if "certificate" in str(e).lower() or "renewal" in str(e).lower():
                        # DEMO: Show renewal blip in action
                        self.log("")
                        self.log("  ⚠️  RENEWAL BLIP: TLS error detected (certificate renewal in progress)")
                        self.log(f"     Error: {str(e)[:100]}")
                        self.log("     Connection will be retried with renewed certificate...")
                        self.log("")
                        # Wait a bit and try to continue
                        time.sleep(0.5)
                    else:
                        raise
                except (ConnectionError, BrokenPipeError) as e:
                    # DEMO: Show connection closure (may be due to renewal)
                    if "renewal" in str(e).lower() or self.renewal_count > 0:
                        self.log(f"  ⚠️  Connection closed (possibly due to renewal blip): {e}")
                    else:
                        self.log(f"Connection closed: {e}")
                    break
                except Exception as e:
                    self.log(f"Error handling client {conn_id}: {e}")
                    break
                    
        except Exception as e:
            self.log(f"Error in client handler {conn_id}: {e}")
        finally:
            # Remove from active connections
            with self.connections_lock:
                if client_socket in self.active_connections:
                    self.active_connections.remove(client_socket)
            try:
                client_socket.close()
            except:
                pass
            self.log(f"Client {conn_id} disconnected")
    
    def run(self):
        """Run the mTLS server."""
        self.log("")
        self.log("╔════════════════════════════════════════════════════════════════╗")
        self.log("║  mTLS Server Starting with Automatic SVID Renewal              ║")
        self.log("╚════════════════════════════════════════════════════════════════╝")
        self.log(f"SPIRE Agent socket: {self.socket_path}")
        self.log(f"Listening on port: {self.port}")
        self.log("")
        
        try:
            # Setup TLS context with SPIRE SVID
            context = self.setup_tls_context()
            with self.context_lock:
                self.context = context
            
            # Create server socket
            server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server_socket.bind(('0.0.0.0', self.port))
            server_socket.listen(5)
            
            self.log("")
            self.log("╔════════════════════════════════════════════════════════════════╗")
            self.log("║  Server Ready - Waiting for mTLS Connections                   ║")
            self.log("╚════════════════════════════════════════════════════════════════╝")
            self.log("  Automatic SVID renewal is active")
            self.log("  Renewal blips will be logged when they occur")
            self.log("")
            
            while self.running:
                try:
                    client_socket, address = server_socket.accept()
                    
                    # Wrap with TLS
                    try:
                        with self.context_lock:
                            active_context = self.context
                        tls_socket = active_context.wrap_socket(client_socket, server_side=True)
                        
                        self.log(f"✓ New TLS client connected from {address[0]}:{address[1]}")
                        if self.renewal_count > 0:
                            self.log("  (Connection established with renewed server certificate)")
                        
                        # Handle client in a thread
                        client_thread = threading.Thread(
                            target=self.handle_client,
                            args=(tls_socket, address),
                            daemon=True
                        )
                        client_thread.start()
                    except ssl.SSLError as e:
                        # DEMO: Show TLS errors (may be renewal-related)
                        if "certificate" in str(e).lower():
                            self.log(f"  ⚠️  TLS handshake error (possibly renewal blip): {e}")
                        else:
                            self.log(f"TLS handshake error: {e}")
                        client_socket.close()
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
            if self.source:
                self.source.close()
            # Clean up bundle file
            if self.bundle_path and os.path.exists(self.bundle_path):
                try:
                    os.unlink(self.bundle_path)
                except:
                    pass
            self.log("Server shutting down...")
            self.log(f"Total renewals: {self.renewal_count}")
            self.log(f"Total connections: {self.connection_count}")

def main():
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    port = int(os.environ.get('SERVER_PORT', '9443'))
    log_file = os.environ.get('SERVER_LOG', '/tmp/mtls-server-app.log')
    
    server = SPIREmTLSServer(socket_path, port, log_file)
    server.run()

if __name__ == '__main__':
    main()

