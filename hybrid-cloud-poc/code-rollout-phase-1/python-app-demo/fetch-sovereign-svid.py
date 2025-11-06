#!/usr/bin/env python3
"""
Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
Python script to fetch Sovereign SVID with AttestedClaims using SPIRE Server API
"""

import os
import sys
import json
import subprocess
import tempfile
from pathlib import Path

def get_registration_entry_id():
    """Get the registration entry ID for the Python app."""
    script_dir = Path(__file__).parent
    spire_dir = script_dir.parent / "spire"
    
    try:
        result = subprocess.run(
            [str(spire_dir / "bin" / "spire-server"), "entry", "show",
             "-spiffeID", "spiffe://example.org/python-app",
             "-socketPath", "/tmp/spire-server/private/api.sock"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            # Extract entry ID from output
            for line in result.stdout.split('\n'):
                if 'Entry ID' in line:
                    entry_id = line.split(':')[-1].strip()
                    return entry_id
    except Exception as e:
        print(f"Warning: Could not get entry ID: {e}")
    
    return None

def call_spire_server_api():
    """Call SPIRE Server API to generate sovereign SVID."""
    script_dir = Path(__file__).parent
    spire_dir = script_dir.parent / "spire"
    generate_script = script_dir.parent / "scripts" / "generate-sovereign-svid.go"
    
    if not generate_script.exists():
        print(f"Error: generate-sovereign-svid.go not found at {generate_script}")
        return None, None
    
    # Get registration entry ID
    entry_id = get_registration_entry_id()
    if not entry_id:
        print("Error: Could not get registration entry ID")
        print("Make sure you ran ./create-registration-entry.sh first")
        return None, None
    
    print("Calling SPIRE Server API to generate sovereign SVID...")
    print(f"Using entry ID: {entry_id}")
    print("(This uses the Go script which calls BatchNewX509SVID API)")
    print()
    
    # Run the Go script with entry ID
    try:
        result = subprocess.run(
            ["go", "run", str(generate_script),
             "-entryID", entry_id,
             "-spiffeID", "spiffe://example.org/python-app",
             "-outputCert", "/tmp/svid.pem",
             "-outputKey", "/tmp/svid.key"],
            cwd=str(script_dir.parent),
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            print(f"Error running generate-sovereign-svid.go:")
            print(result.stdout)
            print(result.stderr)
            return None, None
        
        # The script saves files - check for them
        cert_file = Path("/tmp/svid.pem")
        claims_file = Path("/tmp/svid_attested_claims.json")  # Go script uses this naming
        
        if not cert_file.exists():
            # Try alternative location
            cert_file = script_dir.parent / "scripts" / "svid.pem"
            claims_file = script_dir.parent / "scripts" / "svid_attested_claims.json"
        
        if cert_file.exists():
            cert_pem = cert_file.read_text()
            claims_json = None
            if claims_file.exists():
                claims_json = json.loads(claims_file.read_text())
            return cert_pem, claims_json
        else:
            print("Warning: Certificate file not found after generation")
            print(f"Checked: /tmp/svid.pem and {script_dir.parent / 'scripts' / 'svid.pem'}")
            return None, None
            
    except subprocess.TimeoutExpired:
        print("Error: Script timed out")
        return None, None
    except Exception as e:
        print(f"Error: {e}")
        return None, None

def fetch_from_workload_api():
    """Fetch SVID from Workload API (standard, no AttestedClaims)."""
    socket_path = "/tmp/spire-agent/public/api.sock"
    
    if not os.path.exists(socket_path):
        print(f"Error: SPIRE Agent socket not found at {socket_path}")
        return None, None
    
    print("Fetching SVID from Workload API...")
    print("(Note: Workload API doesn't expose AttestedClaims directly)")
    print()
    
    try:
        result = subprocess.run(
            ["spire-agent", "api", "fetch", "-socketPath", socket_path, "-write", "/tmp"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            cert_file = Path("/tmp/svid.0.pem")
            if cert_file.exists():
                return cert_file.read_text(), None
    except Exception as e:
        print(f"Error: {e}")
    
    return None, None

def main():
    print("=" * 70)
    print("Unified-Identity - Phase 1: Fetching Sovereign SVID")
    print("=" * 70)
    print()
    
    output_dir = Path("/tmp/svid-dump")
    output_dir.mkdir(exist_ok=True)
    
    # Try to get sovereign SVID with AttestedClaims
    print("Method 1: Fetching Sovereign SVID with AttestedClaims...")
    cert_pem, claims_json = call_spire_server_api()
    
    if cert_pem:
        # Save certificate
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
            print("⚠ No AttestedClaims in response")
        
        print()
        print("=" * 70)
        print("SVID fetch complete!")
        print("=" * 70)
        print()
        print("To view the SVID with AttestedClaims:")
        if claims_json:
            print(f"  ../scripts/dump-svid -cert {cert_file} -attested {output_dir / 'attested_claims.json'}")
        else:
            print(f"  ../scripts/dump-svid -cert {cert_file}")
        return
    
    # Fallback to standard workload API
    print()
    print("Method 2: Fetching from Workload API (fallback)...")
    cert_pem, _ = fetch_from_workload_api()
    
    if cert_pem:
        cert_file = output_dir / "svid.pem"
        cert_file.write_text(cert_pem)
        print(f"✓ SVID certificate saved to: {cert_file}")
        print("(Note: No AttestedClaims available from Workload API)")
        print()
        print("To view the SVID:")
        print(f"  ../scripts/dump-svid -cert {cert_file}")
    else:
        print("Error: Could not fetch SVID")
        sys.exit(1)

if __name__ == "__main__":
    main()

