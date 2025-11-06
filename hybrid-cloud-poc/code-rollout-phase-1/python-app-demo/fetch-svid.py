#!/usr/bin/env python3
"""
Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
Python script to fetch SVID from SPIRE Workload API and extract AttestedClaims
"""

import os
import sys
import json
import socket
import struct
import time
from pathlib import Path

# Try to import the workload API client
try:
    from spiffe.workloadapi import default_client
    from spiffe.svid import x509_svid
    HAS_SPIFFE = True
except ImportError:
    HAS_SPIFFE = False
    print("Warning: spiffe library not found. Install with: pip install python-spiffe")
    print("Falling back to manual gRPC client...")

def fetch_svid_grpc(socket_path):
    """Fetch SVID using gRPC directly (fallback if spiffe library not available)."""
    try:
        import grpc
        from google.protobuf import json_format
        
        # Import the workload proto (if available)
        sys.path.insert(0, str(Path(__file__).parent.parent / "go-spiffe" / "proto"))
        
        # For now, use a simpler approach - call spire-agent CLI
        import subprocess
        result = subprocess.run(
            ["spire-agent", "api", "fetch", "-socketPath", socket_path, "-write", "/tmp"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            # spire-agent creates files like svid.0.pem, svid.0.key, bundle.0.pem
            svid_file = Path("/tmp/svid.0.pem")
            if svid_file.exists():
                return svid_file.read_text(), None
        return None, "Could not fetch SVID using spire-agent"
    except Exception as e:
        return None, str(e)

def fetch_svid_spiffe(socket_path):
    """Fetch SVID using python-spiffe library."""
    try:
        with default_client.DefaultWorkloadApiClient(f"unix://{socket_path}") as client:
            svid = client.fetch_x509_svid()
            
            # Get certificate PEM
            cert_pem = svid.cert_bytes_to_pem(svid.cert)
            
            # Note: AttestedClaims are not directly exposed by python-spiffe
            # They would need to be extracted from the raw gRPC response
            # For now, we'll note this limitation
            
            return cert_pem, None
    except Exception as e:
        return None, str(e)

def main():
    socket_path = os.environ.get("SPIFFE_ENDPOINT_SOCKET", "/tmp/spire-agent/public/api.sock")
    output_dir = Path("/tmp/svid-dump")
    output_dir.mkdir(exist_ok=True)
    
    print("=" * 70)
    print("Unified-Identity - Phase 1: Fetching Sovereign SVID")
    print("=" * 70)
    print()
    
    # Check if socket exists
    if not os.path.exists(socket_path):
        print(f"Error: SPIRE Agent socket not found at {socket_path}")
        print("Make sure SPIRE Agent is running and the socket is accessible")
        sys.exit(1)
    
    print(f"✓ Found SPIRE Agent socket: {socket_path}")
    print()
    
    # Try to fetch SVID
    print("Fetching SVID from Workload API...")
    
    cert_pem = None
    error = None
    
    if HAS_SPIFFE:
        print("Using python-spiffe library...")
        cert_pem, error = fetch_svid_spiffe(socket_path)
    else:
        print("Using spire-agent CLI (fallback)...")
        cert_pem, error = fetch_svid_grpc(socket_path)
    
    if error:
        print(f"Error: {error}")
        sys.exit(1)
    
    if not cert_pem:
        print("Error: No certificate received")
        sys.exit(1)
    
    # Save certificate
    cert_file = output_dir / "svid.pem"
    cert_file.write_text(cert_pem)
    print(f"✓ SVID certificate saved to: {cert_file}")
    
    # Note about AttestedClaims
    print()
    print("Note: AttestedClaims are part of the workload API response,")
    print("but the standard workload API doesn't expose them directly.")
    print()
    print("To get AttestedClaims, you need to:")
    print("  1. Use the BatchNewX509SVID API (requires agent credentials)")
    print("  2. Or use the generate-sovereign-svid.go script")
    print()
    print("For now, the certificate is saved. You can view it with:")
    print(f"  ../scripts/dump-svid -cert {cert_file}")
    print()
    
    # Try to get bundle as well
    try:
        import subprocess
        result = subprocess.run(
            ["spire-agent", "api", "fetch", "-socketPath", socket_path],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            # Parse the output to get bundle
            print("✓ SVID fetched successfully")
    except:
        pass
    
    print("=" * 70)
    print("SVID fetch complete!")
    print("=" * 70)

if __name__ == "__main__":
    main()

