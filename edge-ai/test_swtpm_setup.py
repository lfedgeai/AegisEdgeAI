#!/usr/bin/env python3
"""
Test script to verify software TPM (swtpm) setup with persistent keys.

This script tests:
1. swtpm accessibility
2. TPM2 initialization
3. Persistent key handles
4. Basic TPM2 operations
"""

import os
import sys
import subprocess
import structlog

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from config import settings

# Configure logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger(__name__)


def test_swtpm_access() -> bool:
    """Test if swtpm is accessible."""
    try:
        env = os.environ.copy()
        env['TPM2TOOLS_TCTI'] = settings.tpm2tools_tcti
        
        result = subprocess.run(
            ["tpm2_getcap", "properties-fixed"],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            logger.info("✓ swtpm is accessible")
            return True
        else:
            logger.error(f"✗ swtpm not accessible: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"✗ Error testing swtpm access: {e}")
        return False


def test_persistent_handles() -> bool:
    """Test if persistent handles are available."""
    try:
        env = os.environ.copy()
        env['TPM2TOOLS_TCTI'] = settings.tpm2tools_tcti
        
        result = subprocess.run(
            ["tpm2", "getcap", "handles-persistent"],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            handles = result.stdout.strip().split('\n')
            logger.info("✓ Persistent handles found:")
            for handle in handles:
                if handle.strip():
                    logger.info(f"  {handle.strip()}")
            
            # Check for required handles
            required_handles = [settings.ek_handle, settings.ak_handle, settings.app_handle]
            found_handles = [h.strip() for h in handles if h.strip()]
            
            for required in required_handles:
                if required in found_handles:
                    logger.info(f"  ✓ {required} (EK)")
                else:
                    logger.warning(f"  ⚠ {required} not found")
            
            return True
        else:
            logger.error(f"✗ Failed to get persistent handles: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"✗ Error testing persistent handles: {e}")
        return False


def test_context_files() -> bool:
    """Test if required context files exist."""
    required_files = ["ek.ctx", "ak.ctx", "app.ctx", "primary.ctx"]
    missing_files = []
    
    for file in required_files:
        if os.path.exists(file):
            logger.info(f"✓ {file} exists")
        else:
            logger.warning(f"⚠ {file} missing")
            missing_files.append(file)
    
    if missing_files:
        logger.warning(f"Missing context files: {missing_files}")
        return False
    
    return True


def test_basic_operations() -> bool:
    """Test basic TPM2 operations."""
    try:
        env = os.environ.copy()
        env['TPM2TOOLS_TCTI'] = settings.tpm2tools_tcti
        
        # Test hash operation
        logger.info("Testing hash operation...")
        result = subprocess.run(
            ["tpm2_hash", "-C", "o", "-g", "sha256", "-o", "test_hash.bin"],
            input=b"test data",
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            logger.info("✓ Hash operation successful")
        else:
            logger.error(f"✗ Hash operation failed: {result.stderr}")
            return False
        
        # Test random number generation
        logger.info("Testing random number generation...")
        result = subprocess.run(
            ["tpm2_getrandom", "16", "-o", "test_random.bin"],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            logger.info("✓ Random number generation successful")
        else:
            logger.error(f"✗ Random number generation failed: {result.stderr}")
            return False
        
        # Cleanup test files
        for test_file in ["test_hash.bin", "test_random.bin"]:
            if os.path.exists(test_file):
                os.remove(test_file)
        
        return True
        
    except Exception as e:
        logger.error(f"✗ Error testing basic operations: {e}")
        return False


def test_key_operations() -> bool:
    """Test key operations using persistent handles."""
    try:
        env = os.environ.copy()
        env['TPM2TOOLS_TCTI'] = settings.tpm2tools_tcti
        
        # Test reading public key from AppSK
        logger.info("Testing AppSK public key read...")
        result = subprocess.run(
            ["tpm2_readpublic", "-c", settings.app_handle],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            logger.info("✓ AppSK public key read successful")
        else:
            logger.error(f"✗ AppSK public key read failed: {result.stderr}")
            return False
        
        # Test reading public key from AK
        logger.info("Testing AK public key read...")
        result = subprocess.run(
            ["tpm2_readpublic", "-c", settings.ak_handle],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            logger.info("✓ AK public key read successful")
        else:
            logger.error(f"✗ AK public key read failed: {result.stderr}")
            return False
        
        return True
        
    except Exception as e:
        logger.error(f"✗ Error testing key operations: {e}")
        return False


def main():
    """Main test function."""
    logger.info("Testing Software TPM (swtpm) Setup")
    logger.info("=" * 50)
    
    tests = [
        ("swtpm Access", test_swtpm_access),
        ("Context Files", test_context_files),
        ("Persistent Handles", test_persistent_handles),
        ("Basic Operations", test_basic_operations),
        ("Key Operations", test_key_operations),
    ]
    
    passed = 0
    total = len(tests)
    
    for test_name, test_func in tests:
        logger.info(f"\nRunning test: {test_name}")
        try:
            if test_func():
                logger.info(f"✓ {test_name} passed")
                passed += 1
            else:
                logger.error(f"✗ {test_name} failed")
        except Exception as e:
            logger.error(f"✗ {test_name} failed with exception: {e}")
    
    logger.info(f"\nTest Results: {passed}/{total} tests passed")
    
    if passed == total:
        logger.info("🎉 All tests passed! Software TPM setup is working correctly.")
        sys.exit(0)
    else:
        logger.error("❌ Some tests failed. Please check the setup.")
        sys.exit(1)


if __name__ == "__main__":
    main()
