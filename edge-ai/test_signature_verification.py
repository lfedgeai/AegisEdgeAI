#!/usr/bin/env python3
"""
Test script to verify signature verification process.
"""

import sys
import os
import json

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def test_signature_verification():
    """Test signature verification directly."""
    print("🧪 Testing Signature Verification")
    print("=" * 40)
    
    # Test data (same as in signature flow test)
    test_metrics = {
        "timestamp": "2025-08-15T15:30:00.000000",
        "cpu_usage": 45.2,
        "memory_usage": 67.8,
        "service": {
            "name": "test-service",
            "version": "1.0.0"
        }
    }
    
    test_geographic_region = {
        "region": "US",
        "state": "California", 
        "city": "Santa Clara"
    }
    
    # Combine data
    data_to_sign = {
        "metrics": test_metrics,
        "geographic_region": test_geographic_region
    }
    
    data_json = json.dumps(data_to_sign, sort_keys=True)
    data_bytes = data_json.encode('utf-8')
    nonce = "dc500913ae1003671234567890abcdef"  # Use a fixed nonce for testing
    nonce_bytes = nonce.encode('utf-8')
    
    print(f"✅ Test data created: {len(data_bytes)} bytes")
    print(f"✅ Nonce: {nonce}")
    
    # Step 1: Sign the data using TPM2
    print("\n1. Signing data with TPM2...")
    try:
        from utils.tpm2_utils import TPM2Utils
        
        tpm2_utils = TPM2Utils(use_swtpm=True)
        signature_data = tpm2_utils.sign_with_nonce(
            data_bytes, 
            nonce_bytes, 
            algorithm="sha256"
        )
        
        print(f"✅ Data signed successfully")
        print(f"   Signature: {signature_data['signature'][:32]}...")
        print(f"   Digest: {signature_data['digest'][:32]}...")
        print(f"   Algorithm: {signature_data['algorithm']}")
        
    except Exception as e:
        print(f"❌ Error signing data: {e}")
        return False
    
    # Step 2: Verify signature using public key utils
    print("\n2. Verifying signature with public key utils...")
    try:
        from utils.public_key_utils import PublicKeyUtils
        from config import settings
        
        pk_utils = PublicKeyUtils(
            public_key_path=settings.public_key_path,
            verify_script_path=settings.verify_script_path
        )
        
        # Convert hex signature back to bytes
        signature_bytes = bytes.fromhex(signature_data['signature'])
        
        # Verify signature
        is_valid = pk_utils.verify_with_nonce(
            data_bytes,
            nonce_bytes,
            signature_bytes,
            algorithm="sha256"
        )
        
        if is_valid:
            print("✅ Signature verification successful!")
            return True
        else:
            print("❌ Signature verification failed!")
            return False
            
    except Exception as e:
        print(f"❌ Error verifying signature: {e}")
        return False

def main():
    """Main test function."""
    print("Starting signature verification test...")
    
    success = test_signature_verification()
    
    print("\n" + "=" * 40)
    if success:
        print("🎉 Signature verification test PASSED!")
        return 0
    else:
        print("❌ Signature verification test FAILED!")
        return 1

if __name__ == "__main__":
    sys.exit(main())
