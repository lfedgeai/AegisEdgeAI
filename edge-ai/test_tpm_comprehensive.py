#!/usr/bin/env python3
"""
Comprehensive TPM test script.
Tests all TPM-related functionality in the edge-ai project.
"""

import sys
import os
import subprocess
import time

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def run_command(cmd, description):
    """Run a command and return success status."""
    print(f"Testing: {description}")
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        print(f"✅ {description} - SUCCESS")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ {description} - FAILED")
        print(f"   Error: {e.stderr}")
        return False

def test_python_imports():
    """Test Python module imports."""
    print("\n=== Testing Python Module Imports ===")
    
    tests = [
        ("config import", "python3 -c 'from config import settings; print(\"Config loaded\")'"),
        ("TPM2Utils import", "python3 -c 'from utils.tpm2_utils import TPM2Utils; print(\"TPM2Utils imported\")'"),
        ("PublicKeyUtils import", "python3 -c 'from utils.public_key_utils import PublicKeyUtils; print(\"PublicKeyUtils imported\")'"),
    ]
    
    success = True
    for desc, cmd in tests:
        if not run_command(cmd, desc):
            success = False
    
    return success

def test_tpm2_commands():
    """Test TPM2 command line tools."""
    print("\n=== Testing TPM2 Commands ===")
    
    tests = [
        ("TPM2 properties", "tpm2_getcap properties-fixed"),
        ("Persistent handles", "tpm2 getcap handles-persistent"),
        ("AppSK public key", "tpm2_readpublic -c 0x8101000B"),
        ("AK public key", "tpm2_readpublic -c 0x8101000A"),
        ("EK public key", "tpm2_readpublic -c 0x81010001"),
    ]
    
    success = True
    for desc, cmd in tests:
        if not run_command(cmd, desc):
            success = False
    
    return success

def test_signing_operations():
    """Test signing operations."""
    print("\n=== Testing Signing Operations ===")
    
    # Create test message first
    with open("tpm/appsig_info.bin", "w") as f:
        f.write("test message for signing")
    
    tests = [
        ("Message signing", "./tpm/sign_app_message.sh"),
        ("Signature verification", "./tpm/verify_app_message_signature.sh"),
        ("Quote generation", "./tpm/generate_quote.sh"),
        ("Quote verification", "./tpm/verify_quote.sh"),
    ]
    
    success = True
    for desc, cmd in tests:
        if not run_command(cmd, desc):
            success = False
    
    return success

def test_python_utilities():
    """Test Python utility classes."""
    print("\n=== Testing Python Utilities ===")
    
    # Test TPM2Utils
    try:
        from utils.tpm2_utils import TPM2Utils
        tpm2_utils = TPM2Utils(use_swtpm=True)
        print("✅ TPM2Utils initialization - SUCCESS")
        
        # Test basic operations
        test_data = b"test message for signing"
        signature = tpm2_utils.sign_data(test_data)
        if signature:
            print("✅ TPM2Utils signing - SUCCESS")
        else:
            print("❌ TPM2Utils signing - FAILED")
            return False
            
    except Exception as e:
        print(f"❌ TPM2Utils test - FAILED: {e}")
        return False
    
    # Test PublicKeyUtils
    try:
        from utils.public_key_utils import PublicKeyUtils
        from config import settings
        
        pk_utils = PublicKeyUtils(
            public_key_path=settings.public_key_path,
            verify_script_path=settings.verify_script_path
        )
        print("✅ PublicKeyUtils initialization - SUCCESS")
        
        # Test verification with simple data
        test_data = b"test message for verification"
        
        # Create a signature first
        with open("tpm/appsig_info.bin", "wb") as f:
            f.write(test_data)
        os.system("./tpm/sign_app_message.sh")
        
        if os.path.exists("tpm/appsig.bin"):
            with open("tpm/appsig.bin", "rb") as f:
                signature = f.read()
            
            is_valid = pk_utils.verify_signature(test_data, signature)
            if is_valid:
                print("✅ PublicKeyUtils verification - SUCCESS")
            else:
                print("❌ PublicKeyUtils verification - FAILED")
                return False
        else:
            print("❌ Could not create test signature")
            return False
            
        # Cleanup
        os.system("rm -f tpm/appsig_info.bin tpm/appsig.bin tpm/appsig_info.hash")
        
    except Exception as e:
        print(f"❌ PublicKeyUtils test - FAILED: {e}")
        return False
    
    return True

def main():
    """Main test function."""
    print("🧪 Comprehensive TPM Testing")
    print("=" * 50)
    
    all_tests = [
        ("Python Imports", test_python_imports),
        ("TPM2 Commands", test_tpm2_commands),
        ("Signing Operations", test_signing_operations),
        ("Python Utilities", test_python_utilities),
    ]
    
    passed = 0
    total = len(all_tests)
    
    for test_name, test_func in all_tests:
        print(f"\n{'='*20} {test_name} {'='*20}")
        try:
            if test_func():
                passed += 1
                print(f"✅ {test_name} - ALL TESTS PASSED")
            else:
                print(f"❌ {test_name} - SOME TESTS FAILED")
        except Exception as e:
            print(f"❌ {test_name} - EXCEPTION: {e}")
    
    print(f"\n{'='*50}")
    print(f"Test Results: {passed}/{total} test suites passed")
    
    if passed == total:
        print("🎉 ALL TPM TESTS PASSED! TPM functionality is working correctly.")
        return 0
    else:
        print("❌ Some TPM tests failed. Please check the setup.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
