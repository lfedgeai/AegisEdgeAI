#!/usr/bin/env python3
"""
Utility script to generate fingerprints for public keys.
"""

import os
import sys
import hashlib
import subprocess
from pathlib import Path

def generate_key_fingerprint(public_key_path: str) -> str:
    """
    Generate a SHA-256 fingerprint for a public key.
    
    Args:
        public_key_path: Path to the public key file
        
    Returns:
        SHA-256 fingerprint as a hex string
    """
    try:
        with open(public_key_path, 'rb') as f:
            key_data = f.read()
        
        # Generate SHA-256 hash
        fingerprint = hashlib.sha256(key_data).hexdigest()
        return f"sha256:{fingerprint}"
        
    except Exception as e:
        print(f"Error generating fingerprint: {e}")
        return None

def get_openssl_fingerprint(public_key_path: str) -> str:
    """
    Get fingerprint using OpenSSL command.
    
    Args:
        public_key_path: Path to the public key file
        
    Returns:
        OpenSSL fingerprint string
    """
    try:
        result = subprocess.run(
            ['openssl', 'x509', '-in', public_key_path, '-noout', '-fingerprint', '-sha256'],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            # Extract fingerprint from output like "SHA256 Fingerprint=AA:BB:CC:DD..."
            fingerprint_line = result.stdout.strip()
            fingerprint = fingerprint_line.split('=')[1]
            return f"sha256:{fingerprint}"
        else:
            print(f"OpenSSL error: {result.stderr}")
            return None
            
    except Exception as e:
        print(f"Error running OpenSSL: {e}")
        return None

def main():
    """Main function."""
    if len(sys.argv) != 2:
        print("Usage: python generate_key_fingerprint.py <public_key_path>")
        sys.exit(1)
    
    public_key_path = sys.argv[1]
    
    if not os.path.exists(public_key_path):
        print(f"Public key file not found: {public_key_path}")
        sys.exit(1)
    
    print(f"Generating fingerprint for: {public_key_path}")
    
    # Try OpenSSL first (for X.509 certificates)
    fingerprint = get_openssl_fingerprint(public_key_path)
    
    if not fingerprint:
        # Fall back to simple SHA-256 hash
        fingerprint = generate_key_fingerprint(public_key_path)
    
    if fingerprint:
        print(f"Fingerprint: {fingerprint}")
    else:
        print("Failed to generate fingerprint")
        sys.exit(1)

if __name__ == "__main__":
    main()
