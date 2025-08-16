#!/usr/bin/env python3
"""
Test script to verify public key payload functionality.
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

def test_public_key_payload():
    """Test the public key payload functionality."""
    print("🧪 Testing Public Key Payload Functionality")
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
        "timestamp": "2025-08-15T18:45:00.000000",
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
        "timestamp": "2025-08-15T18:45:00.000000",
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
            print("✅ Metrics sent successfully with public key!")
            return True
        else:
            print("❌ Failed to send metrics")
            return False
            
    except Exception as e:
        print(f"❌ Error sending metrics: {e}")
        return False

def test_collector_health():
    """Test collector health endpoint."""
    print("\n🔍 Testing Collector Health")
    print("=" * 30)
    
    try:
        response = requests.get("https://localhost:8444/health", verify=False, timeout=5)
        if response.status_code == 200:
            health_data = response.json()
            print(f"✅ Collector health: {health_data.get('status')}")
            print(f"   Public key allowlist enabled: {health_data.get('public_key_allowlist_enabled')}")
            return True
        else:
            print(f"❌ Collector health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error checking collector health: {e}")
        return False

def main():
    """Main test function."""
    print("🧪 Public Key Payload Test Suite")
    print("=" * 50)
    
    # Test collector health first
    if not test_collector_health():
        print("❌ Collector health check failed, aborting tests")
        return False
    
    # Test public key payload functionality
    if test_public_key_payload():
        print("\n🎉 All tests passed!")
        return True
    else:
        print("\n❌ Some tests failed!")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
