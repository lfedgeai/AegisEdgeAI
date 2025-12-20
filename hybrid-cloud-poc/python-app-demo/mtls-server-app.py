#!/usr/bin/env python3
"""
mTLS Server App with SPIRE SVID and Automatic Renewal
This server uses SPIRE SVIDs for mTLS and automatically renews when agent SVID renews.
Can also run in standard certificate mode (no SPIRE required).
"""

import os
import sys
import time
import socket
import ssl
import threading
import signal
import ipaddress
from pathlib import Path
from datetime import datetime, timedelta

try:
    from spiffe.workloadapi.x509_source import X509Source
    HAS_SPIFFE = True
except ImportError:
    HAS_SPIFFE = False

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID
    HAS_CRYPTOGRAPHY = True
except ImportError:
    HAS_CRYPTOGRAPHY = False
    print("Warning: cryptography library not installed. Standard cert mode will not work.")
    print("Install it with: pip install cryptography")

class SPIREmTLSServer:
    def __init__(self, socket_path, port, log_file=None, use_spire=None, 
                 server_cert_path=None, server_key_path=None, ca_cert_path=None):
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
        
        # Certificate mode configuration
        if use_spire is None:
            # Auto-detect: use SPIRE if socket exists and spiffe is available, otherwise use standard
            self.use_spire = HAS_SPIFFE and os.path.exists(socket_path) if socket_path else False
        else:
            self.use_spire = use_spire
        
        # Standard cert paths
        self.server_cert_path = server_cert_path
        self.server_key_path = server_key_path
        self.ca_cert_path = ca_cert_path
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
    def _signal_handler(self, signum, frame):
        self.log("Received signal, shutting down...")
        self.running = False
        if self.source:
            self.source.close()
    
    def generate_self_signed_cert(self, cert_path, key_path, ca_cert_path=None):
        """Generate a self-signed certificate and key for standard cert mode."""
        if not HAS_CRYPTOGRAPHY:
            raise Exception("cryptography library required for standard cert mode")
        
        self.log("Generating self-signed certificate...")
        
        # Generate private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )
        
        # Create certificate
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "CA"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "San Francisco"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "mTLS Demo"),
            x509.NameAttribute(NameOID.COMMON_NAME, "mtls-server"),
        ])
        
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.utcnow()
        ).not_valid_after(
            datetime.utcnow() + timedelta(days=365)
        ).add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
            ]),
            critical=False,
        ).sign(private_key, hashes.SHA256())
        
        # Write certificate
        with open(cert_path, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
        
        # Write private key
        with open(key_path, "wb") as f:
            f.write(private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            ))
        
        # If CA cert path provided, only copy server cert if CA file doesn't exist
        # This prevents overwriting existing CA bundles (e.g., combined-ca-bundle.pem with SPIRE + Envoy certs)
        if ca_cert_path:
            import shutil
            if not os.path.exists(ca_cert_path):
                shutil.copy(cert_path, ca_cert_path)
                self.log(f"  ✓ CA certificate saved to {ca_cert_path}")
            else:
                self.log(f"  ℹ CA certificate file already exists: {ca_cert_path} (preserving existing CA bundle)")
        
        self.log(f"  ✓ Server certificate saved to {cert_path}")
        self.log(f"  ✓ Server key saved to {key_path}")
        return cert_path, key_path
        
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
                cert_path = None
                try:
                    with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as cert_file:
                        cert_file.write(cert_pem)
                        cert_file.write(key_pem)
                        cert_path = cert_file.name
                    
                    # Load and return
                    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                    context.load_cert_chain(cert_path)
                finally:
                    # Always clean up temporary cert file, even if load_cert_chain fails
                    if cert_path and os.path.exists(cert_path):
                        try:
                            os.unlink(cert_path)
                        except Exception:
                            pass  # Ignore errors during cleanup
                
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
    
    def setup_tls_context_standard(self):
        """Setup TLS context with standard certificates (no SPIRE)."""
        if not HAS_CRYPTOGRAPHY:
            raise Exception("cryptography library required for standard cert mode")
        
        self.log("Setting up TLS context with standard certificates...")
        
        # Determine certificate paths
        if self.server_cert_path and self.server_key_path:
            cert_path = self.server_cert_path
            key_path = self.server_key_path
            if not os.path.exists(cert_path) or not os.path.exists(key_path):
                raise Exception(f"Certificate files not found: {cert_path} or {key_path}")
            self.log(f"  Using provided certificates: {cert_path}, {key_path}")
        else:
            # Generate self-signed certificates
            cert_dir = os.path.join(os.path.expanduser("~"), ".mtls-demo")
            os.makedirs(cert_dir, mode=0o700, exist_ok=True)
            cert_path = os.path.join(cert_dir, "server-cert.pem")
            key_path = os.path.join(cert_dir, "server-key.pem")
            
            if not os.path.exists(cert_path) or not os.path.exists(key_path):
                self.generate_self_signed_cert(cert_path, key_path, self.ca_cert_path)
            else:
                self.log(f"  Using existing certificates: {cert_path}, {key_path}")
        
        # Create TLS context
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.check_hostname = False
        context.load_cert_chain(cert_path, key_path)
        
        # Load CA certificate for client verification if provided
        # In mixed mode (standard cert server + SPIRE client), we need to accept SPIRE-issued client certs
        if self.ca_cert_path and os.path.exists(self.ca_cert_path):
            context.load_verify_locations(self.ca_cert_path)
            context.verify_mode = ssl.CERT_OPTIONAL  # Request client cert and verify it
            self.log(f"  ✓ CA certificate loaded for client verification: {self.ca_cert_path}")
        else:
            # If no CA provided, try to use the same cert as CA (self-signed mode)
            if self.ca_cert_path:
                context.load_verify_locations(cert_path)  # Use server cert as CA
                context.verify_mode = ssl.CERT_OPTIONAL
                self.log(f"  ✓ Using server certificate as CA for client verification")
            else:
                # For mixed mode: accept any client certificate (including SPIRE-issued)
                # This allows SPIRE clients to connect to standard cert servers
                context.verify_mode = ssl.CERT_OPTIONAL  # Request client cert but don't strictly verify
                self.log(f"  ⚠ No CA certificate provided")
                self.log(f"  ℹ Mixed mode: Accepting client certificates (including SPIRE-issued)")
                self.log(f"  ℹ Note: For strict verification, provide CA_CERT_PATH with SPIRE CA")
        
        self.log("  ✓ Standard TLS context configured")
        return context
    
    def setup_tls_context(self):
        """Setup TLS context - either SPIRE or standard cert mode."""
        if self.use_spire:
            return self.setup_tls_context_spire()
        else:
            return self.setup_tls_context_standard()
    
    def setup_tls_context_spire(self):
        """Setup TLS context with SPIRE SVID source."""
        if not HAS_SPIFFE:
            raise Exception("SPIRE mode requires spiffe library. Install with: pip install spiffe")
        
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
                # Clean up old bundle file if it exists (from previous renewal)
                if self.bundle_path and os.path.exists(self.bundle_path):
                    try:
                        os.unlink(self.bundle_path)
                    except Exception:
                        pass  # Ignore errors during cleanup
                    self.bundle_path = None
                
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
            
            # Monitor for renewal and update context (SPIRE mode only)
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
                            new_expiry = new_svid.leaf.not_valid_after_utc if hasattr(new_svid.leaf, 'not_valid_after_utc') else new_svid.leaf.not_valid_after
                            
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
            
            # Only start renewal monitoring in SPIRE mode
            renewal_thread = threading.Thread(target=monitor_and_update, daemon=True)
            renewal_thread.start()
            
            return context
            
        except Exception as e:
            self.log(f"Error setting up TLS context: {e}")
            import traceback
            traceback.print_exc()
            raise
    
    def _detect_peer_cert_type(self, tls_socket):
        """Detect if peer certificate is SPIRE-issued or standard."""
        try:
            peer_cert = tls_socket.getpeercert(binary_form=False)
            if not peer_cert:
                return None
            
            # Check for SPIFFE ID in certificate
            import ssl
            cert_der = tls_socket.getpeercert_chain()[0] if hasattr(tls_socket, 'getpeercert_chain') else None
            if cert_der:
                from cryptography import x509
                from cryptography.hazmat.backends import default_backend
                cert = x509.load_der_x509_certificate(cert_der, default_backend())
                
                # Check for SPIFFE ID in SAN
                for ext in cert.extensions:
                    if ext.oid._name == 'subjectAltName':
                        for name in ext.value:
                            if hasattr(name, 'value') and isinstance(name.value, str):
                                if name.value.startswith('spiffe://'):
                                    return 'SPIRE'
            
            return 'standard'
        except Exception as e:
            self.log(f"  ⚠ Could not detect peer cert type: {e}")
            return None
    
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
                    # Receive HTTP request
                    request_data = b""
                    while True:
                        chunk = client_socket.recv(4096)
                        if not chunk:
                            break
                        request_data += chunk
                        # Check if we've received the full HTTP request headers
                        if b"\r\n\r\n" in request_data:
                            # Try to read body if Content-Length is specified
                            headers_end = request_data.find(b"\r\n\r\n")
                            headers = request_data[:headers_end].decode('utf-8', errors='replace')
                            
                            # Check for Content-Length
                            content_length = 0
                            for line in headers.split('\r\n'):
                                if line.lower().startswith('content-length:'):
                                    try:
                                        content_length = int(line.split(':', 1)[1].strip())
                                        break
                                    except:
                                        pass
                            
                            if content_length > 0:
                                body_start = headers_end + 4
                                body_received = len(request_data) - body_start
                                if body_received >= content_length:
                                    break
                            else:
                                # No Content-Length, assume request is complete
                                break
                    
                    if not request_data:
                        break
                    
                    # Parse HTTP request
                    request_text = request_data.decode('utf-8', errors='replace')
                    request_lines = request_text.split('\r\n')
                    if not request_lines:
                        break
                    
                    # Parse request line
                    request_line = request_lines[0]
                    parts = request_line.split()
                    if len(parts) < 2:
                        break
                    method = parts[0]
                    path = parts[1]
                    
                    # Extract message from X-Message header or path
                    message = path
                    sensor_id = None
                    for line in request_lines[1:]:
                        if line.lower().startswith('x-sensor-id:'):
                            sensor_id = line.split(':', 1)[1].strip()
                            self.log(f"🔊 Client {conn_id} sensor ID (from X-Sensor-ID header): {sensor_id}")
                        elif line.lower().startswith('x-message:'):
                            message = line.split(':', 1)[1].strip()
                            break
                    
                    if sensor_id:
                        self.log(f"🔊 Client {conn_id} HTTP {method} {path}: {message} [Sensor ID: {sensor_id}]")
                    else:
                        self.log(f"🔊 Client {conn_id} HTTP {method} {path}: {message}")
                    
                    # Prepare HTTP response
                    response_body = f"SERVER ACK: {message}"
                    http_response = (
                        f"HTTP/1.1 200 OK\r\n"
                        f"Content-Type: text/plain\r\n"
                        f"Content-Length: {len(response_body)}\r\n"
                        f"Connection: keep-alive\r\n"
                        f"X-Connection-ID: {conn_id}\r\n"
                        f"\r\n"
                        f"{response_body}"
                    )
                    
                    client_socket.sendall(http_response.encode('utf-8'))
                    self.log(f"✅ Responded to client {conn_id} with HTTP 200: {response_body}")
                    
                    # Special status endpoint
                    if path == "/status" or message.upper() == "STATUS":
                        status_body = f"Renewals: {self.renewal_count}, Connections: {self.connection_count}"
                        status_response = (
                            f"HTTP/1.1 200 OK\r\n"
                            f"Content-Type: text/plain\r\n"
                            f"Content-Length: {len(status_body)}\r\n"
                            f"Connection: keep-alive\r\n"
                            f"\r\n"
                            f"{status_body}"
                        )
                        client_socket.sendall(status_response.encode('utf-8'))
                        
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
        if self.use_spire:
            self.log("╔════════════════════════════════════════════════════════════════╗")
            self.log("║  mTLS Server Starting with SPIRE SVID (Automatic Renewal)      ║")
            self.log("╚════════════════════════════════════════════════════════════════╝")
            self.log(f"SPIRE Agent socket: {self.socket_path}")
        else:
            self.log("╔════════════════════════════════════════════════════════════════╗")
            self.log("║  mTLS Server Starting with Standard Certificates               ║")
            self.log("╚════════════════════════════════════════════════════════════════╝")
        self.log(f"Listening on port: {self.port}")
        self.log("")
        
        # Log mode and compatibility info
        if self.use_spire:
            self.log("  Mode: SPIRE (automatic SVID renewal enabled)")
            self.log("  Accepts: SPIRE and standard client certificates")
        else:
            self.log("  Mode: Standard Certificates (no SPIRE)")
            self.log("  Accepts: SPIRE and standard client certificates (mixed mode supported)")
            if not self.ca_cert_path:
                self.log("  ⚠ Client verification: Permissive (accepts any client cert)")
                self.log("  ℹ For strict verification, provide CA_CERT_PATH with SPIRE CA")
        
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
            if self.use_spire:
                self.log("  Automatic SVID renewal is active")
                self.log("  Renewal blips will be logged when they occur")
            else:
                self.log("  Standard certificate mode (no SPIRE)")
                self.log("  No automatic renewal (certificates are static)")
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
                        
                        # Detect and log client certificate type
                        client_cert_type = self._detect_peer_cert_type(tls_socket)
                        if client_cert_type:
                            if client_cert_type == 'SPIRE' and not self.use_spire:
                                self.log(f"  ℹ Mixed mode: Client using SPIRE certificate, Server using standard certificate")
                                self.log(f"  ℹ This is supported - server accepts SPIRE-issued client certificates")
                            elif client_cert_type == 'standard' and self.use_spire:
                                self.log(f"  ℹ Mixed mode: Client using standard certificate, Server using SPIRE certificate")
                                self.log(f"  ℹ This is supported - server accepts standard client certificates")
                            else:
                                self.log(f"  ℹ Client certificate type: {client_cert_type} (matches server mode)")
                        
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
    
    # Certificate mode configuration
    use_spire_env = os.environ.get('SERVER_USE_SPIRE', '').lower()
    if use_spire_env == 'true' or use_spire_env == '1':
        use_spire = True
    elif use_spire_env == 'false' or use_spire_env == '0':
        use_spire = False
    else:
        use_spire = None  # Auto-detect
    
    # Standard cert paths (optional) - expand ~ in paths
    server_cert_path = os.environ.get('SERVER_CERT_PATH')
    if server_cert_path:
        server_cert_path = os.path.expanduser(server_cert_path)
    server_key_path = os.environ.get('SERVER_KEY_PATH')
    if server_key_path:
        server_key_path = os.path.expanduser(server_key_path)
    ca_cert_path = os.environ.get('CA_CERT_PATH')
    if ca_cert_path:
        ca_cert_path = os.path.expanduser(ca_cert_path)
    
    server = SPIREmTLSServer(
        socket_path, 
        port, 
        log_file,
        use_spire=use_spire,
        server_cert_path=server_cert_path,
        server_key_path=server_key_path,
        ca_cert_path=ca_cert_path
    )
    server.run()

if __name__ == '__main__':
    main()

