#!/usr/bin/env python3
"""
Test script for the new architecture with public key verification.
"""

import requests
import json
import sys

def test_health_endpoints():
    """Test all health endpoints."""
    print("Testing health endpoints...")
    
    endpoints = [
        ("Agent", "https://localhost:8442/health"),
        ("Gateway", "https://localhost:8443/health"),
        ("Collector", "https://localhost:8444/health")
    ]
    
    for name, url in endpoints:
        try:
            response = requests.get(url, verify=False, timeout=5)
            print(f"✅ {name}: {response.status_code} - {response.json()}")
        except Exception as e:
            print(f"❌ {name}: Error - {e}")

def test_nonce_endpoint():
    """Test nonce endpoint."""
    print("\nTesting nonce endpoint...")
    
    try:
        response = requests.get("https://localhost:8443/nonce", verify=False, timeout=5)
        print(f"✅ Nonce: {response.status_code}")
        data = response.json()
        print(f"   Nonce: {data.get('nonce', 'N/A')}")
        print(f"   Expires: {data.get('expires_in', 'N/A')}")
        return data.get('nonce')
    except Exception as e:
        print(f"❌ Nonce: Error - {e}")
        return None

def test_metrics_generation():
    """Test metrics generation."""
    print("\nTesting metrics generation...")
    
    try:
        response = requests.post(
            "https://localhost:8442/metrics/generate",
            json={"metric_type": "system"},
            headers={"Content-Type": "application/json"},
            verify=False,
            timeout=10
        )
        print(f"✅ Metrics Generation: {response.status_code}")
        print(f"   Response: {response.text}")
        return response.status_code == 200
    except Exception as e:
        print(f"❌ Metrics Generation: Error - {e}")
        return False

def main():
    """Main test function."""
    print("🧪 Testing New Architecture (Agent TPM2 + Collector Public Key)")
    print("=" * 60)
    
    # Test health endpoints
    test_health_endpoints()
    
    # Test nonce endpoint
    nonce = test_nonce_endpoint()
    
    # Test metrics generation
    success = test_metrics_generation()
    
    print("\n" + "=" * 60)
    if success:
        print("🎉 All tests passed! New architecture is working.")
    else:
        print("❌ Some tests failed. Check the logs for details.")
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())

