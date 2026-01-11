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
import importlib.util
import time
import random
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


import argparse
import json
import base64

# OID for Unified Identity Claims
UNIFIED_IDENTITY_OID = "1.3.6.1.4.1.55744.1.1"

def fetch_bundle_via_grpc(socket_path):
    """Fetch trust bundle and leaf SVID from SPIRE Agent via direct gRPC."""
    script_dir = Path(__file__).parent / "python-app-demo"
    workload_pb2_path = script_dir / "generated" / "spiffe" / "workload" / "workload_pb2.py"
    workload_pb2_grpc_path = script_dir / "generated" / "spiffe" / "workload" / "workload_pb2_grpc.py"

    if not workload_pb2_path.exists() or not workload_pb2_grpc_path.exists():
        raise ImportError(f"Protobuf files not found: {workload_pb2_path}")

    # Load protobuf modules
    import types
    import sys
    
    if 'spiffe' not in sys.modules or hasattr(sys.modules.get('spiffe'), '__path__'):
        spiffe_module = types.ModuleType('spiffe')
        spiffe_module.__path__ = []
        sys.modules['spiffe'] = spiffe_module
    
    if 'spiffe.workload' not in sys.modules:
        spiffe_workload = types.ModuleType('spiffe.workload')
        spiffe_workload.__path__ = []
        sys.modules['spiffe.workload'] = spiffe_workload

    spec_pb2 = importlib.util.spec_from_file_location("workload_pb2", workload_pb2_path)
    workload_pb2 = importlib.util.module_from_spec(spec_pb2)
    spec_pb2.loader.exec_module(workload_pb2)
    sys.modules['spiffe.workload.workload_pb2'] = workload_pb2
    
    spec_grpc = importlib.util.spec_from_file_location("workload_pb2_grpc", workload_pb2_grpc_path)
    workload_pb2_grpc = importlib.util.module_from_spec(spec_grpc)
    spec_grpc.loader.exec_module(workload_pb2_grpc)

    max_attempts = 5
    attempt = 0
    backoff = 1.0
    abs_socket_path = socket_path.replace('unix://', '')
    response = None

    while attempt < max_attempts:
        attempt += 1
        try:
            if not os.path.exists(abs_socket_path) and attempt < max_attempts:
                raise Exception(f"Socket not found at {abs_socket_path}")

            channel = grpc.insecure_channel(f'unix:{abs_socket_path}')
            stub = workload_pb2_grpc.SpiffeWorkloadAPIStub(channel)
            grpc_metadata = [('workload.spiffe.io', 'true')]

            request = workload_pb2.X509SVIDRequest()
            rpc_timeout = 5 if attempt < max_attempts else 15
            response_stream = stub.FetchX509SVID(request, metadata=grpc_metadata, timeout=rpc_timeout)
            response = next(response_stream)

            if not response or not response.svids:
                raise Exception("No SVIDs in response")
            break
        except (grpc.RpcError, Exception) as e:
            if attempt < max_attempts:
                wait_time = backoff + random.uniform(0, 0.5)
                time.sleep(wait_time)
                backoff *= 2
            else:
                raise e

    svid_response = response.svids[0]
    spiffe_id_str = getattr(svid_response, 'spiffe_id', "")
    spiffe_id = SimpleSpiffeId(spiffe_id_str)

    # Extract leaf DER cert
    leaf_cert_der = svid_response.x509_svid
    # If it's a chain (concatenated DER), load_der_certs will handle it
    
    def load_der_certs(data):
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

    svid_certs = load_der_certs(leaf_cert_der)
    
    bundle_certs = []
    bundle_der = getattr(svid_response, 'bundle', None)
    if bundle_der:
        bundle_certs = load_der_certs(bundle_der)
        
    channel.close()
    return spiffe_id, bundle_certs, svid_certs

def dump_claims(svid_certs):
    """Extract and dump Unified Identity claims from SVID."""
    if not svid_certs:
        return
    
    # Unified Identity can be in leaf or agent SVID (intermediate)
    claims = {}
    print(f"  Checking {len(svid_certs)} certificate(s) in SVID chain...")
    for i, cert in enumerate(svid_certs):
        spiffe_id = "unknown"
        try:
            for ext in cert.extensions:
                if ext.oid._name == 'subjectAltName':
                    for name in ext.value:
                        if hasattr(name, 'value') and isinstance(name.value, str) and name.value.startswith('spiffe://'):
                            spiffe_id = name.value
                            break
        except: pass
        
        print(f"  - Cert [{i}]: SPIFFE ID: {spiffe_id}")
        
        for ext in cert.extensions:
            if ext.oid.dotted_string == UNIFIED_IDENTITY_OID:
                print(f"    ✓ Found Unified Identity extension in cert [{i}]")
                # Value is usually an octet string containing UTF-8 JSON
                try:
                    # Cryptography returns the raw extension value (DER octet string)
                    # We need to unwrap the octet string if it's there, or just take bytes
                    val = ext.value.value
                    if isinstance(val, bytes):
                        # Some versions of cryptography/SPIRE might wrap this
                        # Try to parse as JSON directly
                        try:
                            claims = json.loads(val.decode('utf-8'))
                        except:
                            # Try to strip leading/trailing non-JSON if any
                            s = val.decode('utf-8', errors='ignore')
                            start = s.find('{')
                            end = s.rfind('}')
                            if start != -1 and end != -1:
                                claims = json.loads(s[start:end+1])
                    break
                except Exception as e:
                    print(f"  ⚠ Failed to parse claims from extension: {e}")
        if claims:
            break
            
    if claims:
        dump_path = Path("/tmp/svid-dump/attested_claims.json")
        dump_path.parent.mkdir(parents=True, exist_ok=True)
        with open(dump_path, 'w') as f:
            json.dump(claims, f, indent=2)
        print(f"✓ Dumped SVID claims to {dump_path}")
    else:
        print("⚠ No Unified Identity claims found in SVID chain")

def main():
    parser = argparse.ArgumentParser(description='Fetch SPIRE Trust Bundle or Dump SVID Claims')
    parser.add_argument('--dump-only', action='store_true', help='Dump SVID claims instead of fetching bundle')
    parser.add_argument('--socket', default=os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock'), help='SPIRE Agent socket path')
    parser.add_argument('--output', default=os.environ.get('BUNDLE_OUTPUT_PATH', '/tmp/spire-bundle.pem'), help='Output path for bundle')
    args = parser.parse_args()

    raw_socket = args.socket
    if "://" in raw_socket:
        socket_path = raw_socket
    else:
        socket_path = f"unix://{raw_socket}"

    try:
        spiffe_id, bundle_certs, svid_certs = fetch_bundle_via_grpc(socket_path)

        if args.dump_only:
            dump_claims(svid_certs)
            return

        print(f"Trust domain: {spiffe_id.trust_domain}")
        print(f"SPIFFE ID: {spiffe_id}")

        if not bundle_certs:
            print("Error: Trust bundle has no X509 authorities")
            sys.exit(1)

        # Write bundle to file
        bundle_pem = b""
        for cert in bundle_certs:
            bundle_pem += cert.public_bytes(serialization.Encoding.PEM)

        output_dir = os.path.dirname(args.output)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, mode=0o755, exist_ok=True)

        with open(args.output, 'wb') as f:
            f.write(bundle_pem)

        print(f"✓ Successfully extracted SPIRE trust bundle to {args.output}")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

if __name__ == '__main__':
    main()
