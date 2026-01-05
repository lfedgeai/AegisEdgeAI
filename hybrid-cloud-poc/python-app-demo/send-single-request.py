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

Uses direct gRPC calls to SPIRE Agent Workload API (no python-spiffe dependency).
"""

import os
import sys
import socket
import ssl
import tempfile
import importlib.util
from pathlib import Path

# Simple SPIFFE ID class
class SimpleSpiffeId:
    """Simple SPIFFE ID parser."""
    def __init__(self, spiffe_id_str):
        self._str = spiffe_id_str
        if not spiffe_id_str.startswith('spiffe://'):
            raise ValueError(f"Invalid SPIFFE ID: {spiffe_id_str}")
        parts = spiffe_id_str[9:].split('/', 1)
        self.trust_domain = parts[0]
        self.path = '/' + parts[1] if len(parts) > 1 else '/'
    
    def __str__(self):
        return self._str

try:
    import grpc
    HAS_GRPC = True
except ImportError:
    print("ERROR: grpcio library not available")
    print("Install it with: pip install grpcio")
    sys.exit(1)

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
except ImportError:
    print("ERROR: cryptography library not available")
    print("Install it with: pip install cryptography")
    sys.exit(1)


def fetch_svid_via_grpc(socket_path):
    """Fetch SVID from SPIRE Agent via direct gRPC."""
    script_dir = Path(__file__).parent
    workload_pb2_path = script_dir / "generated" / "spiffe" / "workload" / "workload_pb2.py"
    workload_pb2_grpc_path = script_dir / "generated" / "spiffe" / "workload" / "workload_pb2_grpc.py"

    if not workload_pb2_path.exists() or not workload_pb2_grpc_path.exists():
        raise ImportError(f"Protobuf files not found: {workload_pb2_path}")

    spec_pb2 = importlib.util.spec_from_file_location("workload_pb2", workload_pb2_path)
    spec_grpc = importlib.util.spec_from_file_location("workload_pb2_grpc", workload_pb2_grpc_path)
    workload_pb2 = importlib.util.module_from_spec(spec_pb2)
    workload_pb2_grpc = importlib.util.module_from_spec(spec_grpc)
    spec_pb2.loader.exec_module(workload_pb2)
    spec_grpc.loader.exec_module(workload_pb2_grpc)

    abs_socket_path = socket_path.replace('unix://', '')
    channel = grpc.insecure_channel(f'unix:{abs_socket_path}')
    stub = workload_pb2_grpc.SpiffeWorkloadAPIStub(channel)
    grpc_metadata = [('workload.spiffe.io', 'true')]

    # Fetch SVID
    request = workload_pb2.X509SVIDRequest()
    response_stream = stub.FetchX509SVID(request, metadata=grpc_metadata, timeout=10)
    response = next(response_stream)

    if not response.svids:
        raise Exception("No SVIDs in response")

    svid_response = response.svids[0]

    # Parse certificates
    certs = []
    for cert_der in svid_response.x509_svid:
        cert = x509.load_der_x509_certificate(cert_der)
        certs.append(cert)

    if not certs:
        raise Exception("No certificates in SVID")

    # Parse private key
    key = serialization.load_der_private_key(svid_response.private_key, password=None)

    # Extract SPIFFE ID
    spiffe_id = None
    for ext in certs[0].extensions:
        if ext.oid._name == 'subjectAltName':
            for name in ext.value:
                if hasattr(name, 'value') and isinstance(name.value, str):
                    if name.value.startswith('spiffe://'):
                        spiffe_id = SimpleSpiffeId(name.value)
                        break

    # Simple SVID object
    class SimpleSVID:
        def __init__(self, certs, key, spiffe_id):
            self.leaf = certs[0]
            self.cert_chain = certs
            self.private_key = key
            self.spiffe_id = spiffe_id

    svid = SimpleSVID(certs, key, spiffe_id)

    # Fetch bundle
    bundle_request = workload_pb2.X509BundlesRequest()
    bundle_response_stream = stub.FetchX509Bundles(bundle_request, metadata=grpc_metadata, timeout=10)
    bundle_response = next(bundle_response_stream)

    bundle_certs = {}
    for trust_domain, bundle_der in bundle_response.bundles.items():
        bundle_cert = x509.load_der_x509_certificate(bundle_der)
        bundle_certs[trust_domain] = bundle_cert

    channel.close()
    return svid, bundle_certs


def get_tls_context():
    """Get TLS context with SPIRE SVID via direct gRPC."""
    socket_path = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')

    if not os.path.exists(socket_path):
        print(f"ERROR: SPIRE agent socket not found: {socket_path}")
        sys.exit(1)

    # Fetch SVID via gRPC
    svid, bundle_certs = fetch_svid_via_grpc(socket_path)
    if not svid:
        print("ERROR: Failed to get SVID from SPIRE agent")
        sys.exit(1)

    # Create SSL context
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False

    # Load trust bundle
    trust_domain = svid.spiffe_id.trust_domain
    bundle_cert = bundle_certs.get(trust_domain)
    bundle_path = None
    
    if bundle_cert:
        try:
            bundle_pem = bundle_cert.public_bytes(serialization.Encoding.PEM)
            with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as f:
                f.write(bundle_pem)
                bundle_path = f.name
            context.load_verify_locations(bundle_path)
            context.verify_mode = ssl.CERT_REQUIRED
        except Exception:
            context.verify_mode = ssl.CERT_NONE
        finally:
            if bundle_path and os.path.exists(bundle_path):
                try:
                    os.unlink(bundle_path)
                except Exception:
                    pass

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

    # Load certificate chain
    cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM)
    
    # Add agent SVID to chain
    if svid.cert_chain:
        for cert in svid.cert_chain:
            if cert != svid.leaf:
                cert_pem += cert.public_bytes(serialization.Encoding.PEM)

    key_pem = svid.private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )

    # Create temporary cert file
    cert_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem') as cert_file:
            cert_file.write(cert_pem)
            cert_file.write(key_pem)
            cert_path = cert_file.name
        context.load_cert_chain(cert_path)
    finally:
        if cert_path and os.path.exists(cert_path):
            try:
                os.unlink(cert_path)
            except Exception:
                pass

    return context


def send_single_request(server_host, server_port):
    """Send a single HTTP request and display the response."""
    print(f"Connecting to {server_host}:{server_port}...")

    try:
        context = get_tls_context()
    except Exception as e:
        print(f"ERROR: Failed to get TLS context: {e}")
        sys.exit(1)

    client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    client_socket.settimeout(10)
    tls_socket = context.wrap_socket(client_socket, server_hostname=server_host)

    try:
        print("  Attempting connection...")
        tls_socket.connect((server_host, server_port))
        print("✓ Connected to server")

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

        print("📥 Waiting for response...")
        response_data = b""
        tls_socket.settimeout(5)
        try:
            while True:
                chunk = tls_socket.recv(4096)
                if not chunk:
                    break
                response_data += chunk
                if b'\r\n\r\n' in response_data:
                    headers = response_data.split(b'\r\n\r\n')[0]
                    if b'Content-Length:' in headers:
                        for line in headers.split(b'\r\n'):
                            if line.startswith(b'Content-Length:'):
                                try:
                                    content_length = int(line.split(b':')[1].strip())
                                    if len(response_data) >= len(headers) + 4 + content_length:
                                        break
                                except ValueError:
                                    break
                    else:
                        break
                if len(response_data) > 100000:
                    print("  (Response too large, truncating...)")
                    break
        except socket.timeout:
            print("  (Response timeout, but may have received partial response)")
        except Exception as e:
            print(f"  (Error receiving response: {e})")

        response = response_data.decode('utf-8', errors='ignore')
        print(f"✓ Received response:")
        print(response[:500])

        if 'HTTP/1.1' in response or 'HTTP/1.0' in response:
            status_line = response.split('\n')[0]
            print(f"\nStatus: {status_line.strip()}")

    except socket.timeout:
        print(f"ERROR: Connection timeout to {server_host}:{server_port}")
        sys.exit(1)
    except ConnectionRefusedError:
        print(f"ERROR: Connection refused to {server_host}:{server_port}")
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

    print("\n✓ Single request completed successfully")

if __name__ == '__main__':
    server_host = os.environ.get('SERVER_HOST', '10.1.0.10')
    server_port = int(os.environ.get('SERVER_PORT', '8080'))
    send_single_request(server_host, server_port)
