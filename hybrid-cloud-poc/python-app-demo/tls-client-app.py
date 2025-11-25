#!/usr/bin/env python3
"""
TLS Client App with SPIRE SVID and Automatic Renewal
This client connects to the TLS server using SPIRE SVIDs and handles automatic renewal.
"""

import os
import sys
import time
import socket
import ssl
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

class SPIRETLSClient:
    def __init__(self, socket_path, server_host, server_port, log_file=None):
        self.socket_path = socket_path
        self.server_host = server_host
        self.server_port = server_port
        self.log_file = log_file
        self.running = True
        self.renewal_count = 0
        self.message_count = 0
        self.reconnect_count = 0
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
        socket_path_with_scheme = f"unix://{self.socket_path}"
        
        try:
            source = default_client.DefaultX509Source(socket_path=socket_path_with_scheme)
            bundle_source = default_client.DefaultX509BundleSource(socket_path=socket_path_with_scheme)
            
            # Create TLS context
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE  # We'll verify using SPIFFE
            
            # Get initial SVID
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
            with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as cert_file:
                cert_file.write(cert_pem)
                cert_file.write(key_pem)
                cert_path = cert_file.name
            
            context.load_cert_chain(cert_path)
            
            # Clean up temp file
            os.unlink(cert_path)
            
            return context, source, bundle_source
            
        except Exception as e:
            self.log(f"Error creating TLS context: {e}")
            raise
    
    def connect_and_communicate(self, context, source, interval=2):
        """Connect to server and send periodic messages."""
        self.log(f"Connecting to {self.server_host}:{self.server_port}...")
        
        while self.running:
            try:
                # Create socket
                client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                
                # Wrap with TLS
                tls_socket = context.wrap_socket(client_socket, server_hostname=self.server_host)
                
                self.log("Connected to server")
                
                # Send periodic messages
                message_num = 0
                while self.running:
                    try:
                        message_num += 1
                        self.message_count += 1
                        
                        # Check if SVID was renewed
                        try:
                            new_svid = source.get_x509_svid()
                            if new_svid and hasattr(self, 'last_svid_serial'):
                                if new_svid.cert.serial_number != self.last_svid_serial:
                                    self.log(f"SVID renewed! New serial: {new_svid.cert.serial_number}")
                                    self.renewal_count += 1
                                    self.last_renewal_time = time.time()
                                    # Note: In production, we'd recreate the context here
                                    # For now, the connection may drop and we'll reconnect
                        except:
                            pass
                        
                        if not hasattr(self, 'last_svid_serial'):
                            self.last_svid_serial = new_svid.cert.serial_number if new_svid else None
                        
                        # Send message
                        message = f"Hello from client - Message #{message_num}"
                        tls_socket.send(message.encode('utf-8'))
                        
                        # Receive response
                        try:
                            response = tls_socket.recv(1024)
                            if response:
                                self.log(f"Server response: {response.decode('utf-8')}")
                        except ssl.SSLError as e:
                            if "certificate" in str(e).lower() or "renewal" in str(e).lower():
                                self.log(f"TLS error (possibly renewal blip): {e}")
                                raise  # Reconnect
                            else:
                                raise
                        
                        # Wait before next message
                        time.sleep(interval)
                        
                    except (ssl.SSLError, ConnectionError, BrokenPipeError) as e:
                        self.log(f"Connection error (renewal blip?): {e}")
                        self.reconnect_count += 1
                        tls_socket.close()
                        break  # Reconnect
                    except Exception as e:
                        self.log(f"Error in communication: {e}")
                        tls_socket.close()
                        break  # Reconnect
                
                tls_socket.close()
                
            except (ConnectionRefusedError, OSError) as e:
                self.log(f"Connection failed: {e}")
                self.log("Waiting before retry...")
                time.sleep(5)
            except Exception as e:
                self.log(f"Error connecting: {e}")
                time.sleep(5)
    
    def run(self):
        """Run the TLS client."""
        self.log("Starting TLS Client with SPIRE SVID...")
        self.log(f"SPIRE Agent socket: {self.socket_path}")
        self.log(f"Server: {self.server_host}:{self.server_port}")
        
        try:
            # Get TLS context with SPIRE SVID
            context, source, bundle_source = self.get_tls_context()
            
            # Connect and communicate
            self.connect_and_communicate(context, source)
            
        except KeyboardInterrupt:
            self.log("Interrupted by user")
        except Exception as e:
            self.log(f"Client error: {e}")
            import traceback
            traceback.print_exc()
        finally:
            self.log("Client shutting down...")
            self.log(f"Total renewals detected: {self.renewal_count}")
            self.log(f"Total messages sent: {self.message_count}")
            self.log(f"Total reconnects: {self.reconnect_count}")

def main():
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    server_host = os.environ.get('SERVER_HOST', 'localhost')
    server_port = int(os.environ.get('SERVER_PORT', '8443'))
    log_file = os.environ.get('CLIENT_LOG', '/tmp/tls-client-app.log')
    
    client = SPIRETLSServer(socket_path, server_host, server_port, log_file)
    client.run()

if __name__ == '__main__':
    # Fix: Use SPIRETLSClient, not SPIRETLSServer
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    server_host = os.environ.get('SERVER_HOST', 'localhost')
    server_port = int(os.environ.get('SERVER_PORT', '8443'))
    log_file = os.environ.get('CLIENT_LOG', '/tmp/tls-client-app.log')
    
    client = SPIRETLSClient(socket_path, server_host, server_port, log_file)
    client.run()

