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

import tempfile
from cryptography.hazmat.primitives import serialization

try:
    from spiffe.workloadapi.x509_source import X509Source
    HAS_SPIFFE = True
except ImportError as e:
    HAS_SPIFFE = False
    print(f"ERROR: spiffe library not available: {e}")
    print("Install it with: pip install spiffe")
    sys.exit(1)

# Track temp files for cleanup
_temp_files = []

def get_tls_context():
    """Get TLS context with SPIRE SVID."""
    global _temp_files
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
    print(f"DEBUG: Initializing X509Source with socket: {socket_path_with_scheme}", flush=True)
    source = X509Source(socket_path=socket_path_with_scheme)
    
    # Get SVID (X509Source uses .svid property, not get_x509_svid() method)
    print("DEBUG: Source initialized. Fetching SVID from Workload API...", flush=True)
    svid = source.svid
    print(f"DEBUG: SVID fetch returned: {svid.spiffe_id if svid else 'None'}", flush=True)
    if not svid:
        print("ERROR: Failed to get SVID from SPIRE agent")
        sys.exit(1)
    
    # Serialize the certificate and key to temporary files
    # py-spiffe X509Svid has .leaf (certificate) and .private_key (key crypto objects)
    # We need to serialize them to PEM files for ssl.load_cert_chain()
    
    # Serialize certificate chain (leaf + intermediates)
    cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM)
    if hasattr(svid, 'cert_chain') and svid.cert_chain:
        for intermediate in svid.cert_chain:
            cert_pem += intermediate.public_bytes(serialization.Encoding.PEM)
    
    # Serialize private key
    key_pem = svid.private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    
    # Write to temp files
    cert_file = tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem')
    cert_file.write(cert_pem)
    cert_file.close()
    _temp_files.append(cert_file.name)
    
    key_file = tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem')
    key_file.write(key_pem)
    key_file.close()
    _temp_files.append(key_file.name)
    
    print(f"DEBUG: Wrote certificate to {cert_file.name}", flush=True)
    print(f"DEBUG: Wrote key to {key_file.name}", flush=True)
    
    # Create SSL context
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_REQUIRED
    
    # Load client certificate and key from temp files
    context.load_cert_chain(
        certfile=cert_file.name,
        keyfile=key_file.name
    )
    
    # Load CA certificate from bundle
    # Try multiple bundle locations:
    # 1. Combined bundle (includes SPIRE CA + Envoy cert)
    # 2. SPIRE bundle from environment
    # 3. Default SPIRE bundle location
    bundle_candidates = [
        os.environ.get('CA_BUNDLE_PATH', ''),
        '/opt/envoy/certs/combined-ca-bundle.pem',  # Combined bundle with Envoy cert
        os.environ.get('SPIRE_BUNDLE_PATH', ''),
        '/tmp/spire-bundle.pem',
        '/tmp/bundle.pem',
    ]
    
    bundle_loaded = False
    for bundle_file in bundle_candidates:
        if bundle_file and os.path.exists(bundle_file):
            try:
                context.load_verify_locations(cafile=bundle_file)
                print(f"  Using CA bundle: {bundle_file}", flush=True)
                bundle_loaded = True
                break
            except Exception as e:
                print(f"  Warning: Failed to load bundle {bundle_file}: {e}", flush=True)
    
    if not bundle_loaded:
        # Skip server verification if no bundle found (for testing/demo)
        print(f"  Warning: No CA bundle found, disabling server verification", flush=True)
        context.verify_mode = ssl.CERT_NONE
    
    return context, source

def send_single_request(server_host, server_port):
    """Send a single HTTP request and display the response."""
    print(f"Connecting to {server_host}:{server_port}...", flush=True)
    status_code = 0  # Track HTTP status code for final message
    
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
        
        # Extract and validate status code
        status_code = 0
        if 'HTTP/1.1' in response or 'HTTP/1.0' in response:
            status_line = response.split('\n')[0].strip()
            print(f"\nStatus: {status_line}")
            # Parse status code (e.g., "HTTP/1.1 200 OK" -> 200)
            try:
                status_code = int(status_line.split()[1])
            except (IndexError, ValueError):
                print("ERROR: Failed to parse HTTP status code")
                status_code = 0
        
        # Check if response is successful (2xx)
        if status_code < 200 or status_code >= 300:
            print(f"\nERROR: Request failed with status {status_code}")
            if status_code == 403:
                print("  Hint: '403 Forbidden - Client certificate required' suggests mTLS issue:")
                print("    - Verify Envoy has the SPIRE CA bundle (/opt/envoy/certs/spire-bundle.pem)")
                print("    - Verify client certificate chain is complete")
                print("    - Check Envoy logs for TLS handshake errors")
            sys.exit(1)
        
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
        # Clean up temp files
        for temp_file in _temp_files:
            try:
                os.unlink(temp_file)
            except:
                pass
    
    print(f"\n✓ Single request completed successfully (HTTP {status_code})")

if __name__ == '__main__':
    server_host = os.environ.get('SERVER_HOST', '127.0.0.1')
    server_port = int(os.environ.get('SERVER_PORT', '8080'))
    
    send_single_request(server_host, server_port)

