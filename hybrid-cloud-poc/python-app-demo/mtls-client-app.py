#!/usr/bin/env python3
"""
mTLS Client App with SPIRE SVID and Automatic Renewal
This client connects to the mTLS server using SPIRE SVIDs and automatically renews when agent SVID renews.
Can also work with standard certificates (no SPIRE required).
"""

import os
import sys
import time
import socket
import ssl
import signal
import ipaddress
from pathlib import Path

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
    from datetime import datetime, timedelta, timezone
    HAS_CRYPTOGRAPHY = True
except ImportError:
    HAS_CRYPTOGRAPHY = False
    print("Warning: cryptography library not installed. Standard cert mode will not work.")
    print("Install it with: pip install cryptography")

class SPIREmTLSClient:
    def __init__(self, socket_path, server_host, server_port, log_file=None,
                 use_spire=None, client_cert_path=None, client_key_path=None, ca_cert_path=None):
        self.socket_path = socket_path
        self.server_host = server_host
        self.server_port = server_port
        self.log_file = log_file
        self.running = True
        self.renewal_count = 0
        self.message_count = 0
        self.reconnect_count = 0
        self.last_svid_serial = None
        self.source = None
        self.bundle_path = None  # Keep bundle file path for SSL context lifetime
        # Track logging so we don't spam on repeated renewal blips
        self.last_logged_renewal_id = 0
        # Track if we've logged the first connection (for stable reconnection behavior)
        self._first_connection_logged = False
        # Track if reconnection is due to renewal (should be logged)
        self._reconnect_due_to_renewal = False
        
        # Certificate mode configuration
        if use_spire is None:
            # Auto-detect: use SPIRE if socket exists and spiffe is available, otherwise use standard
            self.use_spire = HAS_SPIFFE and os.path.exists(socket_path) if socket_path else False
        else:
            self.use_spire = use_spire
        
        # Standard cert paths
        self.client_cert_path = client_cert_path
        self.client_key_path = client_key_path
        self.ca_cert_path = ca_cert_path
        
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
    
    def generate_self_signed_cert(self, cert_path, key_path):
        """Generate a self-signed certificate and key for standard cert mode."""
        if not HAS_CRYPTOGRAPHY:
            raise Exception("cryptography library required for standard cert mode")
        
        self.log("Generating self-signed client certificate...")
        
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
            x509.NameAttribute(NameOID.COMMON_NAME, "mtls-client"),
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
        
        self.log(f"  ✓ Client certificate saved to {cert_path}")
        self.log(f"  ✓ Client key saved to {key_path}")
        return cert_path, key_path
    
    def setup_tls_context_standard(self):
        """Setup TLS context with standard certificates (no SPIRE)."""
        if not HAS_CRYPTOGRAPHY:
            raise Exception("cryptography library required for standard cert mode")
        
        self.log("Setting up TLS context with standard certificates...")
        
        # Determine certificate paths
        if self.client_cert_path and self.client_key_path:
            cert_path = self.client_cert_path
            key_path = self.client_key_path
            if not os.path.exists(cert_path) or not os.path.exists(key_path):
                raise Exception(f"Certificate files not found: {cert_path} or {key_path}")
            self.log(f"  Using provided certificates: {cert_path}, {key_path}")
        else:
            # Generate self-signed certificates
            cert_dir = os.path.join(os.path.expanduser("~"), ".mtls-demo")
            os.makedirs(cert_dir, mode=0o700, exist_ok=True)
            cert_path = os.path.join(cert_dir, "client-cert.pem")
            key_path = os.path.join(cert_dir, "client-key.pem")
            
            if not os.path.exists(cert_path) or not os.path.exists(key_path):
                self.generate_self_signed_cert(cert_path, key_path)
            else:
                self.log(f"  Using existing certificates: {cert_path}, {key_path}")
        
        # Create TLS context
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.load_cert_chain(cert_path, key_path)
        
        # Load CA certificate for server verification
        if self.ca_cert_path and os.path.exists(self.ca_cert_path):
            context.load_verify_locations(self.ca_cert_path)
            context.verify_mode = ssl.CERT_REQUIRED
            self.log(f"  ✓ CA certificate loaded for server verification: {self.ca_cert_path}")
        else:
            # Try to find server cert as CA (for self-signed server)
            server_cert_path = os.path.join(os.path.expanduser("~"), ".mtls-demo", "server-cert.pem")
            if os.path.exists(server_cert_path):
                context.load_verify_locations(server_cert_path)
                context.verify_mode = ssl.CERT_REQUIRED
                self.log(f"  ✓ Using server certificate as CA for verification")
            else:
                context.verify_mode = ssl.CERT_NONE  # No server verification
                self.log(f"  ⚠ No CA certificate found, server verification disabled")
        
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
            expiry = svid.leaf.not_valid_after_utc if hasattr(svid.leaf, 'not_valid_after_utc') else svid.leaf.not_valid_after
            self.log(f"  Certificate Expires: {expiry}")
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
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            
            # Load trust bundle for peer verification
            if self.bundle_path:
                try:
                    context.load_verify_locations(self.bundle_path)
                    self.log(f"  ✓ SPIRE trust bundle loaded into SSL context")
                    
                    # Also load additional CA cert if provided (for mixed mode: SPIRE client + standard cert server)
                    if self.ca_cert_path:
                        expanded_ca_path = os.path.expanduser(self.ca_cert_path)
                        if os.path.exists(expanded_ca_path):
                            context.load_verify_locations(expanded_ca_path)
                            self.log(f"  ✓ Additional CA certificate loaded: {expanded_ca_path}")
                            self.log(f"  ℹ Mixed mode: SPIRE client can verify standard cert servers")
                        else:
                            self.log(f"  ⚠ CA certificate path not found: {expanded_ca_path}")
                            self.log(f"  ⚠ Server verification may fail for standard cert servers")
                    
                    context.verify_mode = ssl.CERT_REQUIRED  # Verify server certificate using trust bundle
                except Exception as e:
                    self.log(f"  ⚠ Error loading bundle into SSL context: {e}")
                    context.verify_mode = ssl.CERT_NONE  # Fallback: don't verify if bundle load fails
            else:
                # If no SPIRE bundle, try to use CA cert if provided
                if self.ca_cert_path and os.path.exists(self.ca_cert_path):
                    context.load_verify_locations(self.ca_cert_path)
                    context.verify_mode = ssl.CERT_REQUIRED
                    self.log(f"  ✓ CA certificate loaded for server verification: {self.ca_cert_path}")
                else:
                    self.log(f"  ⚠ No bundle path available, using CERT_NONE (no peer verification)")
                    context.verify_mode = ssl.CERT_NONE  # Don't verify if no bundle
            
            # Load certificate chain (leaf + intermediates)
            # The Unified Identity extension is in the intermediate certificate (agent SVID)
            from cryptography.hazmat.primitives import serialization
            cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM)
            
            # SPIRE X509Source provides the full chain via the underlying workload API
            # The chain includes: workload SVID (leaf) + agent SVID (intermediate)
            # Check if svid has a chain attribute or if we need to get it from the source
            try:
                # Try to get the full chain from the source's underlying data
                # The python-spiffe library may store intermediates separately
                if hasattr(self.source, '_x509_svid') and self.source._x509_svid:
                    x509_svid = self.source._x509_svid
                    # Check if there are additional certificates in the chain
                    if hasattr(x509_svid, 'cert_chain') and x509_svid.cert_chain:
                        for cert in x509_svid.cert_chain:
                            if cert != svid.leaf:
                                cert_pem += cert.public_bytes(serialization.Encoding.PEM)
                    # Alternative: check for intermediates in the raw response
                    elif hasattr(x509_svid, 'certificates') and x509_svid.certificates:
                        for cert in x509_svid.certificates[1:]:  # Skip first (leaf)
                            cert_pem += cert.public_bytes(serialization.Encoding.PEM)
            except Exception as e:
                # If we can't get intermediates, log but continue with leaf only
                # The WASM filter will check what's available in the chain
                self.log(f"  ⚠ Could not extract intermediate certificates: {e}")
                self.log(f"  ℹ Note: Unified Identity extension should be in intermediate cert")
            
            key_pem = svid.private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            )
            
            import tempfile
            with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as cert_file:
                cert_file.write(cert_pem)
                cert_file.write(key_pem)
                cert_path = cert_file.name
            
            context.load_cert_chain(cert_path)
            os.unlink(cert_path)
            
            return context
            
        except Exception as e:
            self.log(f"Error setting up TLS context: {e}")
            import traceback
            traceback.print_exc()
            raise
    
    def _detect_peer_cert_type(self, tls_socket):
        """Detect if peer certificate is SPIRE-issued or standard."""
        try:
            # Get server certificate
            cert_der = tls_socket.getpeercert_chain()[0] if hasattr(tls_socket, 'getpeercert_chain') else None
            if not cert_der:
                # Try alternative method
                cert_der = tls_socket.getpeercert(binary_form=True)
            
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
    
    def check_renewal(self):
        """Check if SVID was renewed (SPIRE mode only)."""
        if not self.use_spire:
            return False  # No renewal in standard cert mode
        
        try:
            new_svid = self.source.svid
            if new_svid and self.last_svid_serial:
                if new_svid.leaf.serial_number != self.last_svid_serial:
                    # Detected a new SVID (renewal event)
                    old_serial = self.last_svid_serial
                    new_serial = new_svid.leaf.serial_number
                    new_expiry = new_svid.leaf.not_valid_after

                    self.renewal_count += 1
                    self.last_svid_serial = new_serial

                    # Log a single concise line per renewal
                    self.log(
                        f"SVID renewed #{self.renewal_count}: "
                        f"serial {old_serial} -> {new_serial}, expires {new_expiry}, "
                        f"id={new_svid.spiffe_id}"
                    )

                    # Signal that the current connection should be rebuilt
                    return True
            elif new_svid:
                    self.last_svid_serial = new_svid.leaf.serial_number
        except Exception as e:
            if self.running:
                self.log(f"Error checking renewal: {e}")
        return False
    
    def check_svid_expired(self):
        """Check if current SVID is expired or about to expire (SPIRE mode only)."""
        if not self.use_spire or not self.source:
            return False
        
        try:
            svid = self.source.svid
            if not svid:
                return False
            
            # Get expiration time (handle both naive and timezone-aware datetimes)
            expiry = svid.leaf.not_valid_after_utc if hasattr(svid.leaf, 'not_valid_after_utc') else svid.leaf.not_valid_after
            if expiry.tzinfo is None:
                # Naive datetime - assume UTC
                expiry = expiry.replace(tzinfo=timezone.utc)
            
            now = datetime.now(timezone.utc)
            
            # Check if expired or expires within next 10 seconds (more buffer for proactive refresh)
            time_until_expiry = (expiry - now).total_seconds()
            if expiry <= now:
                # SVID is expired - need to refresh immediately
                self.log(f"⚠️  SVID expired at {expiry}, refreshing context...")
                return True
            elif time_until_expiry < 10:
                # SVID expires soon - refresh proactively
                self.log(f"⚠️  SVID expires in {time_until_expiry:.1f}s ({expiry}), refreshing context proactively...")
                return True
        except Exception as e:
            if self.running:
                self.log(f"Error checking SVID expiration: {e}")
        return False
    
    def connect_and_communicate(self, context, interval=2):
        """Connect to server and send periodic messages."""
        self.log(f"Connecting to {self.server_host}:{self.server_port}...")
        
        while self.running:
            try:
                # Check for renewal before connecting
                if self.check_renewal():
                    # DEMO: Show TLS context recreation
                    self.log("  🔧 Recreating TLS context with renewed SVID...")
                    context = self.setup_tls_context()
                    self.log("  ✓ TLS context recreated successfully")
                    self.log("  🔌 Reconnecting to server with new certificate...")
                # Also check if SVID is expired or about to expire
                elif self.check_svid_expired():
                    # SVID expired - refresh context proactively
                    self.log("  🔧 Recreating TLS context (SVID expired/expiring)...")
                    # Close old source if it exists to force fresh SVID fetch
                    if self.source:
                        try:
                            self.source.close()
                        except:
                            pass
                    context = self.setup_tls_context()
                    self.log("  ✓ TLS context recreated successfully")
                    # Small delay to ensure new SVID is fully loaded
                    time.sleep(0.5)
                    self.log("  🔌 Reconnecting to server with refreshed certificate...")
                
                # Create socket
                client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                
                # Wrap with TLS and connect
                tls_socket = context.wrap_socket(client_socket, server_hostname=self.server_host)
                tls_socket.connect((self.server_host, self.server_port))
                
                # Detect and log server certificate type (only once per connection session)
                if not hasattr(self, '_server_cert_logged'):
                    server_cert_type = self._detect_peer_cert_type(tls_socket)
                    if server_cert_type:
                        if server_cert_type == 'standard' and self.use_spire:
                            self.log(f"  ℹ Mixed mode detected: Server using standard certificate, Client using SPIRE certificate")
                            if not self.ca_cert_path:
                                self.log(f"  ⚠ Warning: Server verification may fail without CA_CERT_PATH")
                                self.log(f"  ℹ Provide server's CA via CA_CERT_PATH for proper verification")
                            else:
                                self.log(f"  ✓ Server CA provided - verification should succeed")
                        elif server_cert_type == 'SPIRE' and not self.use_spire:
                            self.log(f"  ℹ Mixed mode detected: Server using SPIRE certificate, Client using standard certificate")
                            self.log(f"  ℹ This is supported - client can connect to SPIRE servers")
                        else:
                            self.log(f"  ℹ Server certificate type: {server_cert_type} (matches client mode)")
                    self._server_cert_logged = True
                
                # Log connection appropriately
                if not self._first_connection_logged:
                    self.log("✓ Connected to server")
                    self._first_connection_logged = True
                    # Reset renewal flag on first connection
                    self._reconnect_due_to_renewal = False
                elif self._reconnect_due_to_renewal:
                    # Log reconnection when it's due to certificate renewal (important event)
                    self.log("  ✓ Reconnected to server (certificate renewal)")
                    self._reconnect_due_to_renewal = False  # Reset immediately after logging
                # All other reconnections (normal connection closures) are silent for stability
                # Also reset renewal flag for normal reconnections to prevent false positives
                else:
                    self._reconnect_due_to_renewal = False
                
                # Send periodic messages
                message_num = 0
                last_response_received = False  # Track if last request got a response
                connection_active = True  # Track if connection is active and ready for messages
                
                while self.running:
                    try:
                        # Only send messages if connection is active
                        if not connection_active:
                            # Connection is not active - wait a bit and reconnect
                            time.sleep(0.5)
                            break  # Exit inner loop to reconnect
                        
                        # Check for renewal periodically
                        if self.check_renewal():
                            # Renewal detected during active connection
                            if self.renewal_count > self.last_logged_renewal_id:
                                self.last_logged_renewal_id = self.renewal_count
                                self.log(
                                    f"SVID renewed #{self.renewal_count} during active connection; "
                                    "closing and reconnecting with new certificate"
                                )
                            # Mark that reconnection is due to renewal (will be logged on reconnect)
                            self._reconnect_due_to_renewal = True
                            # Mark connection as inactive
                            connection_active = False
                            # Close current connection to force reconnection with new cert
                            try:
                                tls_socket.shutdown(socket.SHUT_RDWR)
                            except:
                                pass
                            try:
                                tls_socket.close()
                            except:
                                pass
                            break  # Exit inner loop to reconnect
                        # Also check if SVID expired during active connection
                        elif self.check_svid_expired():
                            # SVID expired during active connection - close and refresh
                            if self.renewal_count > self.last_logged_renewal_id:
                                self.last_logged_renewal_id = self.renewal_count
                                self.log(
                                    f"SVID expired during active connection; "
                                    "closing and reconnecting with refreshed certificate"
                                )
                            # Mark that reconnection is due to renewal/expiration (will be logged on reconnect)
                            self._reconnect_due_to_renewal = True
                            # Mark connection as inactive
                            connection_active = False
                            # Close current connection to force reconnection with refreshed cert
                            try:
                                tls_socket.shutdown(socket.SHUT_RDWR)
                            except:
                                pass
                            try:
                                tls_socket.close()
                            except:
                                pass
                            break  # Exit inner loop to reconnect
                        
                        message_num += 1
                        self.message_count += 1
                        
                        # Send HTTP request
                        message = f"HELLO #{self.message_count}"
                        http_request = (
                            f"GET /hello HTTP/1.1\r\n"
                            f"Host: {self.server_host}:{self.server_port}\r\n"
                            f"User-Agent: mTLS-Client/1.0\r\n"
                            f"X-Message: {message}\r\n"
                            f"Connection: keep-alive\r\n"
                            f"\r\n"
                        )
                        # Verify connection is still active before sending
                        try:
                            # Quick check if socket is still connected
                            tls_socket.getpeername()
                        except (OSError, AttributeError):
                            # Connection is not active - mark as inactive and reconnect
                            connection_active = False
                            break  # Exit inner loop to reconnect
                        
                        self.log(f"📤 Sending HTTP request: {message}")
                        try:
                            tls_socket.sendall(http_request.encode('utf-8'))
                        except (ssl.SSLError, ConnectionError, BrokenPipeError) as e:
                            # EOF or connection error during send - connection likely closed by server
                            # Mark connection as inactive
                            connection_active = False
                            err_str = str(e)
                            is_eof_error = "EOF" in err_str or "eof" in err_str.lower()
                            # Only log if it's clearly not a normal closure (not EOF)
                            if not is_eof_error:
                                self.log(f"Connection error during send: {err_str}")
                            # Reconnect silently for EOF (normal closure)
                            self.reconnect_count += 1
                            try:
                                tls_socket.close()
                            except:
                                pass
                            break  # Reconnect
                        
                        # Receive HTTP response
                        response_received = False
                        try:
                            response_data = b""
                            connection_closed_by_server = False
                            while True:
                                chunk = tls_socket.recv(4096)
                                if not chunk:
                                    # Server closed connection
                                    connection_closed_by_server = True
                                    break
                                response_data += chunk
                                # Check if we've received the full HTTP response
                                if b"\r\n\r\n" in response_data:
                                    # Try to read body if Content-Length is specified
                                    headers_end = response_data.find(b"\r\n\r\n")
                                    headers = response_data[:headers_end].decode('utf-8', errors='replace')
                                    body_start = headers_end + 4
                                    
                                    # Check for Connection header to see if server wants to close
                                    connection_header = None
                                    for line in headers.split('\r\n'):
                                        if line.lower().startswith('connection:'):
                                            connection_header = line.split(':', 1)[1].strip().lower()
                                            break
                                    
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
                                        body_received = len(response_data) - body_start
                                        if body_received >= content_length:
                                            response_received = True
                                            break
                                    else:
                                        # No Content-Length, assume response is complete
                                        response_received = True
                                        break
                                    
                                    # If server sent Connection: close, mark for reconnection
                                    if connection_header == 'close':
                                        connection_closed_by_server = True
                            
                            if response_data:
                                response_text = response_data.decode('utf-8', errors='replace')
                                # Extract body from HTTP response
                                if "\r\n\r\n" in response_text:
                                    body = response_text.split("\r\n\r\n", 1)[1]
                                    self.log(f"📥 Received HTTP response: {body.strip()}")
                                else:
                                    self.log(f"📥 Received: {response_text[:200]}")
                                last_response_received = True  # Successfully received response
                            
                            # If server closed connection, break to reconnect silently
                            # This is normal HTTP behavior - no logging needed
                            if connection_closed_by_server:
                                last_response_received = True  # We got a response before closure
                                connection_active = False  # Mark connection as inactive
                                try:
                                    tls_socket.close()
                                except:
                                    pass
                                break  # Exit inner loop to reconnect (silent - normal behavior)
                        except ssl.SSLError as e:
                            err_str = str(e)
                            if "certificate" in err_str.lower() or "renewal" in err_str.lower():
                                # Concise log once per renewal event
                                if self.renewal_count > self.last_logged_renewal_id:
                                    self.last_logged_renewal_id = self.renewal_count
                                    self.log(
                                        f"TLS error during SVID renewal (will reconnect): "
                                        f"{err_str[:120]}"
                                    )
                                # Mark that reconnection is due to renewal (will be logged on reconnect)
                                self._reconnect_due_to_renewal = True
                                connection_active = False  # Mark connection as inactive
                                raise  # Reconnect
                            else:
                                # Non-renewal TLS error - already logged above, reconnect silently
                                raise
                        except (ConnectionError, BrokenPipeError) as e:
                            # Only set had_previous_connection if we didn't receive a complete response
                            # If we got a complete response, this is just normal connection closure
                            if not response_received:
                                # Connection closed before response - log error
                                if "renewal" in str(e).lower() or self.renewal_count > 0:
                                    self.log(f"  ⚠️  Connection closed (renewal blip): {e}")
                                else:
                                    self.log(f"Connection closed before response: {e}")
                            # Otherwise, normal closure after successful response - silent reconnect
                            raise  # Reconnect (silently if response was received)
                        
                        # Wait before next message
                        time.sleep(interval)
                        
                    except (ssl.SSLError, ConnectionError, BrokenPipeError) as e:
                        # Reconnection due to error
                        err_str = str(e)
                        is_eof_error = "EOF" in err_str or "eof" in err_str.lower()
                        
                        # Only log if we didn't receive a response (actual error)
                        # If we got a response, the error is during cleanup - silent reconnect
                        if not last_response_received:
                            # Check if this is renewal-related
                            if self.renewal_count > 0 and (
                                "certificate" in err_str.lower()
                                or "renewal" in err_str.lower()
                                or "unknown ca" in err_str.lower()
                            ):
                                # Only log once per renewal cycle
                                if self.renewal_count > self.last_logged_renewal_id:
                                    self.last_logged_renewal_id = self.renewal_count
                                    self.log(
                                        f"Renewal blip: reconnecting after TLS error: "
                                        f"{err_str[:120]}"
                                    )
                                # Mark that reconnection is due to renewal (will be logged on reconnect)
                                self._reconnect_due_to_renewal = True
                            elif is_eof_error:
                                # EOF errors are common and often normal (server closes connections)
                                # Don't log them - they're usually just normal connection closures
                                # Silent reconnect for all EOF errors
                                pass
                            else:
                                # Non-renewal, non-EOF error - log it
                                self.log(f"Connection error: {err_str}")
                        # If we got a response, any error (including EOF) is normal closure - silent reconnect
                        # Mark connection as inactive
                        connection_active = False
                        # Always increment reconnect count and reset response flag
                        self.reconnect_count += 1
                        last_response_received = False  # Reset for next connection
                        try:
                            tls_socket.close()
                        except:
                            pass
                        break  # Reconnect (silently if response was received or normal EOF)
                    except Exception as e:
                        # Unexpected error - log it
                        self.log(f"Error in communication: {e}")
                        try:
                            tls_socket.close()
                        except:
                            pass
                        break  # Reconnect (error already logged)
                
                try:
                    tls_socket.close()
                except:
                    pass
                
            except (ConnectionRefusedError, OSError) as e:
                self.log(f"Connection failed: {e}")
                self.log("Waiting before retry...")
                time.sleep(5)
            except Exception as e:
                self.log(f"Error connecting: {e}")
                time.sleep(5)
    
    def run(self):
        """Run the mTLS client."""
        self.log("")
        if self.use_spire:
            self.log("╔════════════════════════════════════════════════════════════════╗")
            self.log("║  mTLS Client Starting with SPIRE SVID (Automatic Renewal)      ║")
            self.log("╚════════════════════════════════════════════════════════════════╝")
            self.log(f"SPIRE Agent socket: {self.socket_path}")
        else:
            self.log("╔════════════════════════════════════════════════════════════════╗")
            self.log("║  mTLS Client Starting with Standard Certificates               ║")
            self.log("╚════════════════════════════════════════════════════════════════╝")
        self.log(f"Server: {self.server_host}:{self.server_port}")
        self.log("")
        
        try:
            # Setup TLS context with SPIRE SVID
            context = self.setup_tls_context()
            
            # Connect and communicate
            self.connect_and_communicate(context)
            
        except KeyboardInterrupt:
            self.log("Interrupted by user")
        except Exception as e:
            self.log(f"Client error: {e}")
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
            self.log("Client shutting down...")
            self.log(f"Total renewals detected: {self.renewal_count}")
            self.log(f"Total messages sent: {self.message_count}")
            self.log(f"Total reconnects: {self.reconnect_count}")

def main():
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    server_host = os.environ.get('SERVER_HOST', 'localhost')
    server_port = int(os.environ.get('SERVER_PORT', '9443'))
    log_file = os.environ.get('CLIENT_LOG', '/tmp/mtls-client-app.log')
    
    # Certificate mode configuration
    use_spire_env = os.environ.get('CLIENT_USE_SPIRE', '').lower()
    if use_spire_env == 'true' or use_spire_env == '1':
        use_spire = True
    elif use_spire_env == 'false' or use_spire_env == '0':
        use_spire = False
    else:
        use_spire = None  # Auto-detect
    
    # Standard cert paths (optional) - expand ~ in paths
    client_cert_path = os.environ.get('CLIENT_CERT_PATH')
    if client_cert_path:
        client_cert_path = os.path.expanduser(client_cert_path)
    client_key_path = os.environ.get('CLIENT_KEY_PATH')
    if client_key_path:
        client_key_path = os.path.expanduser(client_key_path)
    ca_cert_path = os.environ.get('CA_CERT_PATH')
    if ca_cert_path:
        ca_cert_path = os.path.expanduser(ca_cert_path)
    
    client = SPIREmTLSClient(
        socket_path,
        server_host,
        server_port,
        log_file,
        use_spire=use_spire,
        client_cert_path=client_cert_path,
        client_key_path=client_key_path,
        ca_cert_path=ca_cert_path
    )
    client.run()

if __name__ == '__main__':
    main()

