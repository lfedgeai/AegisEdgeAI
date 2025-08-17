#!/usr/bin/env python3
"""
Test script to verify agent's TPM signing capability.
"""

import os
import sys
import json
from datetime import datetime

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from config import settings
from utils.tpm2_utils import TPM2Utils

def test_agent_tpm():
    """Test agent's TPM signing capability."""
    
    print("🔍 Testing Agent TPM Signing")
    print("=" * 40)
    
    # Check if agent-001 config exists
    agent_config_path = "agents/agent-001/config.json"
    if not os.path.exists(agent_config_path):
        print("❌ Agent-001 config not found")
        return False
    
    # Load agent config
    with open(agent_config_path, 'r') as f:
        agent_config = json.load(f)
    
    print(f"✅ Agent config loaded: {agent_config['agent_name']}")
    print(f"   TPM context: {agent_config['tpm_context_file']}")
    print(f"   Public key: {agent_config['tpm_public_key_path']}")
    
    # Check if TPM files exist
    tpm_context = agent_config['tpm_context_file']
    tpm_pubkey = agent_config['tpm_public_key_path']
    
    if not os.path.exists(tpm_context):
        print(f"❌ TPM context file not found: {tpm_context}")
        return False
    
    if not os.path.exists(tpm_pubkey):
        print(f"❌ TPM public key file not found: {tpm_pubkey}")
        return False
    
    print(f"✅ TPM files exist")
    
    # Test TPM2Utils initialization
    try:
        tpm2_utils = TPM2Utils(
            app_ctx_path=tpm_context,
            device=settings.tpm2_device,
            use_swtpm=True
        )
        print("✅ TPM2Utils initialized successfully")
    except Exception as e:
        print(f"❌ TPM2Utils initialization failed: {e}")
        return False
    
    # Test signing
    try:
        test_data = b"test data for signing"
        test_nonce = b"test nonce"
        
        signature_data = tpm2_utils.sign_with_nonce(
            test_data,
            test_nonce,
            algorithm="sha256"
        )
        
        print("✅ TPM signing successful")
        print(f"   Signature: {signature_data['signature'][:32]}...")
        print(f"   Digest: {signature_data['digest'][:32]}...")
        print(f"   Algorithm: {signature_data['algorithm']}")
        
        return True
        
    except Exception as e:
        print(f"❌ TPM signing failed: {e}")
        return False

if __name__ == "__main__":
    success = test_agent_tpm()
    if success:
        print("\n🎉 Agent TPM signing test passed!")
    else:
        print("\n❌ Agent TPM signing test failed!")
        sys.exit(1)
