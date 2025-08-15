#!/usr/bin/env python3
"""
Simple test script to verify configuration loading.
"""

import sys
import os

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

try:
    from config import settings
    print("✓ Configuration loaded successfully")
    print(f"TPM2TOOLS_TCTI: {settings.tpm2tools_tcti}")
    print(f"SWTPM_PORT: {settings.swtpm_port}")
    print(f"EK_HANDLE: {settings.ek_handle}")
    print(f"AK_HANDLE: {settings.ak_handle}")
    print(f"APP_HANDLE: {settings.app_handle}")
except Exception as e:
    print(f"✗ Configuration loading failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
