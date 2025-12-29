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
Unified-Identity - Setup: SPIRE API & Policy Staging (Stubbed Keylime)
Python script to fetch Sovereign SVID with AttestedClaims from SPIRE Agent Workload API.

This script communicates ONLY with the SPIRE Agent via the Workload API.
The agent handles all communication with the SPIRE Server.

Requirements:
    pip install -r requirements.txt
"""
import os
import sys
import json
from pathlib import Path
from cryptography.hazmat.primitives import serialization

try:
    from spiffe import X509Source
except ImportError:
    print("Error: spiffe library not installed")
    print("Install it with: pip install -r requirements.txt")
    sys.exit(1)

def fetch_from_workload_api():
    """
    Fetch SVID from SPIRE Agent Workload API using spiffe library.

    This properly attests the Python process itself (not a subprocess).
    The agent automatically:
    1. Attests the calling process (extracts UID, etc.)
    2. Matches selectors to registration entries
    3. Fetches SVID from server on behalf of the workload
    4. Returns SVID to the workload
    """
    socket_path = "/tmp/spire-agent/public/api.sock"

    if not os.path.exists(socket_path):
        print(f"Error: SPIRE Agent socket not found at {socket_path}")
        print("Make sure SPIRE Agent is running")
        return None, None

    print("Connecting to SPIRE Agent Workload API...")
    print("  Socket: /tmp/spire-agent/public/api.sock")
    print("  (This Python process will be attested by the agent)")
    print()

    try:
        # X509Source requires unix:// scheme for socket path
        socket_path_with_scheme = f"unix://{socket_path}"
        # Increase timeout to allow for registration entry propagation
        # The agent needs time to fetch the SVID from the server after entry creation
        with X509Source(socket_path=socket_path_with_scheme, timeout_in_seconds=30) as source:
            svid = source.svid
            if not svid:
                print("Error: No SVID available from Workload API")
                return None, None

            # X509Svid has a 'leaf' property which is a cryptography.x509.Certificate
            # Convert it to PEM format
            if not svid.leaf:
                print("Error: No certificate in SVID")
                return None, None

            cert_pem = svid.leaf.public_bytes(serialization.Encoding.PEM).decode('utf-8')

            print(f"✓ SVID fetched successfully")
            print(f"  SPIFFE ID: {svid.spiffe_id}")
            print()

            # Unified-Identity - Setup: AttestedClaims are now passed through by the agent
            # The agent receives AttestedClaims from the server and includes them in the Workload API response.
            # However, the Python spiffe library may not yet expose AttestedClaims directly.
            # Check if X509Source exposes AttestedClaims (may require library update)
            claims_json = None
            if hasattr(source, 'attested_claims') and source.attested_claims:
                # If the library exposes AttestedClaims, use them
                claims_json = source.attested_claims
                print("✓ AttestedClaims received from Workload API")
            elif hasattr(svid, 'attested_claims') and svid.attested_claims:
                # Alternative: check if SVID object has AttestedClaims
                claims_json = svid.attested_claims
                print("✓ AttestedClaims received from Workload API (via SVID)")
            else:
                # Fallback: The agent now passes AttestedClaims through, but the Python library
                # may need to be updated to expose them. For Setup testing, use mock data.
                print("⚠ AttestedClaims not exposed by Python spiffe library yet")
                print("  (The agent passes them through, but library needs update)")
                print("  Using mock data for Setup demonstration")
                claims_json = {
                    "geolocation": "US-CA-SanFrancisco",
                    "host_integrity_status": "PASSED_ALL_CHECKS",
                    "gpu_metrics_health": {
                        "status": "healthy",
                        "utilization_pct": 45.2,
                        "memory_mb": 8192
                    }
                }

            # Store results before exiting context manager
            result = (cert_pem, claims_json)

        # Context manager exit may show harmless CANCELLED error - ignore it
        return result
    except Exception as e:
        print(f"Error fetching SVID: {e}")
        print()
        print("Troubleshooting:")
        print("  1. Ensure SPIRE Agent is running:")
        print("     ps aux | grep spire-agent")
        print("  2. Check agent socket exists:")
        print("     ls -la /tmp/spire-agent/public/api.sock")
        print("  3. Verify registration entry:")
        print("     ../spire/bin/spire-server entry show -spiffeID spiffe://example.org/python-app -socketPath /tmp/spire-server/private/api.sock")
        print("  4. Check agent logs:")
        print("     tail -20 /tmp/spire-agent.log")
        return None, None

def main():
    print("=" * 70)
    print("Unified-Identity - Setup: Fetching Sovereign SVID")
    print("=" * 70)
    print()
    print("Note: Python app communicates only with SPIRE Agent via Workload API")
    print("      (not directly with SPIRE Server)")
    print()
    print("Architecture:")
    print("  Python App → SPIRE Agent (Workload API) → SPIRE Server")
    print()

    output_dir = Path("/tmp/svid-dump")
    output_dir.mkdir(exist_ok=True)

    # Fetch SVID from Workload API (standard way for workloads)
    print("Fetching SVID from SPIRE Agent Workload API...")
    cert_pem, claims_json = fetch_from_workload_api()

    if cert_pem:
        cert_file = output_dir / "svid.pem"
        cert_file.write_text(cert_pem)
        print(f"✓ SVID certificate saved to: {cert_file}")

        # Save AttestedClaims if available
        if claims_json:
            claims_file = output_dir / "attested_claims.json"
            claims_file.write_text(json.dumps(claims_json, indent=2))
            print(f"✓ AttestedClaims saved to: {claims_file}")
            print()
            print("AttestedClaims:")
            print(json.dumps(claims_json, indent=2))
        else:
            print("(Note: AttestedClaims not available)")

        print()
        print("=" * 70)
        print("SVID fetch complete!")
        print("=" * 70)
        print()
        if claims_json:
            print("To view the SVID with AttestedClaims:")
            print(f"  ../../code-rollout-phase-2/dump-svid-attested-claims.sh {cert_file}")
        else:
            print("To view the SVID:")
            print(f"  ../../code-rollout-phase-2/dump-svid-attested-claims.sh {cert_file}")
    else:
        print("Error: Could not fetch SVID")
        sys.exit(1)

if __name__ == "__main__":
    main()
