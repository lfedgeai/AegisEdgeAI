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
Fetch SPIRE Trust Bundle (CA Certificate)
Extracts the SPIRE CA certificate bundle for use with standard cert servers.

Uses direct gRPC calls to SPIRE Agent Workload API (no python-spiffe dependency).
"""

import os
import sys
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
    print("Error: grpcio library not installed")
    print("Install it with: pip install grpcio")
    sys.exit(1)

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
except ImportError:
    print("Error: cryptography library not installed")
    print("Install it with: pip install cryptography")
    sys.exit(1)


def fetch_bundle_via_grpc(socket_path):
    """Fetch trust bundle from SPIRE Agent via direct gRPC."""
    # Load protobuf modules
    script_dir = Path(__file__).parent / "python-app-demo"
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

    # Create gRPC channel
    abs_socket_path = socket_path.replace('unix://', '')
    channel = grpc.insecure_channel(f'unix:{abs_socket_path}')
    stub = workload_pb2_grpc.SpiffeWorkloadAPIStub(channel)
    grpc_metadata = [('workload.spiffe.io', 'true')]

    # Fetch SVID to get trust domain
    request = workload_pb2.X509SVIDRequest()
    response_stream = stub.FetchX509SVID(request, metadata=grpc_metadata, timeout=10)
    response = next(response_stream)

    if not response.svids:
        raise Exception("No SVIDs in response")

    svid_response = response.svids[0]
    
    # Parse leaf certificate to get SPIFFE ID
    cert = x509.load_der_x509_certificate(svid_response.x509_svid)
    spiffe_id = None
    for ext in cert.extensions:
        if ext.oid._name == 'subjectAltName':
            for name in ext.value:
                if hasattr(name, 'value') and isinstance(name.value, str):
                    if name.value.startswith('spiffe://'):
                        spiffe_id = SimpleSpiffeId(name.value)
                        break

    if not spiffe_id:
        raise Exception("Could not extract SPIFFE ID from certificate")

    # Fetch bundle
    bundle_request = workload_pb2.X509BundlesRequest()
    bundle_response_stream = stub.FetchX509Bundles(bundle_request, metadata=grpc_metadata, timeout=10)
    bundle_response = next(bundle_response_stream)

    # Parse bundle
    bundle_certs = []
    for trust_domain, bundle_der in bundle_response.bundles.items():
        if trust_domain == spiffe_id.trust_domain:
            bundle_cert = x509.load_der_x509_certificate(bundle_der)
            bundle_certs.append(bundle_cert)

    channel.close()
    return spiffe_id, bundle_certs


def main():
    raw_socket = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    output_path = os.environ.get('BUNDLE_OUTPUT_PATH', '/tmp/spire-bundle.pem')

    if "://" in raw_socket:
        socket_path = raw_socket
    else:
        socket_path = f"unix://{raw_socket}"

    print(f"Fetching SPIRE trust bundle from: {socket_path}")
    print(f"Output path: {output_path}")
    print("")

    try:
        spiffe_id, bundle_certs = fetch_bundle_via_grpc(socket_path)

        print(f"Trust domain: {spiffe_id.trust_domain}")
        print(f"SPIFFE ID: {spiffe_id}")
        print("")

        if not bundle_certs:
            print("Error: Trust bundle has no X509 authorities")
            sys.exit(1)

        # Write bundle to file
        bundle_pem = b""
        for cert in bundle_certs:
            bundle_pem += cert.public_bytes(serialization.Encoding.PEM)

        # Create output directory if needed
        output_dir = os.path.dirname(output_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, mode=0o755, exist_ok=True)

        with open(output_path, 'wb') as f:
            f.write(bundle_pem)

        print(f"✓ Successfully extracted SPIRE trust bundle")
        print(f"  Bundle file: {output_path}")
        print(f"  Number of CA certificates: {len(bundle_certs)}")
        print("")
        print("You can now use this bundle file with:")
        print(f"  export CA_CERT_PATH=\"{output_path}\"")
        print("")

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
