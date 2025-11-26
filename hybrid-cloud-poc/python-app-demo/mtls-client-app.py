#!/usr/bin/env python3
"""
mTLS Client App with SPIRE SVID and Automatic Renewal
This client connects to the mTLS server using SPIRE SVIDs and automatically renews when agent SVID renews.
"""

import os
import sys
import time
import socket
import ssl
import signal
from pathlib import Path

try:
    from spiffe.workloadapi.x509_source import X509Source
    HAS_SPIFFE = True
except ImportError:
    print("Error: spiffe library not installed")
    print("Install it with: pip install spiffe")
    sys.exit(1)

class SPIREmTLSClient:
    def __init__(self, socket_path, server_host, server_port, log_file=None):
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
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            
            # Load trust bundle for peer verification
            if self.bundle_path:
                try:
                    context.load_verify_locations(self.bundle_path)
                    context.verify_mode = ssl.CERT_REQUIRED  # Verify server certificate using trust bundle
                    self.log(f"  ✓ Trust bundle loaded into SSL context")
                except Exception as e:
                    self.log(f"  ⚠ Error loading bundle into SSL context: {e}")
                    context.verify_mode = ssl.CERT_NONE  # Fallback: don't verify if bundle load fails
            else:
                self.log(f"  ⚠ No bundle path available, using CERT_NONE (no peer verification)")
                context.verify_mode = ssl.CERT_NONE  # Don't verify if no bundle
            
            # Load initial certificate
            from cryptography.hazmat.primitives import serialization
            cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM)
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
    
    def check_renewal(self):
        """Check if SVID was renewed."""
        try:
            new_svid = self.source.svid
            if new_svid and self.last_svid_serial:
                if new_svid.leaf.serial_number != self.last_svid_serial:
                    # DEMO: Show renewal blip clearly
                    old_serial = self.last_svid_serial
                    new_serial = new_svid.leaf.serial_number
                    new_expiry = new_svid.leaf.not_valid_after
                    
                    self.log("")
                    self.log("╔════════════════════════════════════════════════════════════════╗")
                    self.log("║  🔄 SVID RENEWAL DETECTED - RENEWAL BLIP EVENT                  ║")
                    self.log("╚════════════════════════════════════════════════════════════════╝")
                    self.log(f"  Old Certificate Serial: {old_serial}")
                    self.log(f"  New Certificate Serial: {new_serial}")
                    self.log(f"  New Certificate Expires: {new_expiry}")
                    self.log(f"  SPIFFE ID: {new_svid.spiffe_id}")
                    self.log("  ⚠️  RENEWAL BLIP: Current connection will be re-established")
                    self.log("  ✓  Reconnecting with renewed certificate...")
                    self.log("")
                    
                    self.renewal_count += 1
                    self.last_svid_serial = new_svid.leaf.serial_number
                    # DEMO: Signal that connection should be closed for renewal blip
                    return True
            elif new_svid:
                    self.last_svid_serial = new_svid.leaf.serial_number
        except Exception as e:
            if self.running:
                self.log(f"Error checking renewal: {e}")
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
                
                # Create socket
                client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                
                # Wrap with TLS and connect
                tls_socket = context.wrap_socket(client_socket, server_hostname=self.server_host)
                tls_socket.connect((self.server_host, self.server_port))
                
                # DEMO: Show successful connection (especially after renewal)
                if self.reconnect_count > 0:
                    self.log("  ✓ Reconnected to server successfully (renewal blip resolved)")
                else:
                    self.log("✓ Connected to server")
                
                # Send periodic messages
                message_num = 0
                while self.running:
                    try:
                        # Check for renewal periodically
                        if self.check_renewal():
                            # DEMO: Show renewal detected during active connection
                            self.log("  ⚠️  SVID renewed during active connection!")
                            self.log("  ⚠️  RENEWAL BLIP: Current connection will close and reconnect")
                            self.log("  🔄 Closing current connection to use renewed certificate...")
                            # Close current connection to force reconnection with new cert (renewal blip)
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
                        
                        # Send message
                        message = f"HELLO #{message_num}"
                        self.log(f"📤 Sending: {message}")
                        tls_socket.sendall(message.encode('utf-8'))
                        
                        # Receive response
                        try:
                            response = tls_socket.recv(1024)
                            if response:
                                self.log(f"📥 Received: {response.decode('utf-8')}")
                        except ssl.SSLError as e:
                            if "certificate" in str(e).lower() or "renewal" in str(e).lower():
                                # DEMO: Show renewal blip in action
                                self.log("")
                                self.log("  ⚠️  RENEWAL BLIP: TLS error detected (certificate renewal)")
                                self.log(f"     Error: {str(e)[:100]}")
                                self.log("     Connection will be re-established with renewed certificate...")
                                self.log("")
                                raise  # Reconnect
                            else:
                                raise
                        except (ConnectionError, BrokenPipeError) as e:
                            # DEMO: Show connection closure (may be due to renewal)
                            if "renewal" in str(e).lower() or self.renewal_count > 0:
                                self.log(f"  ⚠️  Connection closed (renewal blip): {e}")
                            else:
                                self.log(f"Connection closed: {e}")
                            raise  # Reconnect
                        
                        # Wait before next message
                        time.sleep(interval)
                        
                    except (ssl.SSLError, ConnectionError, BrokenPipeError) as e:
                        # DEMO: Show reconnection due to renewal blip
                        if self.renewal_count > 0:
                            self.log("")
                            self.log("  🔄 RENEWAL BLIP: Reconnecting due to certificate renewal...")
                            self.log(f"     Reason: {str(e)[:80]}")
                            self.log("     This is expected behavior during SVID renewal")
                            self.log("")
                        else:
                            self.log(f"Connection error: {e}")
                        self.reconnect_count += 1
                        try:
                            tls_socket.close()
                        except:
                            pass
                        break  # Reconnect
                    except Exception as e:
                        self.log(f"Error in communication: {e}")
                        try:
                            tls_socket.close()
                        except:
                            pass
                        break  # Reconnect
                
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
        self.log("╔════════════════════════════════════════════════════════════════╗")
        self.log("║  mTLS Client Starting with Automatic SVID Renewal              ║")
        self.log("╚════════════════════════════════════════════════════════════════╝")
        self.log(f"SPIRE Agent socket: {self.socket_path}")
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
    
    client = SPIREmTLSClient(socket_path, server_host, server_port, log_file)
    client.run()

if __name__ == '__main__':
    main()

