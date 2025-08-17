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
        ("Agent (8401)", "https://localhost:8401/health"),
        ("Gateway (9000)", "https://localhost:9000/health"),
        ("Collector (8500)", "https://localhost:8500/health")
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
    with open("tpm/appsig_info.bin", "w") as f:
        f.write("test message for signing")
    
    tests = [
        ("Message Signing", "./tpm/sign_app_message.sh"),
        ("Signature Verification", "./tpm/verify_app_message_signature.sh"),
        ("Quote Generation", "./tpm/generate_quote.sh"),
        ("Quote Verification", "./tpm/verify_quote.sh"),
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

def test_end_to_end_multi_agent_nonce_and_sig_verification():
    """Test end-to-end multi-agent nonce handling and signature verification."""
    print("\n🔍 Testing End-to-End Multi-Agent Nonce & Signature Verification")
    print("=" * 40)
    
    import base64
    
    try:
        # Test 1: FAILURE - Nonce request without public key (should be rejected)
        print("🔍 Test 1: Nonce request without public key (should fail)")
        response = requests.get("https://localhost:9000/nonce", verify=False, timeout=5)
        if response.status_code == 400:
            print("✅ Correctly rejected nonce request without public key")
        else:
            print(f"❌ Expected 400, got {response.status_code}")
            return False
        
        # Test 2: SUCCESS - Nonce request with valid public key
        print("🔍 Test 2: Nonce request with valid public key (should succeed)")
        # Read agent-001's public key
        with open("tpm/agent-001_pubkey.pem", 'rb') as f:
            public_key_bytes = f.read()
        public_key_b64 = base64.b64encode(public_key_bytes).decode('utf-8')
        
        response = requests.get(f"https://localhost:9000/nonce?public_key={public_key_b64}", 
                              verify=False, timeout=5)
        if response.status_code == 200:
            data = response.json()
            if data.get("nonce") and data.get("agent_public_key_fingerprint"):
                print("✅ Successfully got nonce with valid public key")
                nonce = data.get("nonce")
            else:
                print("❌ Missing nonce or fingerprint in response")
                return False
        else:
            print(f"❌ Failed to get nonce: {response.status_code}")
            return False
        
        # Test 3: SUCCESS - Check nonce statistics
        print("🔍 Test 3: Nonce statistics (should show agent-001)")
        response = requests.get("https://localhost:9000/nonces/stats", verify=False, timeout=5)
        if response.status_code == 200:
            data = response.json()
            stats = data.get("nonce_statistics", {})
            agent_counts = stats.get("agent_nonce_counts", {})
            if len(agent_counts) > 0:
                print(f"✅ Nonce statistics show {len(agent_counts)} agent(s) with nonces")
            else:
                print("❌ No agents found in nonce statistics")
                return False
        else:
            print(f"❌ Failed to get nonce statistics: {response.status_code}")
            return False
        
        # Test 4: FAILURE - Metrics with invalid signature (should fail)
        print("🔍 Test 4: Metrics with invalid signature (should fail)")
        payload = {
            "agent_name": "agent-001",
            "tpm_public_key_path": "tpm/agent-001_pubkey.pem",
            "geolocation": {"country": "US", "state": "California", "city": "Santa Clara"},
            "metrics": {"service": {"name": "test-service"}, "timestamp": "2025-01-16T18:00:00Z"},
            "geographic_region": {"region": "US", "state": "California", "city": "Santa Clara"},
            "nonce": nonce,
            "signature": "invalid-signature",
            "digest": "invalid-digest",
            "algorithm": "sha256",
            "timestamp": "2025-01-16T18:00:00Z"
        }
        
        response = requests.post("https://localhost:9000/metrics", json=payload, verify=False, timeout=10)
        if response.status_code == 400:
            print("✅ Correctly rejected metrics with invalid signature")
        else:
            print(f"❌ Expected 400 for invalid signature, got {response.status_code}")
            return False
        
        # Test 4b: FAILURE - Metrics with wrong geolocation (should fail)
        print("🔍 Test 4b: Metrics with wrong geolocation (should fail)")
        payload = {
            "agent_name": "agent-001",
            "tpm_public_key_path": "tpm/agent-001_pubkey.pem",
            "geolocation": {"country": "EU", "state": "Germany", "city": "Berlin"},  # Wrong location
            "metrics": {"service": {"name": "test-service"}, "timestamp": "2025-01-16T18:00:00Z"},
            "geographic_region": {"region": "EU", "state": "Germany", "city": "Berlin"},
            "nonce": nonce,
            "signature": "invalid-signature",
            "digest": "invalid-digest", 
            "algorithm": "sha256",
            "timestamp": "2025-01-16T18:00:00Z"
        }
        
        response = requests.post("https://localhost:9000/metrics", json=payload, verify=False, timeout=10)
        if response.status_code == 400:
            print("✅ Correctly rejected metrics with wrong geolocation")
        else:
            print(f"❌ Expected 400 for wrong geolocation, got {response.status_code}")
            return False
        
        # Test 5: SUCCESS - Verify agent is in allowlist
        print("🔍 Test 5: Agent allowlist verification")
        response = requests.get("https://localhost:9000/agents", verify=False, timeout=5)
        if response.status_code == 200:
            data = response.json()
            allowed_agents = data.get("allowed_agents", [])
            agent_001_found = "agent-001" in allowed_agents
            if agent_001_found:
                print("✅ Agent-001 found in collector allowlist")
            else:
                print("❌ Agent-001 not found in collector allowlist")
                return False
        else:
            print(f"❌ Failed to get agents list: {response.status_code}")
            return False
        
        # Test 6: SUCCESS - Verify agent creation and setup
        print("🔍 Test 6: Agent creation and setup verification")
        # Check if agent config file exists
        agent_config_path = "agents/agent-001/config.json"
        if os.path.exists(agent_config_path):
            print("✅ Agent config file exists")
        else:
            print("❌ Agent config file not found")
            return False
        
        # Check if agent TPM files exist
        tpm_context_path = "tpm/agent-001.ctx"
        tpm_pubkey_path = "tpm/agent-001_pubkey.pem"
        if os.path.exists(tpm_context_path):
            print("✅ Agent TPM context file exists")
        else:
            print("❌ Agent TPM context file not found")
            return False
        
        if os.path.exists(tpm_pubkey_path):
            print("✅ Agent TPM public key file exists")
        else:
            print("❌ Agent TPM public key file not found")
            return False
        
        # Test 7: SUCCESS - Real end-to-end metrics generation (should succeed)
        print("🔍 Test 7: Real end-to-end metrics generation (should succeed)")
        try:
            # Call the agent's metrics generation endpoint
            response = requests.post("https://localhost:8401/metrics/generate", 
                                   json={"metric_type": "system"}, 
                                   verify=False, timeout=15)
            
            if response.status_code == 200:
                data = response.json()
                if data.get("status") == "success":
                    print("✅ Real end-to-end metrics generation succeeded")
                    print(f"   Payload ID: {data.get('payload_id', 'N/A')}")
                else:
                    print(f"❌ Metrics generation failed: {data.get('message', 'Unknown error')}")
                    return False
            else:
                print(f"❌ Metrics generation request failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Real end-to-end test failed: {e}")
            return False
        
        print("✅ All end-to-end multi-agent nonce & signature verification tests passed!")
        return True
        
    except Exception as e:
        print(f"❌ End-to-end multi-agent nonce & signature verification test: {e}")
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
    test_results.append(("End-to-End Multi-Agent Nonce & Sig Verification", test_end_to_end_multi_agent_nonce_and_sig_verification()))
    
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
