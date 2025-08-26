"""
API Gateway Microservice

This microservice acts as a man-in-the-middle proxy that:
1. Terminates TLS connections from OpenTelemetry Agents
2. Reinitiates TLS connections to OpenTelemetry Collector
3. Provides load balancing and request routing
4. Implements security policies and rate limiting
5. Validates agents against allowlist with configurable options

The gateway ensures secure communication between agents and collectors.
"""

import os
import sys
import json
import time
import hashlib
import base64
import requests
from datetime import datetime
from typing import Dict, Any, Optional, List
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

# Simple file logger for header capture (greppable by tests)
HEADER_LOG_PATH = os.environ.get("GATEWAY_HEADER_LOG", os.path.join(os.getcwd(), "logs", "gateway_headers.log"))
try:
    os.makedirs(os.path.dirname(HEADER_LOG_PATH), exist_ok=True)
except Exception:
    pass

def log_headers_to_file(endpoint: str, geo_id: Optional[str], sig: Optional[str], sig_input: Optional[str]):
    try:
        record = {
            "ts": datetime.utcnow().isoformat(),
            "endpoint": endpoint,
            "Workload-Geo-ID": geo_id,
            "Signature": sig,
            "Signature-Input": sig_input,
        }
        with open(HEADER_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")
    except Exception as e:
        logger.warning("Failed to write header log", error=str(e))


class GatewayAllowlistManager:
    """Manages gateway agent allowlist and validation."""
    
    def __init__(self, allowlist_path: str = "gateway/allowed_agents.json"):
        """
        Initialize the gateway allowlist manager.
        
        Args:
            allowlist_path: Path to the allowlist JSON file
        """
        self.allowlist_path = allowlist_path
        self.allowed_agents = []
        self.load_allowlist()
        
        # Configurable validation options (can be set via environment variables)
        self.validate_public_key_hash = os.environ.get("GATEWAY_VALIDATE_PUBLIC_KEY_HASH", "true").lower() == "true"
        self.validate_signature = os.environ.get("GATEWAY_VALIDATE_SIGNATURE", "true").lower() == "true"
        self.validate_geolocation = os.environ.get("GATEWAY_VALIDATE_GEOLOCATION", "true").lower() == "true"
        
        logger.info("Gateway allowlist manager initialized",
                   allowlist_path=allowlist_path,
                   validate_public_key_hash=self.validate_public_key_hash,
                   validate_signature=self.validate_signature,
                   validate_geolocation=self.validate_geolocation,
                   agent_count=len(self.allowed_agents))
    
    def load_allowlist(self):
        """Load the allowlist from JSON file."""
        try:
            if os.path.exists(self.allowlist_path):
                with open(self.allowlist_path, 'r') as f:
                    self.allowed_agents = json.load(f)
                logger.info("Gateway allowlist loaded", 
                           path=self.allowlist_path,
                           agent_count=len(self.allowed_agents))
            else:
                self.allowed_agents = []
                logger.info("Gateway allowlist file not found, starting with empty allowlist",
                           path=self.allowlist_path)
        except Exception as e:
            logger.error("Failed to load gateway allowlist", 
                        path=self.allowlist_path,
                        error=str(e))
            self.allowed_agents = []
    
    def reload_allowlist(self):
        """Reload the allowlist from file."""
        self.load_allowlist()
    
    def get_agent_by_public_key_hash(self, public_key_hash: str) -> Optional[Dict[str, Any]]:
        """
        Get agent information by public key hash.
        
        Args:
            public_key_hash: SHA-256 hash of the agent's public key
            
        Returns:
            Agent information dict or None if not found
        """
        for agent in self.allowed_agents:
            if agent.get('tpm_public_key_hash') == public_key_hash:
                return agent
        return None
    
    def get_agent_by_name(self, agent_name: str) -> Optional[Dict[str, Any]]:
        """
        Get agent information by agent name.
        
        Args:
            agent_name: Name of the agent
            
        Returns:
            Agent information dict or None if not found
        """
        for agent in self.allowed_agents:
            if agent.get('agent_name') == agent_name:
                return agent
        return None
    
    def validate_public_key_hash_in_allowlist(self, public_key_hash: str) -> Dict[str, Any]:
        """
        Validate that the public key hash is in the allowlist.
        
        Args:
            public_key_hash: SHA-256 hash of the agent's public key
            
        Returns:
            Validation result
        """
        if not self.validate_public_key_hash:
            return {"valid": True, "reason": "Public key hash validation disabled"}
        
        agent = self.get_agent_by_public_key_hash(public_key_hash)
        if agent:
            return {
                "valid": True,
                "agent": agent,
                "reason": "Public key hash found in allowlist"
            }
        else:
            return {
                "valid": False,
                "reason": f"Public key hash {public_key_hash} not found in allowlist"
            }
    
    def validate_signature_against_agent(self, signature: str, public_key_hash: str, 
                                       signature_input: str) -> Dict[str, Any]:
        """
        Validate signature against agent's public key.
        
        Args:
            signature: The signature to validate
            public_key_hash: SHA-256 hash of the agent's public key
            signature_input: The signature input string
            
        Returns:
            Validation result
        """
        if not self.validate_signature:
            return {"valid": True, "reason": "Signature validation disabled"}
        
        agent = self.get_agent_by_public_key_hash(public_key_hash)
        if not agent:
            return {
                "valid": False,
                "reason": "Agent not found in allowlist for signature validation"
            }
        
        try:
            # Extract public key from agent data
            public_key_content = agent.get('tpm_public_key', '')
            if not public_key_content:
                return {
                    "valid": False,
                    "reason": "No public key found for agent"
                }
            
            # TODO: Implement actual signature verification
            # For now, we'll do a basic validation that the signature exists and has expected format
            if not signature or len(signature) < 64:  # Minimum reasonable signature length
                return {
                    "valid": False,
                    "reason": "Invalid signature format"
                }
            
            # TODO: Add actual cryptographic signature verification here
            # This would involve:
            # 1. Parsing the signature input to extract the signed data
            # 2. Using the public key to verify the signature
            # 3. Checking the signature expiration
            
            logger.info("Signature validation passed (basic format check)",
                       agent_name=agent.get('agent_name'),
                       public_key_hash=public_key_hash)
            
            return {
                "valid": True,
                "agent": agent,
                "reason": "Signature format validation passed"
            }
            
        except Exception as e:
            logger.error("Signature validation failed",
                        agent_name=agent.get('agent_name'),
                        public_key_hash=public_key_hash,
                        error=str(e))
            return {
                "valid": False,
                "reason": f"Signature validation error: {str(e)}"
            }
    
    def validate_geolocation_against_agent(self, workload_geo_id: Dict[str, Any], 
                                         public_key_hash: str) -> Dict[str, Any]:
        """
        Validate geolocation against agent's policy.
        
        Args:
            workload_geo_id: The Workload-Geo-ID header content
            public_key_hash: SHA-256 hash of the agent's public key
            
        Returns:
            Validation result
        """
        if not self.validate_geolocation:
            return {"valid": True, "reason": "Geolocation validation disabled"}
        
        agent = self.get_agent_by_public_key_hash(public_key_hash)
        if not agent:
            return {
                "valid": False,
                "reason": "Agent not found in allowlist for geolocation validation"
            }
        
        try:
            # Extract expected geolocation from agent
            expected_geo = agent.get('geolocation', {})
            if not expected_geo:
                return {
                    "valid": True,
                    "reason": "No geolocation policy defined for agent"
                }
            
            # Extract actual geolocation from request
            actual_location = workload_geo_id.get('client_workload_location', {})
            if not actual_location:
                return {
                    "valid": False,
                    "reason": "No geolocation information in request"
                }
            
            # Compare geolocation (case-insensitive)
            # Note: allowlist uses 'country' but Workload-Geo-ID uses 'region'
            expected_country = expected_geo.get('country', '').upper()
            expected_state = expected_geo.get('state', '').upper()
            expected_city = expected_geo.get('city', '').upper()
            
            actual_country = actual_location.get('region', '').upper()
            actual_state = actual_location.get('state', '').upper()
            actual_city = actual_location.get('city', '').upper()
            
            # Check if geolocation matches
            if (expected_country and actual_country and expected_country != actual_country):
                return {
                    "valid": False,
                    "reason": f"Geolocation verification failed - expected country: {expected_country}, received: {actual_country}"
                }
            
            if (expected_state and actual_state and expected_state != actual_state):
                return {
                    "valid": False,
                    "reason": f"Geolocation verification failed - expected state: {expected_state}, received: {actual_state}"
                }
            
            if (expected_city and actual_city and expected_city != actual_city):
                return {
                    "valid": False,
                    "reason": f"Geolocation verification failed - expected city: {expected_city}, received: {actual_city}"
                }
            
            logger.info("Geolocation validation passed",
                       agent_name=agent.get('agent_name'),
                       expected_geo=expected_geo,
                       actual_geo=actual_location)
            
            return {
                "valid": True,
                "agent": agent,
                "reason": "Geolocation validation passed"
            }
            
        except Exception as e:
            logger.error("Geolocation validation failed",
                        agent_name=agent.get('agent_name'),
                        public_key_hash=public_key_hash,
                        error=str(e))
            return {
                "valid": False,
                "reason": f"Geolocation validation error: {str(e)}"
            }
    
    def extract_public_key_hash_from_signature_input(self, signature_input: str) -> Optional[str]:
        """
        Extract public key hash from signature input header.
        
        Args:
            signature_input: The Signature-Input header value
            
        Returns:
            Public key hash or None if not found
        """
        try:
            # Parse signature input format: keyid="hash", created=timestamp, expires=timestamp, alg="algorithm", nonce="nonce"
            if not signature_input:
                return None
            
            # Extract keyid value
            if 'keyid=' in signature_input:
                keyid_start = signature_input.find('keyid="') + 7
                keyid_end = signature_input.find('"', keyid_start)
                if keyid_start > 6 and keyid_end > keyid_start:
                    return signature_input[keyid_start:keyid_end]
            
            return None
            
        except Exception as e:
            logger.error("Failed to extract public key hash from signature input",
                        signature_input=signature_input,
                        error=str(e))
            return None
    
    def validate_request_headers(self, headers: Dict[str, str]) -> Dict[str, Any]:
        """
        Validate request headers against allowlist and policies.
        
        Args:
            headers: Request headers
            
        Returns:
            Validation result
        """
        try:
            # Extract headers
            signature_input = headers.get('Signature-Input', '')
            signature = headers.get('Signature', '')
            workload_geo_id_str = headers.get('Workload-Geo-ID', '')
            
            # Extract public key hash from signature input
            public_key_hash = self.extract_public_key_hash_from_signature_input(signature_input)
            if not public_key_hash:
                return {
                    "valid": False,
                    "reason": "Could not extract public key hash from Signature-Input header"
                }
            
            # Validate public key hash is in allowlist
            pk_validation = self.validate_public_key_hash_in_allowlist(public_key_hash)
            if not pk_validation["valid"]:
                return pk_validation
            
            # Validate signature if present
            if signature:
                sig_validation = self.validate_signature_against_agent(signature, public_key_hash, signature_input)
                if not sig_validation["valid"]:
                    return sig_validation
            
            # Validate geolocation if present
            if workload_geo_id_str:
                try:
                    workload_geo_id = json.loads(workload_geo_id_str)
                    geo_validation = self.validate_geolocation_against_agent(workload_geo_id, public_key_hash)
                    if not geo_validation["valid"]:
                        return geo_validation
                except json.JSONDecodeError:
                    return {
                        "valid": False,
                        "reason": "Invalid JSON format in Workload-Geo-ID header"
                    }
            
            return {
                "valid": True,
                "agent": pk_validation.get("agent"),
                "reason": "All validations passed"
            }
            
        except Exception as e:
            logger.error("Header validation failed", error=str(e))
            return {
                "valid": False,
                "reason": f"Header validation error: {str(e)}"
            }

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

# Debug storage for last seen headers
last_headers = {
    "nonce": {
        "Workload-Geo-ID": None,
        "Signature": None,
        "Signature-Input": None,
        "timestamp": None,
    },
    "metrics": {
        "Workload-Geo-ID": None,
        "Signature": None,
        "Signature-Input": None,
        "timestamp": None,
    },
}


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
        
        # Validate against gateway allowlist if enabled
        if gateway_allowlist_manager.validate_public_key_hash or gateway_allowlist_manager.validate_signature or gateway_allowlist_manager.validate_geolocation:
            header_validation = gateway_allowlist_manager.validate_request_headers(dict(request.headers))
            if not header_validation["valid"]:
                return {
                    "valid": False,
                    "error": header_validation["reason"],
                    "status_code": 403
                }
        
        return {"valid": True}


# Initialize managers
proxy_manager = ProxyManager()
security_manager = SecurityManager()
gateway_allowlist_manager = GatewayAllowlistManager()


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return jsonify({
        "status": "healthy",
        "service": settings.service_name,
        "version": settings.service_version,
        "collector_connected": True,  # This could be enhanced with actual connectivity check
        "gateway_allowlist": {
            "enabled": gateway_allowlist_manager.validate_public_key_hash or gateway_allowlist_manager.validate_signature or gateway_allowlist_manager.validate_geolocation,
            "validation_options": {
                "public_key_hash": gateway_allowlist_manager.validate_public_key_hash,
                "signature": gateway_allowlist_manager.validate_signature,
                "geolocation": gateway_allowlist_manager.validate_geolocation
            },
            "agent_count": len(gateway_allowlist_manager.allowed_agents)
        },
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/reload-allowlist', methods=['POST'])
def reload_allowlist():
    """Reload the gateway allowlist from file."""
    try:
        gateway_allowlist_manager.reload_allowlist()
        return jsonify({
            "status": "success",
            "message": "Gateway allowlist reloaded successfully",
            "agent_count": len(gateway_allowlist_manager.allowed_agents),
            "timestamp": datetime.utcnow().isoformat()
        })
    except Exception as e:
        logger.error("Failed to reload allowlist", error=str(e))
        return jsonify({
            "status": "error",
            "message": f"Failed to reload allowlist: {str(e)}",
            "timestamp": datetime.utcnow().isoformat()
        }), 500


@app.route('/nonce', methods=['GET'])
def proxy_nonce():
    """Proxy nonce requests to the collector."""
    with tracer.start_as_current_span("proxy_nonce"):
        try:
            request_counter.add(1, {"endpoint": "nonce"})
            proxy_counter.add(1, {"operation": "get_nonce"})
            
            # Log headers FIRST (before any validation)
            geo_id = request.headers.get('Workload-Geo-ID')
            sig = request.headers.get('Signature')
            sig_input = request.headers.get('Signature-Input')
            if geo_id or sig or sig_input:
                logger.info("Gateway received headers (nonce)",
                            workload_geo_id=geo_id,
                            signature=sig,
                            signature_input=sig_input)
            log_headers_to_file("/nonce", geo_id, sig, sig_input)
            # update debug headers
            last_headers["nonce"]["Workload-Geo-ID"] = geo_id
            last_headers["nonce"]["Signature"] = sig
            last_headers["nonce"]["Signature-Input"] = sig_input
            last_headers["nonce"]["timestamp"] = datetime.utcnow().isoformat()
            
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
            
            # Log headers FIRST (before any validation)
            geo_id = request.headers.get('Workload-Geo-ID')
            sig = request.headers.get('Signature')
            sig_input = request.headers.get('Signature-Input')
            logger.info("Gateway received headers (metrics)",
                        workload_geo_id=geo_id,
                        signature=(sig[:32] + "...") if sig else None,
                        signature_input=sig_input)
            log_headers_to_file("/metrics", geo_id, sig, sig_input)
            # update debug headers
            last_headers["metrics"]["Workload-Geo-ID"] = geo_id
            last_headers["metrics"]["Signature"] = sig
            last_headers["metrics"]["Signature-Input"] = sig_input
            last_headers["metrics"]["timestamp"] = datetime.utcnow().isoformat()
            
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
