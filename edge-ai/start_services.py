#!/usr/bin/env python3
"""
Startup script for the OpenTelemetry microservice architecture.

This script starts all three microservices:
1. OpenTelemetry Agent
2. OpenTelemetry Collector  
3. API Gateway

Each service runs on a different port with its own SSL certificates.
"""

import os
import sys
import time
import signal
import subprocess
import threading
from pathlib import Path
from typing import List, Dict, Any
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

# Service configurations
SERVICES = {
    "collector": {
        "name": "OpenTelemetry Collector",
        "script": "collector/app.py",
        "port": 8444,
        "env": {
            "SERVICE_NAME": "opentelemetry-collector",
            "PORT": "8444",
            "COLLECTOR_HOST": "localhost",
            "COLLECTOR_PORT": "8444",
            "OTEL_ENDPOINT": settings.otel_endpoint,
            "LOG_LEVEL": "INFO"
        }
    },
    "gateway": {
        "name": "API Gateway",
        "script": "gateway/app.py", 
        "port": 8443,
        "env": {
            "SERVICE_NAME": "opentelemetry-gateway",
            "PORT": "8443",
            "COLLECTOR_HOST": "localhost",
            "COLLECTOR_PORT": "8444",
            "OTEL_ENDPOINT": settings.otel_endpoint,
            "LOG_LEVEL": "INFO"
        }
    },
    "agent": {
        "name": "OpenTelemetry Agent",
        "script": "agent/app.py",
        "port": 8442,
        "env": {
            "SERVICE_NAME": "opentelemetry-agent",
            "PORT": "8442",
            "COLLECTOR_HOST": "localhost", 
            "COLLECTOR_PORT": "8443",
            "OTEL_ENDPOINT": settings.otel_endpoint,
            "LOG_LEVEL": "INFO"
        }
    }
}

# Global process list for cleanup
processes: List[subprocess.Popen] = []


def signal_handler(signum, frame):
    """Handle shutdown signals."""
    logger.info("Received shutdown signal, stopping all services...")
    stop_all_services()
    sys.exit(0)


def stop_all_services():
    """Stop all running services."""
    for process in processes:
        try:
            if process.poll() is None:  # Process is still running
                logger.info(f"Stopping process {process.pid}")
                process.terminate()
                process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            logger.warning(f"Force killing process {process.pid}")
            process.kill()
        except Exception as e:
            logger.error(f"Error stopping process {process.pid}", error=str(e))


def start_service(service_name: str, service_config: Dict[str, Any]) -> subprocess.Popen:
    """
    Start a single service.
    
    Args:
        service_name: Name of the service
        service_config: Service configuration
        
    Returns:
        Subprocess process object
    """
    try:
        # Set environment variables
        env = os.environ.copy()
        env.update(service_config["env"])
        
        # Add Python path
        if "PYTHONPATH" in env:
            env["PYTHONPATH"] = f"{os.getcwd()}:{env['PYTHONPATH']}"
        else:
            env["PYTHONPATH"] = os.getcwd()
        
        # Start the service
        cmd = [sys.executable, service_config["script"]]
        process = subprocess.Popen(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        
        logger.info(f"Started {service_config['name']}", 
                   pid=process.pid, 
                   port=service_config["port"])
        
        return process
        
    except Exception as e:
        logger.error(f"Failed to start {service_config['name']}", error=str(e))
        raise


def monitor_service(service_name: str, process: subprocess.Popen):
    """
    Monitor a service process and log its output.
    
    Args:
        service_name: Name of the service
        process: Subprocess process object
    """
    try:
        # Monitor stdout
        for line in iter(process.stdout.readline, ''):
            if line:
                logger.info(f"[{service_name}] {line.strip()}")
        
        # Monitor stderr
        for line in iter(process.stderr.readline, ''):
            if line:
                logger.error(f"[{service_name}] {line.strip()}")
                
    except Exception as e:
        logger.error(f"Error monitoring {service_name}", error=str(e))


def wait_for_service(service_name: str, port: int, timeout: int = 30) -> bool:
    """
    Wait for a service to be ready by checking its health endpoint.
    
    Args:
        service_name: Name of the service
        port: Service port
        timeout: Timeout in seconds
        
    Returns:
        True if service is ready, False otherwise
    """
    import requests
    import urllib3
    
    # Disable SSL warnings for self-signed certificates
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(
                f"https://localhost:{port}/health",
                verify=False,
                timeout=5
            )
            if response.status_code == 200:
                logger.info(f"{service_name} is ready", port=port)
                return True
        except requests.exceptions.RequestException:
            pass
        
        time.sleep(1)
    
    logger.error(f"{service_name} failed to start within {timeout} seconds", port=port)
    return False


def main():
    """Main startup function."""
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("Starting OpenTelemetry microservice architecture...")
    
    # Check if required files exist
    required_files = ["app.ctx", "primary.ctx", "ak.ctx", "ek.ctx"]
    missing_files = [f for f in required_files if not os.path.exists(f)]
    
    if missing_files:
        logger.error("Missing required TPM2 context files", missing_files=missing_files)
        logger.error("Please run the TPM2 persistence scripts first:")
        logger.error("python start_swtpm.py")
        logger.error("Or manually: ./swtpm.sh && ./tpm-ek-ak-persist.sh && ./tpm-app-persist.sh")
        sys.exit(1)
    
    # Check if swtpm is running
    logger.info("Checking software TPM (swtpm) status...")
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
        
        if result.returncode != 0:
            logger.warning("Software TPM not accessible. Please start swtpm first:")
            logger.warning("python start_swtpm.py")
            logger.warning("Or run: ./swtpm.sh")
            sys.exit(1)
        else:
            logger.info("Software TPM (swtpm) is accessible")
            
    except Exception as e:
        logger.error(f"Error checking swtpm status: {e}")
        sys.exit(1)
    
    # Start services in order (collector first, then gateway, then agent)
    startup_order = ["collector", "gateway", "agent"]
    
    try:
        for service_name in startup_order:
            if service_name not in SERVICES:
                logger.error(f"Unknown service: {service_name}")
                continue
            
            service_config = SERVICES[service_name]
            
            # Start the service
            process = start_service(service_name, service_config)
            processes.append(process)
            
            # Start monitoring thread
            monitor_thread = threading.Thread(
                target=monitor_service,
                args=(service_name, process),
                daemon=True
            )
            monitor_thread.start()
            
            # Wait for service to be ready (except for agent which depends on others)
            if service_name != "agent":
                if not wait_for_service(service_name, service_config["port"]):
                    logger.error(f"Service {service_name} failed to start")
                    stop_all_services()
                    sys.exit(1)
            
            # Small delay between service starts
            time.sleep(2)
        
        # Wait for agent to be ready
        if not wait_for_service("agent", SERVICES["agent"]["port"]):
            logger.warning("Agent service may not be fully ready")
        
        logger.info("All services started successfully!")
        logger.info("Service endpoints:")
        logger.info(f"  Collector: https://localhost:{SERVICES['collector']['port']}")
        logger.info(f"  Gateway:   https://localhost:{SERVICES['gateway']['port']}")
        logger.info(f"  Agent:     https://localhost:{SERVICES['agent']['port']}")
        
        # Keep the main thread alive
        while True:
            time.sleep(1)
            
            # Check if any process has died
            for i, process in enumerate(processes):
                if process.poll() is not None:
                    service_name = list(SERVICES.keys())[i]
                    logger.error(f"Service {service_name} has stopped unexpectedly")
                    stop_all_services()
                    sys.exit(1)
    
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
    except Exception as e:
        logger.error("Unexpected error", error=str(e))
    finally:
        stop_all_services()


if __name__ == "__main__":
    main()
