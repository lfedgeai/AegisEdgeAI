#!/usr/bin/env python3
"""
Debug script to trace signature data mismatch.
"""

import sys
import os
import json
from datetime import datetime

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def debug_signature_data():
    """Debug the signature data mismatch."""
    print("🔍 Debugging Signature Data Mismatch")
    print("=" * 40)
    
    # Simulate agent's data generation
    from agent.app import MetricsGenerator
    from config import settings
    
    # Generate metrics (this creates timestamp)
    metrics_data = MetricsGenerator.generate_system_metrics()
    print(f"Generated metrics timestamp: {metrics_data.get('timestamp')}")
    
    # Create geographic region
    geographic_region = {
        "region": settings.geographic_region,
        "state": settings.geographic_state,
        "city": settings.geographic_city
    }
    
    # Combine data (same as agent)
    data_to_sign = {
        "metrics": metrics_data,
        "geographic_region": geographic_region
    }
    
    # Serialize (same as agent)
    data_json = json.dumps(data_to_sign, sort_keys=True)
    print(f"Agent data JSON length: {len(data_json)}")
    print(f"Agent data JSON (first 200 chars): {data_json[:200]}...")
    
    # Now simulate collector's reconstruction
    # Collector receives the same metrics_data and geographic_region
    data_to_verify = {
        "metrics": metrics_data,
        "geographic_region": geographic_region
    }
    
    # Serialize (same as collector)
    verify_json = json.dumps(data_to_verify, sort_keys=True)
    print(f"Collector data JSON length: {len(verify_json)}")
    print(f"Collector data JSON (first 200 chars): {verify_json[:200]}...")
    
    # Check if they match
    if data_json == verify_json:
        print("✅ Data structures match!")
        return True
    else:
        print("❌ Data structures don't match!")
        print(f"Difference: {data_json != verify_json}")
        return False

if __name__ == "__main__":
    debug_signature_data()

