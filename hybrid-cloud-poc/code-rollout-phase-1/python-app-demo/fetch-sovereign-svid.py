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
    # Note: Must run from scripts directory where go.mod is located
    scripts_dir = script_dir.parent / "scripts"
    try:
        result = subprocess.run(
            ["go", "run", "generate-sovereign-svid.go",
             "-entryID", entry_id,
             "-spiffeID", "spiffe://example.org/python-app",
             "-outputCert", "/tmp/svid.pem",
             "-outputKey", "/tmp/svid.key"],
            cwd=str(scripts_dir),
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
    """Fetch SVID from Workload API."""
    script_dir = Path(__file__).parent
    spire_dir = script_dir.parent / "spire"
    spire_agent = spire_dir / "bin" / "spire-agent"
    socket_path = "/tmp/spire-agent/public/api.sock"
    
    if not os.path.exists(socket_path):
        print(f"Error: SPIRE Agent socket not found at {socket_path}")
        return None, None
    
    if not spire_agent.exists():
        print(f"Error: SPIRE Agent binary not found at {spire_agent}")
        return None, None
    
    print("Fetching SVID from Workload API...")
    print("(Note: AttestedClaims are in the protobuf but may not be populated by agent yet)")
    print()
    
    # Wait a moment for registration entry to propagate
    import time
    print("Waiting for registration entry to propagate...")
    time.sleep(3)
    
    try:
        result = subprocess.run(
            [str(spire_agent), "api", "fetch", "-socketPath", socket_path, "-write", "/tmp"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            print(f"Error: spire-agent api fetch failed")
            print(f"stdout: {result.stdout}")
            print(f"stderr: {result.stderr}")
            print()
            print("Note: This might happen if the process can't be attested.")
            print("Trying to use existing certificate file if available...")
            
            # Try to read from existing files (might be from a previous successful run)
            cert_file = Path("/tmp/svid.0.pem")
            if cert_file.exists():
                file_age = time.time() - cert_file.stat().st_mtime
                if file_age < 3600:  # Less than 1 hour old
                    print(f"Using existing certificate file: {cert_file} (age: {int(file_age)}s)")
                    cert_pem = cert_file.read_text()
                    if cert_pem.strip() and "BEGIN CERTIFICATE" in cert_pem:
                        mock_claims = {
                            "geolocation": "US-CA-SanFrancisco",
                            "host_integrity_status": "PASSED_ALL_CHECKS",
                            "gpu_metrics_health": {
                                "status": "healthy",
                                "utilization_pct": 45.2,
                                "memory_mb": 8192
                            }
                        }
                        return cert_pem, mock_claims
            
            return None, None
        
        # Check for certificate file (spire-agent creates svid.0.pem, svid.0.key, bundle.0.pem)
        cert_file = Path("/tmp/svid.0.pem")
        if not cert_file.exists():
            print(f"Error: Certificate file not found at {cert_file}")
            print(f"stdout: {result.stdout}")
            print(f"stderr: {result.stderr}")
            return None, None
        
        cert_pem = cert_file.read_text()
        
        # Validate it's a real certificate (not empty or placeholder)
        if not cert_pem.strip() or "BEGIN CERTIFICATE" not in cert_pem:
            print(f"Error: Certificate file appears to be empty or invalid")
            return None, None
        
        # For Phase 1, AttestedClaims are not yet passed through by the agent
        # Create a mock AttestedClaims based on Keylime stub response
        # In production, these would come from the Workload API response
        mock_claims = {
            "geolocation": "US-CA-SanFrancisco",
            "host_integrity_status": "PASSED_ALL_CHECKS",
            "gpu_metrics_health": {
                "status": "healthy",
                "utilization_pct": 45.2,
                "memory_mb": 8192
            }
        }
        
        return cert_pem, mock_claims
    except subprocess.TimeoutExpired:
        print(f"Error: spire-agent api fetch timed out")
        return None, None
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
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
    cert_pem, claims_json = fetch_from_workload_api()
    
    if cert_pem:
        cert_file = output_dir / "svid.pem"
        cert_file.write_text(cert_pem)
        print(f"✓ SVID certificate saved to: {cert_file}")
        
        # Save AttestedClaims if available (mock for Phase 1)
        if claims_json:
            claims_file = output_dir / "attested_claims.json"
            claims_file.write_text(json.dumps(claims_json, indent=2))
            print(f"✓ AttestedClaims saved to: {claims_file} (mock data for Phase 1)")
            print()
            print("AttestedClaims (mock - from Keylime stub):")
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
            print(f"  ../scripts/dump-svid -cert {cert_file} -attested {output_dir / 'attested_claims.json'}")
        else:
            print("To view the SVID:")
            print(f"  ../scripts/dump-svid -cert {cert_file}")
    else:
        print("Error: Could not fetch SVID")
        sys.exit(1)

if __name__ == "__main__":
    main()

