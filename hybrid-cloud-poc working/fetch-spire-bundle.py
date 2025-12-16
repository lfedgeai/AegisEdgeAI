#!/usr/bin/env python3
"""
Fetch SPIRE Trust Bundle (CA Certificate)
Extracts the SPIRE CA certificate bundle for use with standard cert servers.
"""

import os
import sys

try:
    from spiffe.workloadapi.x509_source import X509Source
    HAS_SPIFFE = True
except ImportError:
    print("Error: spiffe library not installed")
    print("Install it with: pip install spiffe")
    sys.exit(1)

def main():
    # SPIRE_AGENT_SOCKET can be either:
    # - A bare Unix socket path (e.g., /tmp/spire-agent/public/api.sock)
    # - A full endpoint URI (e.g., unix:///tmp/spire-agent/public/api.sock or tcp://10.0.0.5:8081)
    raw_socket = os.environ.get('SPIRE_AGENT_SOCKET', '/tmp/spire-agent/public/api.sock')
    output_path = os.environ.get('BUNDLE_OUTPUT_PATH', '/tmp/spire-bundle.pem')
    
    # If the value already contains a scheme (://), use it as-is.
    # Otherwise, assume a Unix domain socket path and prefix with unix://
    if "://" in raw_socket:
        socket_path_with_scheme = raw_socket
    else:
        socket_path_with_scheme = f"unix://{raw_socket}"

    print(f"Fetching SPIRE trust bundle from: {socket_path_with_scheme}")
    print(f"Output path: {output_path}")
    print("")
    
    try:
        # Create X509Source to access bundle
        source = X509Source(socket_path=socket_path_with_scheme)
        
        # Get SVID to determine trust domain
        svid = source.svid
        if not svid:
            print("Error: Failed to get SVID from SPIRE Agent")
            print("Make sure SPIRE Agent is running and accessible")
            sys.exit(1)
        
        trust_domain = svid.spiffe_id.trust_domain
        print(f"Trust domain: {trust_domain}")
        print(f"SPIFFE ID: {svid.spiffe_id}")
        print("")
        
        # Get trust bundle
        bundle = source.get_bundle_for_trust_domain(trust_domain)
        if not bundle:
            print("Error: Failed to get trust bundle from SPIRE Agent")
            sys.exit(1)
        
        # Extract CA certificates
        from cryptography.hazmat.primitives import serialization
        x509_authorities = bundle.x509_authorities
        if not x509_authorities or len(x509_authorities) == 0:
            print("Error: Trust bundle has no X509 authorities")
            sys.exit(1)
        
        # Write bundle to file
        bundle_pem = b""
        for cert in x509_authorities:
            bundle_pem += cert.public_bytes(serialization.Encoding.PEM)
        
        # Create output directory if needed
        output_dir = os.path.dirname(output_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, mode=0o755, exist_ok=True)
        
        with open(output_path, 'wb') as f:
            f.write(bundle_pem)
        
        print(f"✓ Successfully extracted SPIRE trust bundle")
        print(f"  Bundle file: {output_path}")
        print(f"  Number of CA certificates: {len(x509_authorities)}")
        print("")
        print("You can now use this bundle file with:")
        print(f"  export CA_CERT_PATH=\"{output_path}\"")
        print("")
        print("For the server (standard cert mode):")
        print(f"  export CA_CERT_PATH=\"{output_path}\"  # To verify SPIRE client certs")
        print("")
        
        source.close()
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()

