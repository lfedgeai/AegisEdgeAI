#!/usr/bin/env python3
"""
Test client for the OpenTelemetry microservice architecture.

This script demonstrates how to interact with the microservices:
1. Test health endpoints
2. Generate and send metrics through the agent
3. Verify the complete flow works end-to-end
"""

import os
import sys
import json
import time
import requests
from datetime import datetime
from typing import Dict, Any, Optional
import structlog

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

# Service endpoints
SERVICES = {
    "collector": "https://localhost:8444",
    "gateway": "https://localhost:8443", 
    "agent": "https://localhost:8442"
}


class TestClient:
    """Test client for the OpenTelemetry microservice architecture."""
    
    def __init__(self):
        """Initialize the test client."""
        self.session = requests.Session()
        
        # Disable SSL verification for self-signed certificates
        self.session.verify = False
        import urllib3
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
        # Set headers
        self.session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'OpenTelemetry-TestClient/1.0'
        })
    
    def test_health_endpoints(self) -> bool:
        """
        Test health endpoints for all services.
        
        Returns:
            True if all services are healthy, False otherwise
        """
        logger.info("Testing health endpoints...")
        
        all_healthy = True
        
        for service_name, base_url in SERVICES.items():
            try:
                response = self.session.get(f"{base_url}/health", timeout=10)
                
                if response.status_code == 200:
                    data = response.json()
                    logger.info(f"{service_name} is healthy", 
                               status=data.get("status"),
                               version=data.get("version"))
                else:
                    logger.error(f"{service_name} health check failed", 
                               status_code=response.status_code)
                    all_healthy = False
                    
            except Exception as e:
                logger.error(f"Failed to connect to {service_name}", error=str(e))
                all_healthy = False
        
        return all_healthy
    
    def test_nonce_generation(self) -> Optional[str]:
        """
        Test nonce generation through the gateway.
        
        Returns:
            Nonce string if successful, None otherwise
        """
        logger.info("Testing nonce generation...")
        
        try:
            # Get nonce through gateway
            response = self.session.get(f"{SERVICES['gateway']}/nonce", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                nonce = data.get("nonce")
                
                if nonce:
                    logger.info("Nonce generated successfully", 
                               nonce_length=len(nonce),
                               expires_in=data.get("expires_in"))
                    return nonce
                else:
                    logger.error("No nonce in response")
                    return None
            else:
                logger.error("Failed to get nonce", status_code=response.status_code)
                return None
                
        except Exception as e:
            logger.error("Error getting nonce", error=str(e))
            return None
    
    def test_metrics_generation(self, metric_type: str = "system") -> bool:
        """
        Test metrics generation and sending through the agent.
        
        Args:
            metric_type: Type of metrics to generate ("system" or "application")
            
        Returns:
            True if successful, False otherwise
        """
        logger.info(f"Testing metrics generation ({metric_type})...")
        
        try:
            # Prepare request payload
            payload = {
                "metric_type": metric_type,
                "custom_data": {
                    "test_run": True,
                    "timestamp": datetime.utcnow().isoformat(),
                    "client_id": "test-client"
                }
            }
            
            # Send request to agent
            response = self.session.post(
                f"{SERVICES['agent']}/metrics/generate",
                json=payload,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                logger.info("Metrics generated and sent successfully",
                           status=data.get("status"),
                           payload_id=data.get("payload_id"))
                return True
            else:
                logger.error("Failed to generate metrics", 
                           status_code=response.status_code,
                           response=response.text)
                return False
                
        except Exception as e:
            logger.error("Error generating metrics", error=str(e))
            return False
    
    def test_collector_status(self) -> bool:
        """
        Test collector status endpoint.
        
        Returns:
            True if successful, False otherwise
        """
        logger.info("Testing collector status...")
        
        try:
            response = self.session.get(f"{SERVICES['collector']}/metrics/status", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                logger.info("Collector status retrieved",
                           service=data.get("service"),
                           active_nonces=data.get("active_nonces"))
                return True
            else:
                logger.error("Failed to get collector status", status_code=response.status_code)
                return False
                
        except Exception as e:
            logger.error("Error getting collector status", error=str(e))
            return False
    
    def test_gateway_status(self) -> bool:
        """
        Test gateway status endpoint.
        
        Returns:
            True if successful, False otherwise
        """
        logger.info("Testing gateway status...")
        
        try:
            response = self.session.get(f"{SERVICES['gateway']}/gateway/status", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                logger.info("Gateway status retrieved",
                           service=data.get("service"),
                           active_clients=data.get("active_clients"))
                return True
            else:
                logger.error("Failed to get gateway status", status_code=response.status_code)
                return False
                
        except Exception as e:
            logger.error("Error getting gateway status", error=str(e))
            return False
    
    def test_rate_limits(self) -> bool:
        """
        Test gateway rate limiting.
        
        Returns:
            True if successful, False otherwise
        """
        logger.info("Testing gateway rate limits...")
        
        try:
            response = self.session.get(f"{SERVICES['gateway']}/gateway/rate-limits", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                logger.info("Rate limit info retrieved",
                           client_ip=data.get("client_ip"),
                           requests_in_window=data.get("requests_in_window"),
                           remaining_requests=data.get("remaining_requests"))
                return True
            else:
                logger.error("Failed to get rate limits", status_code=response.status_code)
                return False
                
        except Exception as e:
            logger.error("Error getting rate limits", error=str(e))
            return False
    
    def test_nonce_cleanup(self) -> bool:
        """
        Test nonce cleanup functionality.
        
        Returns:
            True if successful, False otherwise
        """
        logger.info("Testing nonce cleanup...")
        
        try:
            response = self.session.post(f"{SERVICES['gateway']}/nonces/cleanup", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                logger.info("Nonce cleanup completed",
                           cleaned_count=data.get("cleaned_count"),
                           remaining_count=data.get("remaining_count"))
                return True
            else:
                logger.error("Failed to cleanup nonces", status_code=response.status_code)
                return False
                
        except Exception as e:
            logger.error("Error cleaning up nonces", error=str(e))
            return False
    
    def run_comprehensive_test(self) -> bool:
        """
        Run a comprehensive test of the entire system.
        
        Returns:
            True if all tests pass, False otherwise
        """
        logger.info("Starting comprehensive system test...")
        
        tests = [
            ("Health Endpoints", self.test_health_endpoints),
            ("Nonce Generation", self.test_nonce_generation),
            ("System Metrics Generation", lambda: self.test_metrics_generation("system")),
            ("Application Metrics Generation", lambda: self.test_metrics_generation("application")),
            ("Collector Status", self.test_collector_status),
            ("Gateway Status", self.test_gateway_status),
            ("Rate Limits", self.test_rate_limits),
            ("Nonce Cleanup", self.test_nonce_cleanup)
        ]
        
        passed = 0
        total = len(tests)
        
        for test_name, test_func in tests:
            logger.info(f"Running test: {test_name}")
            try:
                if test_func():
                    logger.info(f"✓ {test_name} passed")
                    passed += 1
                else:
                    logger.error(f"✗ {test_name} failed")
            except Exception as e:
                logger.error(f"✗ {test_name} failed with exception", error=str(e))
            
            # Small delay between tests
            time.sleep(1)
        
        logger.info(f"Test results: {passed}/{total} tests passed")
        return passed == total


def main():
    """Main test function."""
    logger.info("OpenTelemetry Microservice Architecture Test Client")
    logger.info("=" * 60)
    
    # Check if services are running
    client = TestClient()
    
    # Test health endpoints first
    if not client.test_health_endpoints():
        logger.error("One or more services are not healthy. Please ensure all services are running.")
        sys.exit(1)
    
    # Run comprehensive test
    success = client.run_comprehensive_test()
    
    if success:
        logger.info("🎉 All tests passed! The system is working correctly.")
        sys.exit(0)
    else:
        logger.error("❌ Some tests failed. Please check the logs for details.")
        sys.exit(1)


if __name__ == "__main__":
    main()
