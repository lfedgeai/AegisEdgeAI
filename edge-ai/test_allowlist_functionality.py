#!/usr/bin/env python3
"""
Test script to demonstrate the complete allowlist functionality.
"""

import sys
import os
import json
import requests
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def test_allowlist_management():
    """Test allowlist management endpoints."""
    print("🧪 Testing Allowlist Management")
    print("=" * 40)
    
    # Test 1: Get current allowlist
    print("\n1. Getting current allowlist...")
    try:
        response = requests.get("https://localhost:8444/allowlist/keys", verify=False, timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Allowlist retrieved: {data['count']} keys")
            for key in data['allowed_keys']:
                print(f"   - {key['name']} (ID: {key['id']})")
        else:
            print(f"❌ Failed to get allowlist: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error getting allowlist: {e}")
        return False
    
    # Test 2: Add a new key
    print("\n2. Adding a new test key...")
    try:
        new_key_data = {
            "id": "test-key-001",
            "name": "Test Application Key",
            "description": "Test key for demonstration",
            "public_key_path": "tpm/appsk_pubkey.pem",
            "fingerprint": "sha256:test_fingerprint",
            "allowed_regions": ["US"],
            "allowed_services": ["test-service"]
        }
        
        response = requests.post(
            "https://localhost:8444/allowlist/keys",
            json=new_key_data,
            headers={"Content-Type": "application/json"},
            verify=False,
            timeout=5
        )
        
        if response.status_code == 200:
            print("✅ Test key added successfully")
        else:
            print(f"❌ Failed to add test key: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Error adding test key: {e}")
        return False
    
    # Test 3: Verify key was added
    print("\n3. Verifying key was added...")
    try:
        response = requests.get("https://localhost:8444/allowlist/keys", verify=False, timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Allowlist now has {data['count']} keys")
            test_key = next((k for k in data['allowed_keys'] if k['id'] == 'test-key-001'), None)
            if test_key:
                print(f"   - Test key found: {test_key['name']}")
            else:
                print("   - Test key not found")
                return False
        else:
            print(f"❌ Failed to verify allowlist: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error verifying allowlist: {e}")
        return False
    
    # Test 4: Remove test key
    print("\n4. Removing test key...")
    try:
        response = requests.delete(
            "https://localhost:8444/allowlist/keys/test-key-001",
            verify=False,
            timeout=5
        )
        
        if response.status_code == 200:
            print("✅ Test key removed successfully")
        else:
            print(f"❌ Failed to remove test key: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Error removing test key: {e}")
        return False
    
    # Test 5: Verify key was removed
    print("\n5. Verifying key was removed...")
    try:
        response = requests.get("https://localhost:8444/allowlist/keys", verify=False, timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Allowlist now has {data['count']} keys")
            test_key = next((k for k in data['allowed_keys'] if k['id'] == 'test-key-001'), None)
            if not test_key:
                print("   - Test key successfully removed")
            else:
                print("   - Test key still present")
                return False
        else:
            print(f"❌ Failed to verify allowlist: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error verifying allowlist: {e}")
        return False
    
    return True

def test_public_key_payload_with_allowlist():
    """Test public key payload functionality with allowlist enabled."""
    print("\n🧪 Testing Public Key Payload with Allowlist")
    print("=" * 50)
    
    # Step 1: Get nonce from collector
    print("\n1. Getting nonce from collector...")
    try:
        response = requests.get("https://localhost:8444/nonce", verify=False, timeout=5)
        if response.status_code == 200:
            nonce_data = response.json()
            nonce = nonce_data.get('nonce')
            print(f"✅ Nonce received: {nonce[:16]}...")
        else:
            print(f"❌ Failed to get nonce: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error getting nonce: {e}")
        return False
    
    # Step 2: Read public key
    print("\n2. Reading public key...")
    try:
        with open("tpm/appsk_pubkey.pem", 'r') as f:
            public_key_data = f.read()
        print(f"✅ Public key read: {len(public_key_data)} characters")
    except Exception as e:
        print(f"❌ Error reading public key: {e}")
        return False
    
    # Step 3: Create test data
    print("\n3. Creating test data...")
    test_metrics = {
        "timestamp": "2025-08-15T19:35:00.000000",
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
    
    # Step 4: Sign the data using TPM2
    print("\n4. Signing data with TPM2...")
    try:
        from utils.tpm2_utils import TPM2Utils
        
        tpm2_utils = TPM2Utils(use_swtpm=True)
        
        # Combine data (same as agent)
        data_to_sign = {
            "metrics": test_metrics,
            "geographic_region": test_geographic_region
        }
        
        data_json = json.dumps(data_to_sign, sort_keys=True)
        data_bytes = data_json.encode('utf-8')
        nonce_bytes = nonce.encode('utf-8')
        
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
    
    # Step 5: Create payload with public key
    print("\n5. Creating payload with public key...")
    payload = {
        "metrics": test_metrics,
        "geographic_region": test_geographic_region,
        "nonce": nonce,
        "signature": signature_data["signature"],
        "digest": signature_data["digest"],
        "algorithm": signature_data["algorithm"],
        "timestamp": "2025-08-15T19:35:00.000000",
        "public_key": public_key_data
    }
    
    print(f"✅ Payload created with public key: {len(payload)} fields")
    
    # Step 6: Send to collector
    print("\n6. Sending to collector...")
    try:
        response = requests.post(
            "https://localhost:8444/metrics",
            json=payload,
            headers={"Content-Type": "application/json"},
            verify=False,
            timeout=10
        )
        
        print(f"Response status: {response.status_code}")
        print(f"Response body: {response.text}")
        
        if response.status_code == 200:
            print("✅ Metrics sent successfully with public key and allowlist!")
            return True
        else:
            print("❌ Failed to send metrics")
            return False
            
    except Exception as e:
        print(f"❌ Error sending metrics: {e}")
        return False

def main():
    """Main test function."""
    print("🧪 Allowlist Functionality Test Suite")
    print("=" * 60)
    
    # Test allowlist management
    if not test_allowlist_management():
        print("\n❌ Allowlist management tests failed!")
        return False
    
    # Test public key payload with allowlist
    if not test_public_key_payload_with_allowlist():
        print("\n❌ Public key payload with allowlist tests failed!")
        return False
    
    print("\n🎉 All allowlist functionality tests passed!")
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
