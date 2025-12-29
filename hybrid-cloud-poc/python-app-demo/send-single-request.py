#!/usr/bin/env python3

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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

    # Handle CA flag validation warning (same as mtls-client-app.py)
    try:
        source = X509Source(socket_path=socket_path_with_scheme)
    except Exception as e:
        error_msg = str(e)
        if "CA flag" in error_msg or "intermediate certificate" in error_msg:
            # Workaround for strict validation: monkey-patch the validation function
            try:
                from spiffe.svid import x509_svid
                original_validate = x509_svid._validate_intermediate_certificate
                def patched_validate(cert):
                    pass  # Skip CA flag validation
                x509_svid._validate_intermediate_certificate = patched_validate
                source = X509Source(socket_path=socket_path_with_scheme)
                x509_svid._validate_intermediate_certificate = original_validate
            except Exception as e2:
                raise Exception(f"Failed to create X509Source: {e2}")
        else:
            raise

    # Get SVID (X509Source uses .svid property)
    svid = source.svid
    if not svid:
        print("ERROR: Failed to get SVID from SPIRE agent")
        sys.exit(1)

    # Create SSL context
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False

    # Get trust bundle for server verification
    trust_domain = svid.spiffe_id.trust_domain
    bundle = None
    try:
        time.sleep(0.5)  # Wait a moment for bundle to be available

        if hasattr(source, 'get_bundle_for_trust_domain'):
            bundle = source.get_bundle_for_trust_domain(trust_domain)
        elif hasattr(source, 'get_bundle'):
            bundle = source.get_bundle(trust_domain)
    except Exception as e:
        pass  # Bundle not critical for single request

    # Load trust bundle if available
    if bundle:
        try:
            from cryptography.hazmat.primitives import serialization
            x509_authorities = bundle.x509_authorities
            if x509_authorities and len(x509_authorities) > 0:
                bundle_pem = b""
                for cert in x509_authorities:
                    bundle_pem += cert.public_bytes(serialization.Encoding.PEM)

                bundle_path = None
                try:
                    with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as bundle_file:
                        bundle_file.write(bundle_pem)
                        bundle_path = bundle_file.name

                    context.load_verify_locations(bundle_path)
                    context.verify_mode = ssl.CERT_REQUIRED
                finally:
                    # Always clean up temporary bundle file, even if load_verify_locations fails
                    if bundle_path and os.path.exists(bundle_path):
                        try:
                            os.unlink(bundle_path)
                        except Exception:
                            pass  # Ignore errors during cleanup
        except Exception as e:
            context.verify_mode = ssl.CERT_NONE

    # Also try to load additional CA cert if provided
    ca_cert_path = os.environ.get('CA_CERT_PATH', '~/.mtls-demo/envoy-cert.pem')
    if ca_cert_path:
        expanded_ca_path = os.path.expanduser(ca_cert_path)
        if os.path.exists(expanded_ca_path):
            try:
                context.load_verify_locations(expanded_ca_path)
                context.verify_mode = ssl.CERT_REQUIRED
            except Exception:
                pass

    # If no bundle or CA cert loaded, verify_mode is already CERT_NONE

    # Extract certificate and key from SVID
    from cryptography.hazmat.primitives import serialization
    import tempfile

    # Handle different svid object structures
    if hasattr(svid, 'leaf'):
        # X509Source returns svid with .leaf property
        cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM)
        private_key = svid.private_key
    elif hasattr(svid, 'cert'):
        # DefaultX509Source returns svid with .cert property
        cert_pem = svid.cert.public_bytes(serialization.Encoding.PEM)
        private_key = svid.private_key
    else:
        raise Exception("SVID object does not have expected certificate structure")

    # Try to get certificate chain (leaf + intermediates)
    try:
        if hasattr(source, '_x509_svid') and source._x509_svid:
            x509_svid = source._x509_svid
            if hasattr(x509_svid, 'cert_chain') and x509_svid.cert_chain:
                leaf_cert = svid.leaf if hasattr(svid, 'leaf') else svid.cert
                for cert in x509_svid.cert_chain:
                    if cert != leaf_cert:
                        cert_pem += cert.public_bytes(serialization.Encoding.PEM)
            elif hasattr(x509_svid, 'certificates') and x509_svid.certificates:
                for cert in x509_svid.certificates[1:]:  # Skip first (leaf)
                    cert_pem += cert.public_bytes(serialization.Encoding.PEM)
    except Exception:
        pass  # Chain not critical, continue with leaf only

    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )

    # Create temporary file with certificate and key
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
