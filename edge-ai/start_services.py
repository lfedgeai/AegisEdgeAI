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
        structlog.dev.ConsoleRenderer()  # Use console renderer for better readability
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

# Set up basic logging based on environment variables
import logging

# Check for debug logging environment variables
DEBUG_ALL = os.environ.get("DEBUG_ALL", "false").lower() == "true"
DEBUG_COLLECTOR = os.environ.get("DEBUG_COLLECTOR", "false").lower() == "true"
DEBUG_GATEWAY = os.environ.get("DEBUG_GATEWAY", "false").lower() == "true"
DEBUG_AGENT = os.environ.get("DEBUG_AGENT", "false").lower() == "true"

# Check for quiet mode
QUIET_MODE = os.environ.get("QUIET_MODE", "false").lower() == "true"

# Set log level based on debug flags
if DEBUG_ALL or DEBUG_COLLECTOR or DEBUG_GATEWAY or DEBUG_AGENT:
    log_level = logging.DEBUG
else:
    log_level = logging.INFO

logging.basicConfig(level=log_level)

# Log debug configuration
logger = structlog.get_logger(__name__)
logger.info("Logging configuration", 
           debug_all=DEBUG_ALL,
           debug_collector=DEBUG_COLLECTOR,
           debug_gateway=DEBUG_GATEWAY,
           debug_agent=DEBUG_AGENT,
           quiet_mode=QUIET_MODE,
           log_level=logging.getLevelName(log_level))

# Service configurations
SERVICES = {
    "collector": {
        "name": "OpenTelemetry Collector",
        "script": "collector/app.py",
        "port": settings.collector_port,
        "env": {
            "SERVICE_NAME": "opentelemetry-collector",
            "PORT": str(settings.collector_port),
            "COLLECTOR_HOST": "localhost",
            "COLLECTOR_PORT": str(settings.collector_port),
            "OTEL_ENDPOINT": settings.otel_endpoint,
            "LOG_LEVEL": "DEBUG" if DEBUG_ALL or DEBUG_COLLECTOR else "INFO"
        }
    },
    "gateway": {
        "name": "API Gateway",
        "script": "gateway/app.py", 
        "port": settings.gateway_port,
        "env": {
            "SERVICE_NAME": "opentelemetry-gateway",
            "PORT": str(settings.gateway_port),
            "COLLECTOR_HOST": "localhost",
            "COLLECTOR_PORT": str(settings.collector_port),
            "OTEL_ENDPOINT": settings.otel_endpoint,
            "LOG_LEVEL": "DEBUG" if DEBUG_ALL or DEBUG_GATEWAY else "INFO"
        }
    },
    "agent": {
        "name": "OpenTelemetry Agent",
        "script": "agent/app.py",
        "port": settings.agent_base_port,
        "env": {
            "SERVICE_NAME": "opentelemetry-agent",
            "PORT": str(settings.agent_base_port),
            "GATEWAY_HOST": "localhost", 
            "GATEWAY_PORT": str(settings.gateway_port),
            "COLLECTOR_HOST": "localhost",
            "COLLECTOR_PORT": str(settings.gateway_port),  # Agent should connect to gateway, not collector
            "OTEL_ENDPOINT": settings.otel_endpoint,
            "LOG_LEVEL": "DEBUG" if DEBUG_ALL or DEBUG_AGENT else "INFO",
            "AGENT_NAME": "agent-001"  # Set default agent name
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
        # Skip monitoring if quiet mode is enabled
        if QUIET_MODE:
            logger.info(f"Quiet mode enabled - skipping output monitoring for {service_name}")
            return
            
        # Monitor stdout and stderr in a non-blocking way
        import threading
        
        def monitor_output(stream, log_func, stream_type):
            try:
                for line in iter(stream.readline, ''):
                    if line and line.strip():
                        # Filter out some noisy messages
                        line_stripped = line.strip()
                        if any(skip in line_stripped for skip in [
                            "Resetting dropped connection",
                            "Starting new HTTPS connection",
                            "WARNING: This is a development server",
                            "Press CTRL+C to quit",
                            "Running on all addresses",
                            "Running on https://",
                            "Serving Flask app",
                            "Debug mode:",
                            "INFO:werkzeug:"
                        ]):
                            continue
                        log_func(f"[{service_name}] {stream_type}: {line_stripped}")
            except Exception as e:
                logger.error(f"Error monitoring {service_name} {stream_type}", error=str(e))
        
        # Start monitoring threads
        stdout_thread = threading.Thread(
            target=monitor_output, 
            args=(process.stdout, logger.info, "STDOUT"),
            daemon=True
        )
        stderr_thread = threading.Thread(
            target=monitor_output, 
            args=(process.stderr, logger.info, "STDERR"),  # Use info instead of warning for stderr
            daemon=True
        )
        
        stdout_thread.start()
        stderr_thread.start()
                
    except Exception as e:
        logger.error(f"Error setting up monitoring for {service_name}", error=str(e))


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
    required_files = ["tpm/app.ctx", "tpm/primary.ctx", "tpm/ak.ctx", "tpm/ek.ctx"]
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
    
    # Check if agent-001 exists, create if not
    logger.info("Checking if agent-001 exists...")
    agent_config_path = "agents/agent-001/config.json"
    if not os.path.exists(agent_config_path):
        logger.info("Agent-001 not found, creating it...")
        try:
            # Import AgentCreator class
            from create_agent import AgentCreator
            
            # Create agent-001 with default location
            creator = AgentCreator("agent-001", "US/California/Santa Clara")
            success = creator.create_agent()
            
            if success:
                logger.info("Agent-001 created successfully")
                # Small delay to ensure files are written
                time.sleep(1)
            else:
                raise Exception("Agent creation returned False")
                
        except Exception as e:
            logger.error(f"Failed to create agent-001: {e}")
            logger.error("Please create agent-001 manually: python create_agent.py agent-001")
            sys.exit(1)
    else:
        logger.info("Agent-001 already exists")
    
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
            
            # Start monitoring (non-blocking)
            monitor_service(service_name, process)
            
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
        
        logger.info("🎉 All services started successfully!")
        logger.info("📡 Service endpoints:")
        logger.info(f"  🔍 Collector: https://localhost:{SERVICES['collector']['port']}")
        logger.info(f"  🌐 Gateway:   https://localhost:{SERVICES['gateway']['port']}")
        logger.info(f"  🤖 Agent:     https://localhost:{SERVICES['agent']['port']}")
        logger.info("")
        logger.info("✅ System is ready for testing!")
        logger.info("   Run: ./test_end_to_end_flow.sh")
        
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
