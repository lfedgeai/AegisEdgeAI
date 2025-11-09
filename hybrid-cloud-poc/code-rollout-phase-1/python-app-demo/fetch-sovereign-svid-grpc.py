#!/usr/bin/env python3
"""
Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
Python script to fetch Sovereign SVID with AttestedClaims from SPIRE Agent Workload API using gRPC directly.

This script uses gRPC to call the Workload API directly, allowing access to AttestedClaims
from the protobuf response.

Requirements:
    pip install grpcio protobuf
"""
import os
import sys
import json
from pathlib import Path

try:
    import grpc
    from google.protobuf import json_format
except ImportError:
    print("Error: grpcio and protobuf libraries not installed")
    print("Install them with: pip install grpcio protobuf")
    sys.exit(1)

# Add the go-spiffe proto directory to path to import generated protobufs
# Note: We'll need to generate Python stubs from the .proto file
# For now, we'll use a workaround by calling the protobuf compiler or using reflection

def generate_proto_stubs():
    """Generate Python stubs from workload.proto if not already generated."""
    proto_dir = Path(__file__).parent.parent / "go-spiffe" / "proto" / "spiffe" / "workload"
    proto_file = proto_dir / "workload.proto"
    output_dir = Path(__file__).parent / "generated"
    
    if not proto_file.exists():
        print(f"Error: Proto file not found at {proto_file}")
        return False
    
    # Check if already generated
    generated_file = output_dir / "spiffe" / "workload" / "workload_pb2.py"
    if generated_file.exists():
        return True
    
    try:
        import subprocess
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Generate Python stubs using protoc
        result = subprocess.run(
            [
                "protoc",
                f"--proto_path={proto_dir.parent.parent.parent}",
                f"--python_out={output_dir}",
                str(proto_file)
            ],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print(f"✓ Generated Python protobuf stubs in {output_dir}")
            return True
        else:
            print(f"Warning: Failed to generate protobuf stubs: {result.stderr}")
            print("You may need to install protoc: https://grpc.io/docs/protoc-installation/")
            return False
    except FileNotFoundError:
        print("Warning: protoc not found. Cannot generate protobuf stubs.")
        print("Install protoc: https://grpc.io/docs/protoc-installation/")
        return False

def fetch_from_workload_api_grpc(max_retries=3, retry_delay=5):
    """
    Unified-Identity - Phase 1: Fetch SVID from SPIRE Agent Workload API using gRPC directly.
    
    This function uses gRPC to call the Workload API, allowing access to AttestedClaims
    from the protobuf response.
    
    Args:
        max_retries: Maximum number of retries if "no identity issued" error occurs (default: 3)
        retry_delay: Delay in seconds between retries (default: 5)
    
    Returns:
        tuple: (cert_pem, attested_claims_json) or (None, None) on error
    """
    socket_path = "/tmp/spire-agent/public/api.sock"
    
    if not os.path.exists(socket_path):
        print(f"Error: SPIRE Agent socket not found at {socket_path}")
        print("Make sure SPIRE Agent is running")
        return None, None
    
    print("Connecting to SPIRE Agent Workload API via gRPC...")
    print("  Socket: /tmp/spire-agent/public/api.sock")
    print("  (This Python process will be attested by the agent)")
    print()
    
    try:
        # Try to import generated protobufs
        generated_dir = Path(__file__).parent / "generated"
        if generated_dir.exists():
            sys.path.insert(0, str(generated_dir))
        
        try:
            from spiffe.workload import workload_pb2
            from spiffe.workload import workload_pb2_grpc
        except ImportError:
            # If protobufs not generated, try to generate them
            if generate_proto_stubs():
                from spiffe.workload import workload_pb2
                from spiffe.workload import workload_pb2_grpc
            else:
                print("Error: Cannot import workload protobufs")
                print("Please generate them manually:")
                print(f"  protoc --proto_path=../go-spiffe/proto --python_out=generated ../go-spiffe/proto/spiffe/workload/workload.proto")
                print(f"  python -m grpc_tools.protoc --proto_path=../go-spiffe/proto --python_out=generated --grpc_python_out=generated ../go-spiffe/proto/spiffe/workload/workload.proto")
                return None, None
        
        # Create gRPC channel to Unix socket
        # gRPC uses 'unix:' prefix for Unix domain sockets (absolute path required)
        abs_socket_path = os.path.abspath(socket_path)
        channel = grpc.insecure_channel(f'unix:{abs_socket_path}')
        
        # Create stub
        stub = workload_pb2_grpc.SpiffeWorkloadAPIStub(channel)
        
        # Create request (empty for FetchX509SVID)
        request = workload_pb2.X509SVIDRequest()
        
        # Unified-Identity - Phase 1: Add required security header for Workload API
        # The SPIRE Agent requires the "workload.spiffe.io" metadata header
        # This is a security measure to ensure the client is aware it's calling the Workload API
        # For streaming RPCs in Python gRPC, metadata is passed as a list of (key, value) tuples
        grpc_metadata = [('workload.spiffe.io', 'true')]
        
        # Call FetchX509SVID (it's a streaming RPC) with metadata
        # Python gRPC accepts metadata as a list of (key, value) tuples for streaming calls
        # We'll retry if we get "no identity issued" errors (entry hasn't propagated yet)
        
        import time
        
        for attempt in range(max_retries + 1):
            if attempt > 0:
                print(f"  Retry attempt {attempt}/{max_retries} (waiting {retry_delay}s for entry to propagate)...")
                time.sleep(retry_delay)
            else:
                print("Calling FetchX509SVID...")
                print("  (Waiting for agent to fetch SVID from server - this may take a few seconds...)")
            
            # The agent needs time to:
            # 1. Attest this process (extract UID, etc.)
            # 2. Match selectors to registration entry
            # 3. Fetch SVID from server if not cached
            # For streaming RPCs, the agent will send updates when SVID becomes available
            # The first response might raise "no identity issued" if entry hasn't propagated yet
            
            try:
                responses = stub.FetchX509SVID(request, metadata=grpc_metadata)
                
                # Get the first response (streaming may send multiple updates)
                # The agent will send updates when SVID becomes available
                response = None
                max_wait_updates = 20  # Wait for up to 20 updates (agent sends updates periodically)
                update_count = 0
                
                for resp in responses:
                    update_count += 1
                    if resp.svids and len(resp.svids) > 0:
                        response = resp
                        if attempt > 0:
                            print(f"  ✓ SVID received after retry {attempt} (update {update_count})")
                        else:
                            print(f"  ✓ SVID received after {update_count} update(s)")
                        break
                    
                    # If we've waited too long, break and retry
                    if update_count >= max_wait_updates:
                        if attempt < max_retries:
                            print(f"  ⚠ No SVID after {max_wait_updates} updates - will retry...")
                            break  # Break inner loop to retry
                        else:
                            print(f"  ⚠ No SVID after {max_wait_updates} updates and {max_retries} retries")
                            print("  This usually means:")
                            print("    1. Registration entry hasn't propagated to agent yet")
                            print("    2. Process selectors don't match the entry")
                            print("    3. Agent hasn't fetched SVID from server yet")
                            print("  Try:")
                            print("    - Wait a few more seconds and retry manually")
                            print("    - Check agent logs: tail -20 /tmp/spire-agent.log")
                            print("    - Verify entry: ../spire/bin/spire-server entry show -spiffeID spiffe://example.org/python-app")
                            return None, None
                    
                    # Show progress for long waits
                    if update_count % 5 == 0:
                        print(f"  ... still waiting (update {update_count}/{max_wait_updates})...")
                
                # If we got a response, break out of retry loop
                if response:
                    break
                    
            except grpc.RpcError as e:
                # If we get a permission denied error, the entry hasn't propagated yet
                if e.code() == grpc.StatusCode.PERMISSION_DENIED:
                    error_msg = str(e.details()) if e.details() else str(e)
                    if "no identity issued" in error_msg.lower():
                        if attempt < max_retries:
                            print(f"  ⚠ Got 'no identity issued' error (attempt {attempt + 1}/{max_retries + 1})")
                            print(f"     Entry may not have propagated yet - will retry in {retry_delay}s...")
                            continue  # Retry
                        else:
                            print("  ⚠ Got 'no identity issued' error after all retries")
                            print("  This is expected if the entry was just created.")
                            print("  The agent syncs with the server every ~5 seconds.")
                            print("  Recommendation: Wait 5-10 seconds after creating the entry before calling gRPC.")
                            return None, None
                # Re-raise other errors
                raise
        
        if not response:
            # If we didn't get a response after all retries, it might be a timing issue
            print("  ⚠ No SVID received after all retries - this might be a timing issue")
            print("  The spiffe library version handles retries automatically")
            return None, None
        
        if not response.svids:
            print("Error: No SVIDs in response")
            return None, None
        
        # Get the first SVID
        svid = response.svids[0]
        
        # Extract certificate (it's DER-encoded bytes)
        from cryptography import x509
        from cryptography.hazmat.primitives import serialization
        cert_der = svid.x509_svid
        cert = x509.load_der_x509_certificate(cert_der)
        cert_pem = cert.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')
        
        print(f"✓ SVID fetched successfully")
        print(f"  SPIFFE ID: {svid.spiffe_id}")
        print()
        
        # Unified-Identity - Phase 1: Extract AttestedClaims from response
        claims_json = None
        if response.attested_claims:
            print(f"✓ Found {len(response.attested_claims)} AttestedClaims in response")
            print()
            
            # Convert protobuf AttestedClaims to JSON
            claims_list = []
            for claim in response.attested_claims:
                claim_dict = {
                    "geolocation": claim.geolocation,
                    "host_integrity_status": claim.HostIntegrity.Name(claim.host_integrity_status),
                }
                
                if claim.gpu_metrics_health:
                    claim_dict["gpu_metrics_health"] = {
                        "status": claim.gpu_metrics_health.status,
                        "utilization_pct": claim.gpu_metrics_health.utilization_pct,
                        "memory_mb": claim.gpu_metrics_health.memory_mb,
                    }
                
                claims_list.append(claim_dict)
            
            # For simplicity, use the first claim (or combine them)
            if len(claims_list) == 1:
                claims_json = claims_list[0]
            else:
                claims_json = {"claims": claims_list} if claims_list else None
        else:
            print("⚠ No AttestedClaims in response")
            print("  (This may mean the feature flag is disabled or no claims were returned)")
        
        channel.close()
        return cert_pem, claims_json
        
    except Exception as e:
        print(f"Error fetching SVID via gRPC: {e}")
        import traceback
        traceback.print_exc()
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
        print("  5. If protobuf import fails, generate stubs:")
        print("     python -m grpc_tools.protoc --proto_path=../go-spiffe/proto --python_out=generated --grpc_python_out=generated ../go-spiffe/proto/spiffe/workload/workload.proto")
        return None, None

def main():
    print("=" * 70)
    print("Unified-Identity - Phase 1: Fetching Sovereign SVID (gRPC)")
    print("=" * 70)
    print()
    print("Note: Using gRPC directly to access AttestedClaims from Workload API")
    print("      Architecture: Python App → SPIRE Agent (gRPC) → SPIRE Server")
    print()
    
    output_dir = Path("/tmp/svid-dump")
    output_dir.mkdir(exist_ok=True)
    
    # Fetch SVID from Workload API using gRPC
    print("Fetching SVID from SPIRE Agent Workload API via gRPC...")
    cert_pem, claims_json = fetch_from_workload_api_grpc()
    
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
            print("AttestedClaims (from SPIRE Agent):")
            print(json.dumps(claims_json, indent=2))
        else:
            print("(Note: AttestedClaims not available in response)")
        
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

