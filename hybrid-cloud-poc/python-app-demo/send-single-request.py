#!/usr/bin/env python3
"""
Send a single HTTP request via mTLS using SPIRE SVID.
This is used for demos where we want to show a single, decodable request.
"""

import os
import sys
import socket
import ssl
import time

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from spiffe.workloadapi.x509_source import X509Source
    HAS_SPIFFE = True
except ImportError as e:
    HAS_SPIFFE = False
    print(f"ERROR: spiffe library not available: {e}")
    print("Install it with: pip install spiffe")
    sys.exit(1)

def get_tls_context():
    """Get TLS context with SPIRE SVID."""
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    
    if not HAS_SPIFFE:
        print("ERROR: spiffe library not available")
        sys.exit(1)
    
    if not os.path.exists(socket_path):
        print(f"ERROR: SPIRE agent socket not found: {socket_path}")
        sys.exit(1)
    
    # Add unix:// scheme if not present (required by X509Source)
    if not socket_path.startswith('unix://'):
        socket_path_with_scheme = f"unix://{socket_path}"
    else:
        socket_path_with_scheme = socket_path
    
    # Create X509Source (same as mtls-client-app.py)
    # X509Source expects socket_path keyword argument
    source = X509Source(socket_path=socket_path_with_scheme)
    
    # Get SVID (X509Source uses .svid property, not get_x509_svid() method)
    svid = source.svid
    if not svid:
        print("ERROR: Failed to get SVID from SPIRE agent")
        sys.exit(1)
    
    # Get trust bundle (X509Source uses .bundle property or get_bundle_for_trust_domain)
    # For simplicity, we'll use the svid's cert_file and key_file directly
    # The bundle is used for server verification
    
    # Create SSL context
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_REQUIRED
    
    # Load client certificate and key from SVID
    context.load_cert_chain(
        certfile=svid.cert_file,
        keyfile=svid.key_file
    )
    
    # Load CA certificate from bundle
    # X509Source provides bundles via get_bundle_for_trust_domain, but for simplicity
    # we can use the SPIRE bundle file if available, or skip server verification
    bundle_file = os.environ.get('SPIRE_BUNDLE_PATH', '/tmp/bundle.pem')
    if os.path.exists(bundle_file):
        context.load_verify_locations(cafile=bundle_file)
    else:
        # Try to get bundle from source (this may require trust domain)
        # For now, we'll skip strict server verification if bundle not found
        print(f"  Warning: SPIRE bundle not found at {bundle_file}, server verification may be limited")
    
    return context, source

def send_single_request(server_host, server_port):
    """Send a single HTTP request and display the response."""
    print(f"Connecting to {server_host}:{server_port}...")
    
    # Get TLS context
    try:
        context, source = get_tls_context()
    except Exception as e:
        print(f"ERROR: Failed to get TLS context: {e}")
        sys.exit(1)
    
    # Create socket and wrap with TLS
    client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # Set socket timeout to prevent hanging
    client_socket.settimeout(10)  # 10 second timeout
    tls_socket = context.wrap_socket(client_socket, server_hostname=server_host)
    
    try:
        print("  Attempting connection...")
        tls_socket.connect((server_host, server_port))
        print("✓ Connected to server")
        
        # Send single HTTP request
        http_request = (
            f"GET /hello HTTP/1.1\r\n"
            f"Host: {server_host}:{server_port}\r\n"
            f"User-Agent: mTLS-Client-Demo/1.0\r\n"
            f"X-Message: HELLO #1\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        )
        
        print(f"📤 Sending HTTP request:")
        print(http_request.replace('\r\n', '\n').replace('\r', '')[:200])
        
        tls_socket.sendall(http_request.encode('utf-8'))
        
        # Receive response (with timeout)
        print("📥 Waiting for response...")
        response_data = b""
        tls_socket.settimeout(5)  # 5 second timeout for receiving
        try:
            while True:
                chunk = tls_socket.recv(4096)
                if not chunk:
                    break
                response_data += chunk
                # Check if we've received the full response (HTTP headers + body)
                if b'\r\n\r\n' in response_data:
                    # Check if Content-Length is specified
                    headers = response_data.split(b'\r\n\r\n')[0]
                    if b'Content-Length:' in headers:
                        # Parse Content-Length and read body
                        for line in headers.split(b'\r\n'):
                            if line.startswith(b'Content-Length:'):
                                try:
                                    content_length = int(line.split(b':')[1].strip())
                                    if len(response_data) >= len(headers) + 4 + content_length:
                                        break
                                except ValueError:
                                    break
                    else:
                        # No Content-Length, assume response is complete
                        break
                # Limit response size to prevent memory issues
                if len(response_data) > 100000:  # 100KB limit
                    print("  (Response too large, truncating...)")
                    break
        except socket.timeout:
            print("  (Response timeout, but may have received partial response)")
        except Exception as e:
            print(f"  (Error receiving response: {e})")
        
        response = response_data.decode('utf-8', errors='ignore')
        print(f"✓ Received response:")
        print(response[:500])  # Show first 500 chars
        
        # Extract status code
        if 'HTTP/1.1' in response or 'HTTP/1.0' in response:
            status_line = response.split('\n')[0]
            print(f"\nStatus: {status_line.strip()}")
        
    except socket.timeout:
        print(f"ERROR: Connection timeout to {server_host}:{server_port}")
        print("  (Server may not be reachable or not responding)")
        sys.exit(1)
    except ConnectionRefusedError:
        print(f"ERROR: Connection refused to {server_host}:{server_port}")
        print("  (Server may not be running or port is incorrect)")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        try:
            tls_socket.close()
        except:
            pass
        if source:
            try:
                source.close()
            except:
                pass
    
    print("\n✓ Single request completed successfully")

if __name__ == '__main__':
    server_host = os.environ.get('SERVER_HOST', '10.1.0.10')
    server_port = int(os.environ.get('SERVER_PORT', '8080'))
    
    send_single_request(server_host, server_port)

