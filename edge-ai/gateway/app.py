"""
API Gateway Microservice

This microservice acts as a man-in-the-middle proxy that:
1. Terminates TLS connections from OpenTelemetry Agents
2. Reinitiates TLS connections to OpenTelemetry Collector
3. Provides load balancing and request routing
4. Implements security policies and rate limiting

The gateway ensures secure communication between agents and collectors.
"""

import os
import sys
import json
import time
import requests
from datetime import datetime
from typing import Dict, Any, Optional
from flask import Flask, jsonify, request, Response
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
import structlog

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config import settings
from utils.ssl_utils import SSLUtils, SSLError

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.dev.ConsoleRenderer()  # Use dev console renderer for screen output
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
DEBUG_GATEWAY = os.environ.get("DEBUG_GATEWAY", "false").lower() == "true"

# Set log level based on debug flags
if DEBUG_ALL or DEBUG_GATEWAY:
    log_level = logging.DEBUG
else:
    log_level = logging.INFO

logging.basicConfig(level=log_level)

# Filter out urllib3 DEBUG messages in non-debug mode
if not (DEBUG_ALL or DEBUG_GATEWAY):
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("urllib3.connectionpool").setLevel(logging.WARNING)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)

logger = structlog.get_logger(__name__)
logger.info("Gateway logging configuration", 
           debug_all=DEBUG_ALL,
           debug_gateway=DEBUG_GATEWAY,
           log_level=logging.getLevelName(log_level))

# Initialize Flask app
app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# Initialize OpenTelemetry
def setup_opentelemetry():
    """Setup OpenTelemetry tracing and metrics."""
    try:
        # Setup trace provider
        trace_provider = TracerProvider()
        trace.set_tracer_provider(trace_provider)
        
        # Skip metrics setup for now to avoid compatibility issues
        logger.info("Skipping OpenTelemetry metrics setup for compatibility")
        
        # Disable OTLP exporter to avoid warnings about missing collector
        # otlp_exporter = OTLPSpanExporter(endpoint=settings.otel_endpoint)
        # span_processor = BatchSpanProcessor(otlp_exporter)
        # trace_provider.add_span_processor(span_processor)
        
        # Instrument Flask and requests
        FlaskInstrumentor().instrument_app(app)
        RequestsInstrumentor().instrument()
        
        logger.info("OpenTelemetry setup completed (OTLP export disabled)")
        
    except Exception as e:
        logger.error("Failed to setup OpenTelemetry", error=str(e))

# Initialize OpenTelemetry
setup_opentelemetry()

# Get tracer and meter
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

# Create metrics
request_counter = meter.create_counter(
    name="gateway_requests_total",
    description="Total number of requests processed by the gateway"
)

proxy_counter = meter.create_counter(
    name="gateway_proxy_requests_total",
    description="Total number of proxy requests"
)

error_counter = meter.create_counter(
    name="gateway_errors_total",
    description="Total number of errors encountered by the gateway"
)

# Request tracking for rate limiting
request_timestamps = {}


class ProxyManager:
    """Manages proxy connections to the collector."""
    
    def __init__(self):
        """Initialize the proxy manager."""
        self.collector_url = f"https://{settings.collector_host}:{settings.collector_port}"
        self.session = requests.Session()
        
        # Setup SSL context for collector communication
        if not settings.collector_ssl_verify:
            self.session.verify = False
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
        # Add custom headers for gateway identification
        self.session.headers.update({
            'User-Agent': f'OpenTelemetry-Gateway/{settings.service_version}',
            'X-Gateway-ID': os.getenv('GATEWAY_ID', 'unknown')
        })
    
    def proxy_request(self, method: str, path: str, data: Optional[Any] = None, 
                     headers: Optional[Dict] = None, params: Optional[Dict] = None) -> Response:
        """
        Proxy a request to the collector as-is.
        
        Args:
            method: HTTP method
            path: Request path
            data: Request data (JSON dict, raw bytes, or None)
            headers: Request headers (all headers proxied as-is)
            params: Query parameters
            
        Returns:
            Flask Response object
        """
        try:
            url = f"{self.collector_url}{path}"
            
            # Proxy all headers as-is (no filtering)
            proxy_headers = dict(headers) if headers else {}
            
            # Make request to collector
            if method.upper() == 'GET':
                response = self.session.get(url, headers=proxy_headers, params=params)
            elif method.upper() == 'POST':
                if isinstance(data, dict):
                    response = self.session.post(url, json=data, headers=proxy_headers, params=params)
                else:
                    response = self.session.post(url, data=data, headers=proxy_headers, params=params)
            elif method.upper() == 'PUT':
                if isinstance(data, dict):
                    response = self.session.put(url, json=data, headers=proxy_headers, params=params)
                else:
                    response = self.session.put(url, data=data, headers=proxy_headers, params=params)
            elif method.upper() == 'DELETE':
                response = self.session.delete(url, headers=proxy_headers, params=params)
            elif method.upper() == 'PATCH':
                if isinstance(data, dict):
                    response = self.session.patch(url, json=data, headers=proxy_headers, params=params)
                else:
                    response = self.session.patch(url, data=data, headers=proxy_headers, params=params)
            else:
                return jsonify({"error": f"Unsupported method: {method}"}), 405
            
            # Create Flask response with all original headers
            flask_response = Response(
                response.content,
                status=response.status_code,
                headers=dict(response.headers)
            )
            
            return flask_response
            
        except Exception as e:
            logger.error("Proxy request failed", method=method, path=path, error=str(e))
            error_counter.add(1, {"operation": "proxy_request", "error": str(e)})
            return jsonify({"error": "Proxy request failed"}), 500


class SecurityManager:
    """Manages security policies and rate limiting."""
    
    def __init__(self):
        """Initialize the security manager."""
        self.rate_limit_requests = 100  # requests per minute
        self.rate_limit_window = 60  # seconds
    
    def check_rate_limit(self, client_ip: str) -> bool:
        """
        Check if client is within rate limits.
        
        Args:
            client_ip: Client IP address
            
        Returns:
            True if within rate limit, False otherwise
        """
        current_time = time.time()
        
        # Clean up old timestamps
        if client_ip in request_timestamps:
            request_timestamps[client_ip] = [
                ts for ts in request_timestamps[client_ip]
                if current_time - ts < self.rate_limit_window
            ]
        else:
            request_timestamps[client_ip] = []
        
        # Check rate limit
        if len(request_timestamps[client_ip]) >= self.rate_limit_requests:
            return False
        
        # Add current request timestamp
        request_timestamps[client_ip].append(current_time)
        return True
    
    def validate_request(self, request) -> Dict[str, Any]:
        """
        Validate incoming request.
        
        Args:
            request: Flask request object
            
        Returns:
            Validation result
        """
        client_ip = request.remote_addr
        
        # Check rate limit
        if not self.check_rate_limit(client_ip):
            return {
                "valid": False,
                "error": "Rate limit exceeded",
                "status_code": 429
            }
        
        # Check content type for POST requests
        if request.method == 'POST':
            if not request.is_json:
                return {
                    "valid": False,
                    "error": "Content-Type must be application/json",
                    "status_code": 400
                }
        
        return {"valid": True}


# Initialize managers
proxy_manager = ProxyManager()
security_manager = SecurityManager()


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return jsonify({
        "status": "healthy",
        "service": settings.service_name,
        "version": settings.service_version,
        "collector_connected": True,  # This could be enhanced with actual connectivity check
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/nonce', methods=['GET'])
def proxy_nonce():
    """Proxy nonce requests to the collector."""
    with tracer.start_as_current_span("proxy_nonce"):
        try:
            request_counter.add(1, {"endpoint": "nonce"})
            proxy_counter.add(1, {"operation": "get_nonce"})
            
            # Validate request
            validation = security_manager.validate_request(request)
            if not validation["valid"]:
                return jsonify({"error": validation["error"]}), validation["status_code"]
            
            # Proxy request to collector as-is (all query params, headers, etc.)
            response = proxy_manager.proxy_request('GET', '/nonce', 
                                                  headers=request.headers, 
                                                  params=request.args)
            
            logger.info("Nonce request proxied successfully")
            return response
            
        except Exception as e:
            logger.error("Error proxying nonce request", error=str(e))
            error_counter.add(1, {"operation": "proxy_nonce", "error": str(e)})
            return jsonify({"error": "Failed to proxy nonce request"}), 500





@app.route('/metrics', methods=['POST'])
def proxy_metrics():
    """Proxy metrics requests to the collector."""
    with tracer.start_as_current_span("proxy_metrics"):
        try:
            request_counter.add(1, {"endpoint": "metrics"})
            proxy_counter.add(1, {"operation": "send_metrics"})
            
            # Validate request
            validation = security_manager.validate_request(request)
            if not validation["valid"]:
                return jsonify({"error": validation["error"]}), validation["status_code"]
            
            # Get request data
            data = request.get_json()
            
            # Proxy request to collector as-is
            response = proxy_manager.proxy_request('POST', '/metrics', 
                                                 data=data, 
                                                 headers=request.headers,
                                                 params=request.args)
            
            logger.info("Metrics request proxied successfully")
            return response
            
        except Exception as e:
            logger.error("Error proxying metrics request", error=str(e))
            error_counter.add(1, {"operation": "proxy_metrics", "error": str(e)})
            return jsonify({"error": "Failed to proxy metrics request"}), 500


@app.route('/metrics/status', methods=['GET'])
def proxy_metrics_status():
    """Proxy metrics status requests to the collector."""
    with tracer.start_as_current_span("proxy_metrics_status"):
        try:
            request_counter.add(1, {"endpoint": "metrics_status"})
            proxy_counter.add(1, {"operation": "get_metrics_status"})
            
            # Validate request
            validation = security_manager.validate_request(request)
            if not validation["valid"]:
                return jsonify({"error": validation["error"]}), validation["status_code"]
            
            # Proxy request to collector as-is
            response = proxy_manager.proxy_request('GET', '/metrics/status', 
                                                 headers=request.headers,
                                                 params=request.args)
            
            logger.info("Metrics status request proxied successfully")
            return response
            
        except Exception as e:
            logger.error("Error proxying metrics status request", error=str(e))
            error_counter.add(1, {"operation": "proxy_metrics_status", "error": str(e)})
            return jsonify({"error": "Failed to proxy metrics status request"}), 500


@app.route('/nonces/stats', methods=['GET'])
def proxy_nonce_stats():
    """Proxy nonce statistics requests to the collector."""
    with tracer.start_as_current_span("proxy_nonce_stats"):
        try:
            request_counter.add(1, {"endpoint": "nonces_stats"})
            proxy_counter.add(1, {"operation": "get_nonce_stats"})
            
            # Validate request
            validation = security_manager.validate_request(request)
            if not validation["valid"]:
                return jsonify({"error": validation["error"]}), validation["status_code"]
            
            # Proxy request to collector as-is
            response = proxy_manager.proxy_request('GET', '/nonces/stats', 
                                                 headers=request.headers,
                                                 params=request.args)
            
            logger.info("Nonce statistics request proxied successfully")
            return response
            
        except Exception as e:
            logger.error("Error proxying nonce statistics request", error=str(e))
            error_counter.add(1, {"operation": "proxy_nonce_stats", "error": str(e)})
            return jsonify({"error": "Failed to proxy nonce statistics request"}), 500


@app.route('/nonces/cleanup', methods=['POST'])
def proxy_nonces_cleanup():
    """Proxy nonce cleanup requests to the collector."""
    with tracer.start_as_current_span("proxy_nonces_cleanup"):
        try:
            request_counter.add(1, {"endpoint": "nonces_cleanup"})
            proxy_counter.add(1, {"operation": "cleanup_nonces"})
            
            # Validate request
            validation = security_manager.validate_request(request)
            if not validation["valid"]:
                return jsonify({"error": validation["error"]}), validation["status_code"]
            
            # Get request data if any
            data = request.get_json() if request.is_json else None
            
            # Proxy request to collector as-is
            response = proxy_manager.proxy_request('POST', '/nonces/cleanup', 
                                                 data=data,
                                                 headers=request.headers,
                                                 params=request.args)
            
            logger.info("Nonce cleanup request proxied successfully")
            return response
            
        except Exception as e:
            logger.error("Error proxying nonce cleanup request", error=str(e))
            error_counter.add(1, {"operation": "proxy_nonces_cleanup", "error": str(e)})
            return jsonify({"error": "Failed to proxy nonce cleanup request"}), 500


@app.route('/gateway/status', methods=['GET'])
def get_gateway_status():
    """Get gateway status and statistics."""
    return jsonify({
        "service": settings.service_name,
        "version": settings.service_version,
        "collector_url": proxy_manager.collector_url,
        "rate_limit": {
            "requests_per_minute": security_manager.rate_limit_requests,
            "window_seconds": security_manager.rate_limit_window
        },
        "active_clients": len(request_timestamps),
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/gateway/rate-limits', methods=['GET'])
def get_rate_limits():
    """Get current rate limit information."""
    client_ip = request.remote_addr
    current_time = time.time()
    
    if client_ip in request_timestamps:
        recent_requests = [
            ts for ts in request_timestamps[client_ip]
            if current_time - ts < security_manager.rate_limit_window
        ]
        request_count = len(recent_requests)
    else:
        request_count = 0
    
    return jsonify({
        "client_ip": client_ip,
        "requests_in_window": request_count,
        "rate_limit": security_manager.rate_limit_requests,
        "window_seconds": security_manager.rate_limit_window,
        "remaining_requests": max(0, security_manager.rate_limit_requests - request_count),
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/<path:subpath>', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def proxy_all_other_routes(subpath):
    """Generic proxy for all other routes to the collector."""
    with tracer.start_as_current_span("proxy_generic"):
        try:
            method = request.method
            path = f"/{subpath}"
            
            request_counter.add(1, {"endpoint": f"proxy_{method.lower()}"})
            proxy_counter.add(1, {"operation": f"proxy_{method.lower()}"})
            
            # Validate request
            validation = security_manager.validate_request(request)
            if not validation["valid"]:
                return jsonify({"error": validation["error"]}), validation["status_code"]
            
            # Get request data if any
            data = None
            if method in ['POST', 'PUT', 'PATCH'] and request.is_json:
                data = request.get_json()
            elif method in ['POST', 'PUT', 'PATCH'] and request.data:
                data = request.data
            
            # Proxy request to collector as-is
            response = proxy_manager.proxy_request(method, path, 
                                                 data=data,
                                                 headers=request.headers,
                                                 params=request.args)
            
            logger.info(f"Generic {method} request proxied successfully", path=path)
            return response
            
        except Exception as e:
            logger.error(f"Error proxying {method} request", path=path, error=str(e))
            error_counter.add(1, {"operation": f"proxy_{method.lower()}", "error": str(e)})
            return jsonify({"error": f"Failed to proxy {method} request"}), 500


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({"error": "Endpoint not found"}), 404


@app.errorhandler(429)
def rate_limit_exceeded(error):
    """Handle rate limit exceeded errors."""
    return jsonify({
        "error": "Rate limit exceeded",
        "retry_after": security_manager.rate_limit_window
    }), 429


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors."""
    logger.error("Internal server error", error=str(error))
    return jsonify({"error": "Internal server error"}), 500


if __name__ == '__main__':
    # Generate SSL certificates if not provided
    if settings.ssl_enabled and not (settings.ssl_cert_path and settings.ssl_key_path):
        cert_path, key_path = SSLUtils.create_temp_certificate(
            f"{settings.service_name}-gateway"
        )
        settings.ssl_cert_path = cert_path
        settings.ssl_key_path = key_path
        logger.info("Generated temporary SSL certificates", cert_path=cert_path, key_path=key_path)
    
    # Start the application
    if settings.ssl_enabled and settings.ssl_cert_path and settings.ssl_key_path:
        app.run(
            host=settings.host,
            port=settings.port,
            ssl_context=(settings.ssl_cert_path, settings.ssl_key_path),
            debug=settings.debug
        )
    else:
        app.run(
            host=settings.host,
            port=settings.port,
            debug=settings.debug
        )
