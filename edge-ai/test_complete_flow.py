#!/usr/bin/env python3
"""
Test script to verify the complete flow from agent to collector.
"""

import requests
import json
import sys
import os

# Disable SSL warnings
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def test_complete_flow():
    """Test the complete flow from agent to collector."""
    print("🧪 Testing Complete Flow (Agent -> Gateway -> Collector)")
    print("=" * 60)
    
    # Test 1: Get nonce from gateway
    print("\n1. Getting nonce from gateway...")
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
    
    # Test 2: Generate metrics from agent
    print("\n2. Generating metrics from agent...")
    try:
        response = requests.post(
            "https://localhost:8442/metrics/generate",
            json={"metric_type": "system"},
            headers={"Content-Type": "application/json"},
            verify=False,
            timeout=10
        )
        print(f"Response status: {response.status_code}")
        print(f"Response body: {response.text}")
        
        if response.status_code == 200:
            print("✅ Metrics generated successfully")
            return True
        else:
            print("❌ Metrics generation failed")
            return False
            
    except Exception as e:
        print(f"❌ Error generating metrics: {e}")
        return False

def test_individual_components():
    """Test individual components separately."""
    print("\n🔍 Testing Individual Components")
    print("=" * 40)
    
    # Test agent health
    print("\n1. Agent health check...")
    try:
        response = requests.get("https://localhost:8442/health", verify=False, timeout=5)
        print(f"Agent status: {response.status_code}")
        if response.status_code == 200:
            print("✅ Agent is healthy")
        else:
            print("❌ Agent health check failed")
    except Exception as e:
        print(f"❌ Agent error: {e}")
    
    # Test gateway health
    print("\n2. Gateway health check...")
    try:
        response = requests.get("https://localhost:8443/health", verify=False, timeout=5)
        print(f"Gateway status: {response.status_code}")
        if response.status_code == 200:
            print("✅ Gateway is healthy")
        else:
            print("❌ Gateway health check failed")
    except Exception as e:
        print(f"❌ Gateway error: {e}")
    
    # Test collector health
    print("\n3. Collector health check...")
    try:
        response = requests.get("https://localhost:8444/health", verify=False, timeout=5)
        print(f"Collector status: {response.status_code}")
        if response.status_code == 200:
            print("✅ Collector is healthy")
        else:
            print("❌ Collector health check failed")
    except Exception as e:
        print(f"❌ Collector error: {e}")

def main():
    """Main test function."""
    print("Starting complete flow test...")
    
    # Test individual components first
    test_individual_components()
    
    # Test complete flow
    success = test_complete_flow()
    
    print("\n" + "=" * 60)
    if success:
        print("🎉 Complete flow test PASSED!")
        return 0
    else:
        print("❌ Complete flow test FAILED!")
        return 1

if __name__ == "__main__":
    sys.exit(main())
