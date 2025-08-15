#!/usr/bin/env python3
"""
Test script for public key verification.
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils.public_key_utils import PublicKeyUtils
from config import settings

def test_public_key_verification():
    """Test public key verification."""
    print("Testing public key verification...")
    
    try:
        # Initialize public key utils
        public_key_utils = PublicKeyUtils(
            public_key_path=settings.public_key_path,
            verify_script_path=settings.verify_script_path
        )
        print("✅ PublicKeyUtils initialized successfully")
        
        # Test data
        test_data = b"test message for verification"
        test_nonce = b"test_nonce_123"
        combined_data = test_data + test_nonce
        
        # Create a signature using the TPM2 script for the combined data
        print("Creating test signature...")
        with open("tpm/appsig_info.bin", "wb") as f:
            f.write(combined_data)
        os.system("./tpm/sign_app_message.sh")
        
        if not os.path.exists("tpm/appsig.bin"):
            print("❌ Failed to create signature")
            return False
        
        # Read the signature
        with open("tpm/appsig.bin", "rb") as f:
            signature = f.read()
        
        print(f"✅ Signature created: {len(signature)} bytes")
        
        # Test verification
        print("Testing signature verification...")
        is_valid = public_key_utils.verify_signature(combined_data, signature)
        
        if is_valid:
            print("✅ Signature verification successful!")
        else:
            print("❌ Signature verification failed!")
        
        # Cleanup
        os.system("rm -f tpm/appsig_info.bin tpm/appsig.bin tpm/appsig_info.hash")
        
        return is_valid
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    success = test_public_key_verification()
    sys.exit(0 if success else 1)






