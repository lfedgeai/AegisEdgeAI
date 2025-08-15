#!/usr/bin/env python3
"""
Software TPM (swtpm) startup script for the OpenTelemetry microservice architecture.

This script starts and initializes the software TPM using swtpm, which is required
before starting the microservices that use TPM2 operations.
"""

import os
import sys
import time
import signal
import subprocess
import threading
from pathlib import Path
from typing import Optional
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

# Global process for cleanup
swtpm_process: Optional[subprocess.Popen] = None


def signal_handler(signum, frame):
    """Handle shutdown signals."""
    logger.info("Received shutdown signal, stopping swtpm...")
    stop_swtpm()
    sys.exit(0)


def stop_swtpm():
    """Stop the swtpm process."""
    global swtpm_process
    
    if swtpm_process and swtpm_process.poll() is None:
        logger.info("Stopping swtpm process...")
        swtpm_process.terminate()
        try:
            swtpm_process.wait(timeout=10)
            logger.info("swtpm stopped gracefully")
        except subprocess.TimeoutExpired:
            logger.warning("Force killing swtpm process")
            swtpm_process.kill()
    
    # Also kill any remaining swtpm processes
    try:
        subprocess.run(["pkill", "-f", "swtpm"], check=False)
        logger.info("Killed any remaining swtpm processes")
    except Exception as e:
        logger.warning(f"Error killing swtpm processes: {e}")


def check_swtpm_installed() -> bool:
    """Check if swtpm is installed."""
    try:
        result = subprocess.run(["swtpm", "--version"], 
                              capture_output=True, text=True, check=False)
        return result.returncode == 0
    except FileNotFoundError:
        return False


def check_tpm2_tools_installed() -> bool:
    """Check if tpm2-tools is installed."""
    try:
        result = subprocess.run(["tpm2_getcap", "--version"], 
                              capture_output=True, text=True, check=False)
        return result.returncode == 0
    except FileNotFoundError:
        return False


def start_swtpm() -> subprocess.Popen:
    """
    Start the software TPM (swtpm).
    
    Returns:
        Subprocess process object
    """
    global swtpm_process
    
    # Set environment variables
    swtpm_dir = os.path.expandvars(settings.swtpm_dir)
    swtpm_port = settings.swtpm_port
    swtpm_ctrl = settings.swtpm_ctrl
    
    # Kill any existing swtpm processes
    try:
        subprocess.run(["pkill", "-f", "swtpm"], check=False)
        logger.info("Killed any existing swtpm processes")
    except Exception as e:
        logger.warning(f"Error killing existing swtpm processes: {e}")
    
    # Remove and recreate swtpm directory
    try:
        import shutil
        if os.path.exists(swtpm_dir):
            shutil.rmtree(swtpm_dir)
        os.makedirs(swtpm_dir, exist_ok=True)
        logger.info(f"Prepared swtpm directory: {swtpm_dir}")
    except Exception as e:
        logger.error(f"Error preparing swtpm directory: {e}")
        raise
    
    # Start swtpm
    cmd = [
        "swtpm", "socket", "--tpm2",
        "--server", f"type=tcp,port={swtpm_port}",
        "--ctrl", f"type=tcp,port={swtpm_ctrl}",
        "--tpmstate", f"dir={swtpm_dir}",
        "--flags", "not-need-init"
    ]
    
    try:
        swtpm_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        
        logger.info(f"Started swtpm on port {swtpm_port}")
        return swtpm_process
        
    except Exception as e:
        logger.error(f"Failed to start swtpm: {e}")
        raise


def initialize_tpm2() -> bool:
    """
    Initialize TPM2 after swtpm is started.
    
    Returns:
        True if successful, False otherwise
    """
    try:
        # Set environment variable for tpm2-tools
        env = os.environ.copy()
        env['TPM2TOOLS_TCTI'] = settings.tpm2tools_tcti
        
        # Wait a moment for swtpm to be ready
        time.sleep(2)
        
        # Initialize TPM2
        logger.info("Initializing TPM2...")
        result = subprocess.run(
            ["tpm2", "startup", "-c"],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode != 0:
            logger.error(f"TPM2 startup failed: {result.stderr}")
            return False
        
        # Test TPM2 access
        logger.info("Testing TPM2 access...")
        result = subprocess.run(
            ["tpm2", "getcap", "properties-fixed"],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode != 0:
            logger.error(f"TPM2 test failed: {result.stderr}")
            return False
        
        logger.info("TPM2 initialized successfully")
        return True
        
    except Exception as e:
        logger.error(f"Error initializing TPM2: {e}")
        return False


def run_tpm_persistence_scripts() -> bool:
    """
    Run TPM2 persistence scripts to set up EK, AK, and AppSK.
    
    Returns:
        True if successful, False otherwise
    """
    try:
        # Set environment variables for the scripts
        env = os.environ.copy()
        env.update({
            'TPM2TOOLS_TCTI': settings.tpm2tools_tcti,
            'SWTPM_PORT': str(settings.swtpm_port),
            'EK_HANDLE': settings.ek_handle,
            'AK_HANDLE': settings.ak_handle,
            'APP_HANDLE': settings.app_handle
        })
        
        # Check if persistence scripts exist
        ek_ak_script = "tpm-ek-ak-persist.sh"
        app_script = "tpm-app-persist.sh"
        
        if not os.path.exists(ek_ak_script):
            logger.error(f"Persistence script not found: {ek_ak_script}")
            return False
        
        if not os.path.exists(app_script):
            logger.error(f"Persistence script not found: {app_script}")
            return False
        
        # Run EK/AK persistence script
        logger.info("Running EK/AK persistence script...")
        result = subprocess.run(
            ["bash", ek_ak_script],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode != 0:
            logger.error(f"EK/AK persistence failed: {result.stderr}")
            return False
        
        logger.info("EK/AK persistence completed successfully")
        
        # Run AppSK persistence script
        logger.info("Running AppSK persistence script...")
        result = subprocess.run(
            ["bash", app_script],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode != 0:
            logger.error(f"AppSK persistence failed: {result.stderr}")
            return False
        
        logger.info("AppSK persistence completed successfully")
        
        # Verify persistent handles
        logger.info("Verifying persistent handles...")
        result = subprocess.run(
            ["tpm2", "getcap", "handles-persistent"],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            logger.info("Persistent handles:")
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    logger.info(f"  {line.strip()}")
        
        return True
        
    except Exception as e:
        logger.error(f"Error running TPM persistence scripts: {e}")
        return False


def monitor_swtpm(process: subprocess.Popen):
    """Monitor swtpm process output."""
    try:
        # Monitor stdout
        for line in iter(process.stdout.readline, ''):
            if line:
                logger.info(f"[swtpm] {line.strip()}")
        
        # Monitor stderr
        for line in iter(process.stderr.readline, ''):
            if line:
                logger.error(f"[swtpm] {line.strip()}")
                
    except Exception as e:
        logger.error(f"Error monitoring swtpm: {e}")


def wait_for_swtpm_ready(timeout: int = 30) -> bool:
    """
    Wait for swtpm to be ready.
    
    Args:
        timeout: Timeout in seconds
        
    Returns:
        True if ready, False otherwise
    """
    start_time = time.time()
    env = os.environ.copy()
    env['TPM2TOOLS_TCTI'] = settings.tpm2tools_tcti
    
    while time.time() - start_time < timeout:
        try:
            result = subprocess.run(
                ["tpm2", "getcap", "properties-fixed"],
                env=env,
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                logger.info("swtpm is ready")
                return True
                
        except Exception:
            pass
        
        time.sleep(1)
    
    logger.error(f"swtpm failed to be ready within {timeout} seconds")
    return False


def main():
    """Main startup function."""
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("Starting Software TPM (swtpm) for OpenTelemetry microservices...")
    
    # Check prerequisites
    if not check_swtpm_installed():
        logger.error("swtpm is not installed. Please install swtpm.")
        logger.error("On Ubuntu/Debian: sudo apt-get install swtpm")
        sys.exit(1)
    
    if not check_tpm2_tools_installed():
        logger.error("tpm2-tools is not installed. Please install tpm2-tools.")
        logger.error("On Ubuntu/Debian: sudo apt-get install tpm2-tools")
        sys.exit(1)
    
    try:
        # Start swtpm
        process = start_swtpm()
        
        # Start monitoring thread
        monitor_thread = threading.Thread(
            target=monitor_swtpm,
            args=(process,),
            daemon=True
        )
        monitor_thread.start()
        
        # Wait for swtpm to be ready
        if not wait_for_swtpm_ready():
            logger.error("swtpm failed to start properly")
            stop_swtpm()
            sys.exit(1)
        
        # Initialize TPM2
        if not initialize_tpm2():
            logger.error("Failed to initialize TPM2")
            stop_swtpm()
            sys.exit(1)
        
        # Run TPM2 persistence scripts
        if not run_tpm_persistence_scripts():
            logger.error("Failed to run TPM2 persistence scripts")
            stop_swtpm()
            sys.exit(1)
        
        logger.info("Software TPM (swtpm) is ready with persistent keys!")
        logger.info(f"TPM2TOOLS_TCTI: {settings.tpm2tools_tcti}")
        logger.info(f"swtpm directory: {os.path.expandvars(settings.swtpm_dir)}")
        logger.info(f"swtpm port: {settings.swtpm_port}")
        logger.info(f"EK handle: {settings.ek_handle}")
        logger.info(f"AK handle: {settings.ak_handle}")
        logger.info(f"AppSK handle: {settings.app_handle}")
        
        # Keep the main thread alive
        while True:
            time.sleep(1)
            
            # Check if process has died
            if process.poll() is not None:
                logger.error("swtpm process has stopped unexpectedly")
                sys.exit(1)
    
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
    except Exception as e:
        logger.error("Unexpected error", error=str(e))
    finally:
        stop_swtpm()


if __name__ == "__main__":
    main()
