#!/usr/bin/env python3
"""
Comprehensive test summary for the edge-ai project.
"""

import sys
import os
import subprocess
import requests
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def run_command(cmd, description):
    """Run a command and return success status."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        return True
    except subprocess.CalledProcessError:
        return False

def test_services():
    """Test if all services are running."""
    print("🔍 Testing Services")
    print("=" * 30)
    
    services = [
        ("Agent (8442)", "https://localhost:8442/health"),
        ("Gateway (8443)", "https://localhost:8443/health"),
        ("Collector (8444)", "https://localhost:8444/health")
    ]
    
    all_healthy = True
    for name, url in services:
        try:
            response = requests.get(url, verify=False, timeout=5)
            if response.status_code == 200:
                print(f"✅ {name} - Healthy")
            else:
                print(f"❌ {name} - Unhealthy ({response.status_code})")
                all_healthy = False
        except Exception as e:
            print(f"❌ {name} - Error: {e}")
            all_healthy = False
    
    return all_healthy

def test_tpm2_basic():
    """Test basic TPM2 functionality."""
    print("\n🔍 Testing TPM2 Basic Functionality")
    print("=" * 40)
    
    tests = [
        ("TPM2 Properties", "tpm2_getcap properties-fixed"),
        ("Persistent Handles", "tpm2 getcap handles-persistent"),
        ("AppSK Public Key", "tpm2_readpublic -c 0x8101000B"),
        ("AK Public Key", "tpm2_readpublic -c 0x8101000A"),
        ("EK Public Key", "tpm2_readpublic -c 0x81010001"),
    ]
    
    passed = 0
    for desc, cmd in tests:
        if run_command(cmd, desc):
            print(f"✅ {desc}")
            passed += 1
        else:
            print(f"❌ {desc}")
    
    print(f"TPM2 Basic: {passed}/{len(tests)} tests passed")
    return passed == len(tests)

def test_signing_scripts():
    """Test signing shell scripts."""
    print("\n🔍 Testing Signing Shell Scripts")
    print("=" * 35)
    
    # Create test message
    with open("appsig_info.bin", "w") as f:
        f.write("test message for signing")
    
    tests = [
        ("Message Signing", "./sign_app_message.sh"),
        ("Signature Verification", "./verify_app_message_signature.sh"),
        ("Quote Generation & Verification", "./generate_verify_app_quote.sh"),
    ]
    
    passed = 0
    for desc, cmd in tests:
        if run_command(cmd, desc):
            print(f"✅ {desc}")
            passed += 1
        else:
            print(f"❌ {desc}")
    
    print(f"Signing Scripts: {passed}/{len(tests)} tests passed")
    return passed == len(tests)

def test_python_imports():
    """Test Python module imports."""
    print("\n🔍 Testing Python Module Imports")
    print("=" * 35)
    
    tests = [
        ("Config Import", "python3 -c 'from config import settings; print(\"Config loaded\")'"),
        ("TPM2Utils Import", "python3 -c 'from utils.tpm2_utils import TPM2Utils; print(\"TPM2Utils imported\")'"),
        ("PublicKeyUtils Import", "python3 -c 'from utils.public_key_utils import PublicKeyUtils; print(\"PublicKeyUtils imported\")'"),
    ]
    
    passed = 0
    for desc, cmd in tests:
        if run_command(cmd, desc):
            print(f"✅ {desc}")
            passed += 1
        else:
            print(f"❌ {desc}")
    
    print(f"Python Imports: {passed}/{len(tests)} tests passed")
    return passed == len(tests)

def test_python_utilities():
    """Test Python utility classes."""
    print("\n🔍 Testing Python Utilities")
    print("=" * 30)
    
    try:
        # Test TPM2Utils
        from utils.tpm2_utils import TPM2Utils
        tpm2_utils = TPM2Utils(use_swtpm=True)
        print("✅ TPM2Utils initialization")
        
        # Test basic signing
        test_data = b"test message for signing"
        signature = tpm2_utils.sign_data(test_data)
        if signature:
            print("✅ TPM2Utils signing")
        else:
            print("❌ TPM2Utils signing")
            return False
            
    except Exception as e:
        print(f"❌ TPM2Utils test: {e}")
        return False
    
    try:
        # Test PublicKeyUtils
        from utils.public_key_utils import PublicKeyUtils
        from config import settings
        
        pk_utils = PublicKeyUtils(
            public_key_path=settings.public_key_path,
            verify_script_path=settings.verify_script_path
        )
        print("✅ PublicKeyUtils initialization")
        
    except Exception as e:
        print(f"❌ PublicKeyUtils test: {e}")
        return False
    
    print("Python Utilities: All tests passed")
    return True

def test_end_to_end():
    """Test end-to-end functionality."""
    print("\n🔍 Testing End-to-End Functionality")
    print("=" * 40)
    
    try:
        # Test nonce generation
        response = requests.get("https://localhost:8443/nonce", verify=False, timeout=5)
        if response.status_code == 200:
            print("✅ Nonce generation")
        else:
            print("❌ Nonce generation")
            return False
        
        # Test metrics generation (this might fail due to signature issues)
        response = requests.post(
            "https://localhost:8442/metrics/generate",
            json={"metric_type": "system"},
            headers={"Content-Type": "application/json"},
            verify=False,
            timeout=10
        )
        
        if response.status_code == 200:
            print("✅ Metrics generation and sending")
            return True
        else:
            print(f"⚠️  Metrics generation failed (expected due to signature issues): {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ End-to-end test: {e}")
        return False

def main():
    """Main test function."""
    print("🧪 COMPREHENSIVE TEST SUMMARY")
    print("=" * 50)
    
    test_results = []
    
    # Run all tests
    test_results.append(("Services", test_services()))
    test_results.append(("TPM2 Basic", test_tpm2_basic()))
    test_results.append(("Signing Scripts", test_signing_scripts()))
    test_results.append(("Python Imports", test_python_imports()))
    test_results.append(("Python Utilities", test_python_utilities()))
    test_results.append(("End-to-End", test_end_to_end()))
    
    # Summary
    print("\n" + "=" * 50)
    print("📊 TEST SUMMARY")
    print("=" * 50)
    
    passed = 0
    total = len(test_results)
    
    for test_name, result in test_results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name:<20} {status}")
        if result:
            passed += 1
    
    print(f"\nOverall: {passed}/{total} test categories passed")
    
    if passed == total:
        print("🎉 ALL TESTS PASSED! System is working correctly.")
        return 0
    else:
        print("⚠️  Some tests failed. Check the details above.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
