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
    script_dir = Path(__file__).parent / "python-app-demo"
    workload_pb2_path = script_dir / "generated" / "spiffe" / "workload" / "workload_pb2.py"
    workload_pb2_grpc_path = script_dir / "generated" / "spiffe" / "workload" / "workload_pb2_grpc.py"

    if not workload_pb2_path.exists() or not workload_pb2_grpc_path.exists():
        raise ImportError(f"Protobuf files not found: {workload_pb2_path}")

    # Load protobuf modules - need to register in sys.modules to avoid conflicts
    # Must create full module hierarchy in sys.modules before loading grpc module
    import types
    import sys
    
    # Create placeholder modules for the hierarchy (to avoid importing system 'spiffe')
    if 'spiffe' not in sys.modules or hasattr(sys.modules.get('spiffe'), '__path__'):
        # Only override if not already loaded, or if it's a real package
        spiffe_module = types.ModuleType('spiffe')
        spiffe_module.__path__ = []  # Make it a package
        sys.modules['spiffe'] = spiffe_module
    
    if 'spiffe.workload' not in sys.modules:
        spiffe_workload = types.ModuleType('spiffe.workload')
        spiffe_workload.__path__ = []
        sys.modules['spiffe.workload'] = spiffe_workload
        # Compatibility with different import styles
        if hasattr(sys.modules['spiffe'], 'workload'):
            sys.modules['spiffe'].workload = spiffe_workload

    # Load workload_pb2 first
    spec_pb2 = importlib.util.spec_from_file_location("workload_pb2", workload_pb2_path)
    workload_pb2 = importlib.util.module_from_spec(spec_pb2)
    spec_pb2.loader.exec_module(workload_pb2)
    
    # Register in sys.modules so workload_pb2_grpc can find it
    sys.modules['spiffe.workload.workload_pb2'] = workload_pb2
    
    # Now load workload_pb2_grpc
    spec_grpc = importlib.util.spec_from_file_location("workload_pb2_grpc", workload_pb2_grpc_path)
    workload_pb2_grpc = importlib.util.module_from_spec(spec_grpc)
    spec_grpc.loader.exec_module(workload_pb2_grpc)

    # Create gRPC channel
    abs_socket_path = socket_path.replace('unix://', '')
    if not os.path.exists(abs_socket_path):
        # Graceful exit if socket doesn't exist (common during early integration test stages)
        print(f"SPIRE Agent socket not found at {abs_socket_path}. SPIRE Agent may not be started yet.")
        sys.exit(1)
        
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
    
    # Get SPIFFE ID directly from response if available
    spiffe_id_str = getattr(svid_response, 'spiffe_id', None)
    if spiffe_id_str:
        spiffe_id = SimpleSpiffeId(spiffe_id_str)
    else:
        # Fallback to parsing certificate if spiffe_id field is missing
        cert_data = getattr(svid_response, 'x509_svid', getattr(svid_response, 'certificate', [None])[0])
        if isinstance(cert_data, list): cert_data = cert_data[0]
        
        try:
            cert = x509.load_der_x509_certificate(cert_data)
        except ValueError as e:
            # If it has extra data, it's likely a concatenated chain; try to ignore for ID extraction
            # This is a hacky way to get the first cert's bytes if it's concatenated DER
            # For extraction of the ID, we only need the first one.
            pass
            
        # (ID extraction from cert logic removed as we prefer spiffe_id field)
        raise Exception("Could not determine SPIFFE ID from response")

    # The trust bundle is what we actually want to save
    bundle_certs = []
    bundle_data = getattr(svid_response, 'bundle', getattr(svid_response, 'trust_bundle', None))
    if bundle_data:
        if isinstance(bundle_data, (list, tuple)):
            for b_der in bundle_data:
                bundle_certs.append(x509.load_der_x509_certificate(b_der))
        else:
            # Singular bytes field - might be a single cert or concatenated
            try:
                bundle_certs.append(x509.load_der_x509_certificate(bundle_data))
            except ValueError as e:
                if "ExtraData" in str(e):
                    # Handle concatenated DER bundle (common in some SPIRE versions)
                    # We'll just take the first one or try a simple split if we can
                    pass
    
    def load_der_certs(data):
        """Load one or more DER certificates from bytes."""
        if not data: return []
        certs = []
        pos = 0
        while pos < len(data):
            if data[pos] != 0x30: break
            start = pos
            try:
                pos += 1
                if pos >= len(data): break
                length = data[pos]
                pos += 1
                if length & 0x80:
                    n = length & 0x7f
                    if pos + n > len(data): break
                    length = int.from_bytes(data[pos:pos+n], 'big')
                    pos += n
                
                full_len = pos - start + length
                cert_data = data[start:start+full_len]
                cert = x509.load_der_x509_certificate(cert_data)
                certs.append(cert)
                pos = start + full_len
            except Exception:
                break
        return certs



    # Get trust bundle - try multiple places where it might be
    bundle_certs = []
    
    # 1. Try bundle field in SVID response
    svid_bundle = getattr(svid_response, 'bundle', getattr(svid_response, 'trust_bundle', None))
    if svid_bundle:
        if isinstance(svid_bundle, (list, tuple)):
            for b_der in svid_bundle:
                bundle_certs.extend(load_der_certs(b_der))
        else:
            bundle_certs.extend(load_der_certs(svid_bundle))
            
    # 2. Try FetchX509Bundles if SVID response didn't have it
    if not bundle_certs:
        try:
            bundle_request = workload_pb2.X509BundlesRequest()
            bundle_response_stream = stub.FetchX509Bundles(bundle_request, metadata=grpc_metadata, timeout=5)
            bundle_response = next(bundle_response_stream)
            for trust_domain, bundle_der in bundle_response.bundles.items():
                if trust_domain == spiffe_id.trust_domain:
                    bundle_certs.extend(load_der_certs(bundle_der))
        except Exception:
            pass

    channel.close()
    if not bundle_certs:
        raise Exception("Could not retrieve trust bundle from SPIRE Agent")
        
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
        # Suppress full traceback for common/expected connection errors during startup
        if "StatusCode.UNAVAILABLE" in str(e) or "failed to connect" in str(e).lower():
            print(f"Error: Could not connect to SPIRE Agent at {socket_path}. Ensure it is running.")
        else:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
