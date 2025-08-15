#!/usr/bin/env python3
"""
Test script to verify the signature flow from agent to collector.
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

def test_signature_flow():
    """Test the complete signature flow."""
    print("🧪 Testing Signature Flow")
    print("=" * 40)
    
    # Step 1: Get nonce from gateway
    print("\n1. Getting nonce...")
    try:
        response = requests.get("https://localhost:8443/nonce", verify=False, timeout=5)
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
    
    # Step 2: Create test data (same as agent would)
    print("\n2. Creating test data...")
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
    
    # Combine data (same as agent)
    data_to_sign = {
        "metrics": test_metrics,
        "geographic_region": test_geographic_region
    }
    
    data_json = json.dumps(data_to_sign, sort_keys=True)
    data_bytes = data_json.encode('utf-8')
    nonce_bytes = nonce.encode('utf-8')
    
    print(f"✅ Test data created: {len(data_bytes)} bytes")
    
    # Step 3: Sign the data using TPM2
    print("\n3. Signing data with TPM2...")
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
    
    # Step 4: Create payload (same as agent)
    print("\n4. Creating payload...")
    payload = {
        "metrics": test_metrics,
        "geographic_region": test_geographic_region,
        "nonce": nonce,
        "signature": signature_data["signature"],
        "digest": signature_data["digest"],
        "algorithm": signature_data["algorithm"],
        "timestamp": "2025-08-15T15:30:00.000000"
    }
    
    print(f"✅ Payload created with {len(payload)} fields")
    
    # Step 5: Send to collector via gateway
    print("\n5. Sending to collector via gateway...")
    try:
        response = requests.post(
            "https://localhost:8443/metrics",
            json=payload,
            headers={"Content-Type": "application/json"},
            verify=False,
            timeout=10
        )
        
        print(f"Response status: {response.status_code}")
        print(f"Response body: {response.text}")
        
        if response.status_code == 200:
            print("✅ Metrics sent successfully!")
            return True
        else:
            print("❌ Failed to send metrics")
            return False
            
    except Exception as e:
        print(f"❌ Error sending metrics: {e}")
        return False

def main():
    """Main test function."""
    print("Starting signature flow test...")
    
    success = test_signature_flow()
    
    print("\n" + "=" * 40)
    if success:
        print("🎉 Signature flow test PASSED!")
        return 0
    else:
        print("❌ Signature flow test FAILED!")
        return 1

if __name__ == "__main__":
    sys.exit(main())
