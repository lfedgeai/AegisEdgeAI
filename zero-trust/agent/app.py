"""
OpenTelemetry Agent Microservice

This microservice is responsible for:
1. Getting nonces from OpenTelemetry Collector
2. Generating metrics data
3. Signing metrics data with nonce using TPM2
4. Sending signed payload to OpenTelemetry Collector

The agent uses TPM2 for secure signing and HTTPS for all communications.
"""

import os
import sys
import time
import json
import secrets
import random
import requests
import hashlib
from datetime import datetime
from typing import Dict, Any, Optional
from flask import Flask, jsonify, request
from email.utils import formatdate
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
from utils.tpm2_utils import TPM2Utils, TPM2Error
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
DEBUG_AGENT = os.environ.get("DEBUG_AGENT", "false").lower() == "true"

# Set log level based on debug flags
if DEBUG_ALL or DEBUG_AGENT:
    log_level = logging.DEBUG
else:
    log_level = logging.INFO

logging.basicConfig(level=log_level)

# Filter out urllib3 DEBUG messages in non-debug mode
if not (DEBUG_ALL or DEBUG_AGENT):
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("urllib3.connectionpool").setLevel(logging.WARNING)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)

logger = structlog.get_logger(__name__)
logger.info("Agent logging configuration", 
           debug_all=DEBUG_ALL,
           debug_agent=DEBUG_AGENT,
           log_level=logging.getLevelName(log_level))

# Initialize Flask app
app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# Initialize TPM2 utilities with agent-specific context file
def initialize_tpm2_utils():
    """Initialize TPM2 utilities with agent-specific context file."""
    try:
        # Get agent name from environment
        agent_name = os.environ.get("AGENT_NAME", settings.service_name)
        agent_config_path = f"agents/{agent_name}/config.json"
        
        # Default context path
        context_path = settings.tpm2_app_ctx_path
        
        # Try to load agent-specific context file from config
        try:
            with open(agent_config_path, 'r') as f:
                agent_config = json.load(f)
            
            # Use agent-specific context file if available
            if 'tpm_context_file' in agent_config:
                context_path = agent_config['tpm_context_file']
                logger.info("Using agent-specific TPM context file", 
                           agent_name=agent_name,
                           context_path=context_path)
            else:
                logger.info("Using default TPM context file", 
                           agent_name=agent_name,
                           context_path=context_path)
                
        except Exception as e:
            logger.warning("Failed to load agent config for TPM context, using default", 
                          agent_name=agent_name,
                          error=str(e),
                          context_path=context_path)
        
        # Initialize TPM2Utils with the context file
        tpm2_utils = TPM2Utils(
            app_ctx_path=context_path,
            device=settings.tpm2_device,
            use_swtpm=True  # Use software TPM
        )
        
        logger.info("TPM2 utilities initialized successfully", 
                   agent_name=agent_name,
                   context_path=context_path,
                   use_swtpm=True)
        
        return tpm2_utils
        
    except TPM2Error as e:
        logger.error("Failed to initialize TPM2 utilities", error=str(e))
        sys.exit(1)

# Initialize TPM2 utilities
tpm2_utils = initialize_tpm2_utils()

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
    name="agent_requests_total",
    description="Total number of requests processed by the agent"
)

signature_counter = meter.create_counter(
    name="agent_signatures_total",
    description="Total number of signatures created by the agent"
)

error_counter = meter.create_counter(
    name="agent_errors_total",
    description="Total number of errors encountered by the agent"
)


class MetricsGenerator:
    """Generates sample metrics data for demonstration purposes."""
    
    @staticmethod
    def generate_system_metrics() -> Dict[str, Any]:
        """Generate system metrics data."""
        import psutil
        
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "metrics": {
                "cpu_percent": psutil.cpu_percent(interval=1),
                "memory_percent": psutil.virtual_memory().percent,
                "disk_usage_percent": psutil.disk_usage('/').percent,
                "network_io": {
                    "bytes_sent": psutil.net_io_counters().bytes_sent,
                    "bytes_recv": psutil.net_io_counters().bytes_recv
                }
            },
            "service": {
                "name": settings.service_name,
                "version": settings.service_version,
                "instance_id": os.getenv("INSTANCE_ID", "unknown")
            }
        }
    
    @staticmethod
    def generate_application_metrics() -> Dict[str, Any]:
        """Generate application-specific metrics."""
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "metrics": {
                "active_connections": secrets.randbelow(100),
                "requests_per_second": random.uniform(10.0, 100.0),
                "error_rate": random.uniform(0.0, 5.0),
                "response_time_ms": random.uniform(50.0, 500.0)
            },
            "service": {
                "name": settings.service_name,
                "version": settings.service_version,
                "instance_id": os.getenv("INSTANCE_ID", "unknown")
            }
        }


class CollectorClient:
    """Client for communicating with the OpenTelemetry Collector."""
    
    def __init__(self):
        """Initialize the collector client."""
        # Use gateway instead of connecting directly to collector
        self.base_url = f"https://{settings.gateway_host}:{settings.gateway_port}"
        self.session = requests.Session()
        
        # Setup SSL context for gateway communication
        if not settings.gateway_ssl_verify:
            self.session.verify = False
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    @staticmethod
    def _now_epoch() -> int:
        return int(time.time())

    @staticmethod
    def _five_minutes_from(epoch: int) -> int:
        return epoch + 300

    @staticmethod
    def _generate_http_signature_input(keyid: str, algorithm: str, nonce_value: str) -> str:
        created = CollectorClient._now_epoch()
        expires = CollectorClient._five_minutes_from(created)
        return f"keyid=\"{keyid}\", created={created}, expires={expires}, alg=\"{algorithm}\", nonce=\"{nonce_value}\""
    
    def get_nonce(self) -> str:
        """
        Get a nonce from the OpenTelemetry Collector.
        
        Returns:
            Nonce string from the collector
        """
        with tracer.start_as_current_span("get_nonce"):
            try:
                # Get agent's raw public key from config
                agent_name = os.environ.get("AGENT_NAME", settings.service_name)
                config_path = f"agents/{agent_name}/config.json"
                
                logger.info("🔄 [AGENT] Starting nonce request", 
                           agent_name=agent_name,
                           config_path=config_path,
                           gateway_url=self.base_url)
                
                if not os.path.exists(config_path):
                    raise FileNotFoundError(f"Agent config file not found: {config_path}")
                
                # Read the raw public key from agent config
                import json
                with open(config_path, 'r') as f:
                    config = json.load(f)
                
                raw_public_key = config.get("tpm_public_key")
                if not raw_public_key:
                    raise ValueError(f"No tpm_public_key found in agent config: {config_path}")
                
                # Generate public key hash for secure transmission
                public_key_hash = hashlib.sha256(raw_public_key.encode('utf-8')).hexdigest()
                
                logger.info("📤 [AGENT] Sending nonce request to gateway", 
                           agent_name=agent_name,
                           public_key_hash=public_key_hash[:16] + "...")
                
                                # Get the nonce with public key hash parameter
                # Build headers with comprehensive error handling
                headers = {}
                
                try:
                    # Build Signature-Input header (RFC 9421) for nonce request
                    # Default: thick client, use workload public key hash as keyid
                    http_sig_nonce = secrets.token_hex(16)
                    signature_input = self._generate_http_signature_input(
                        keyid=public_key_hash,
                        algorithm="Ed25519",  # per requirement example
                        nonce_value=http_sig_nonce,
                    )
                    
                    logger.info("🔍 [AGENT] Signature-Input header created", 
                               agent_name=agent_name,
                               signature_input=signature_input)
                    
                    # Add Signature-Input header
                    headers["Signature-Input"] = signature_input
                    
                    # Build Workload-Geo-ID header (JSON) for nonce request
                    # Get geographic region from environment or use defaults
                    geo_env_var = os.environ.get("AGENT_GEO_POLICY_VIOLATION_002_GEOGRAPHIC_REGION")
                    logger.info("🔍 [AGENT] Geographic region check", 
                               agent_name=agent_name,
                               geo_env_var=geo_env_var)
                    
                    if geo_env_var:
                        geo_parts = geo_env_var.split("/")
                        geographic_region = {
                            "region": geo_parts[0] if len(geo_parts) > 0 else "US",
                            "state": geo_parts[1] if len(geo_parts) > 1 else "California", 
                            "city": geo_parts[2] if len(geo_parts) > 2 else "Santa Clara",
                        }
                    else:
                        geographic_region = {
                            "region": "US",
                            "state": "California",
                            "city": "Santa Clara",
                        }
                    
                    logger.info("🔍 [AGENT] Geographic region determined", 
                               agent_name=agent_name,
                               geographic_region=geographic_region)

                    workload_geo_id = {
                        "client_workload_id": agent_name,
                        "client_workload_location": {
                            "region": geographic_region.get("region"),
                            "state": geographic_region.get("state"),
                            "city": geographic_region.get("city"),
                        },
                        "client_workload_location_type": "geographic-region",  # precise/approximated/region
                        "client_workload_location_quality": "GNSS",  # GNSS/mobile/WiFi/IP
                        "client_type": os.environ.get("CLIENT_TYPE", "thick"),  # thick/thin (default thick)
                    }

                    # Log the Workload-Geo-ID for debugging
                    logger.info("📤 [AGENT] Sending nonce request with Workload-Geo-ID", 
                               agent_name=agent_name,
                               workload_geo_id=workload_geo_id)

                    # Add Workload-Geo-ID header
                    headers["Workload-Geo-ID"] = json.dumps(workload_geo_id, separators=(",", ":"))
                    
                    logger.info("📤 [AGENT] Final headers for nonce request", 
                               agent_name=agent_name,
                               headers=headers)
                               
                except Exception as e:
                    logger.error("❌ [AGENT] Error preparing headers for nonce request", 
                               agent_name=agent_name,
                               error=str(e),
                               error_type=type(e).__name__)
                    
                    # Ensure we at least have Signature-Input header
                    if "Signature-Input" not in headers:
                        try:
                            http_sig_nonce = secrets.token_hex(16)
                            signature_input = self._generate_http_signature_input(
                                keyid=public_key_hash,
                                algorithm="Ed25519",
                                nonce_value=http_sig_nonce,
                            )
                            headers["Signature-Input"] = signature_input
                            logger.info("📤 [AGENT] Created fallback Signature-Input header", 
                                       agent_name=agent_name,
                                       signature_input=signature_input)
                        except Exception as fallback_error:
                            logger.error("❌ [AGENT] Failed to create even fallback headers", 
                                       agent_name=agent_name,
                                       error=str(fallback_error))
                            # Last resort: empty headers
                            headers = {}
                    
                    logger.info("📤 [AGENT] Using fallback headers for nonce request", 
                               agent_name=agent_name,
                               headers=headers)

                response = self.session.get(
                    f"{self.base_url}/nonce",
                    params={"public_key_hash": public_key_hash},
                    headers=headers,
                )
                response.raise_for_status()
                
                data = response.json()
                nonce = data.get("nonce")
                
                if not nonce:
                    raise ValueError("No nonce received from collector")
                
                logger.info("✅ [AGENT] Nonce received successfully", 
                           nonce_length=len(nonce),
                           nonce_value=nonce[:16] + "...",
                           agent_name=agent_name,
                           public_key_hash=public_key_hash[:16] + "...",
                           response_status=response.status_code)
                return nonce
                
            except requests.exceptions.HTTPError as e:
                # Handle HTTP errors with detailed error messages
                error_details = "Unknown error"
                try:
                    error_response = e.response.json()
                    if "error" in error_response:
                        error_details = error_response["error"]
                except:
                    error_details = e.response.text if e.response.text else str(e)
                
                logger.error("❌ [AGENT] HTTP error from collector during nonce request", 
                           status_code=e.response.status_code,
                           error_details=error_details,
                           response_text=e.response.text[:200] if e.response.text else "No response text")
                error_counter.add(1, {"operation": "get_nonce", "error": error_details})
                raise ValueError(f"Nonce request failed: {error_details}")
                
            except Exception as e:
                logger.error("Failed to get nonce from collector", error=str(e))
                error_counter.add(1, {"operation": "get_nonce", "error": str(e)})
                raise
    

    
    def send_metrics(self, payload: Dict[str, Any]) -> tuple[bool, str]:
        """
        Send signed metrics payload to the OpenTelemetry Collector.
        
        Args:
            payload: Signed metrics payload
            
        Returns:
            Tuple of (success: bool, error_message: str)
        """
        with tracer.start_as_current_span("send_metrics"):
            try:
                # Build Workload-Geo-ID header (JSON) and Signature headers
                agent_name = payload.get("agent_name", os.environ.get("AGENT_NAME", settings.service_name))
                geographic_region = payload.get("geographic_region", {})

                # Determine client workload location details
                workload_geo_id = {
                    "client_workload_id": agent_name,
                    "client_workload_location": {
                        "region": geographic_region.get("region"),
                        "state": geographic_region.get("state"),
                        "city": geographic_region.get("city"),
                    },
                    "client_workload_location_type": "geographic-region",  # precise/approximated/region
                    "client_workload_location_quality": "GNSS",  # GNSS/mobile/WiFi/IP
                    "client_type": os.environ.get("CLIENT_TYPE", "thick"),  # thick/thin (default thick)
                }

                # Signature headers (reuse TPM signature as HTTP Signature header value)
                public_key_hash = payload.get("tpm_public_key_hash", "unknown")
                http_sig_nonce = secrets.token_hex(16)
                signature_input = self._generate_http_signature_input(
                    keyid=public_key_hash,  # thick: workload public key hash
                    algorithm="Ed25519",
                    nonce_value=http_sig_nonce,
                )
                http_signature = payload.get("signature", "")

                response = self.session.post(
                    f"{self.base_url}/metrics",
                    json=payload,
                    headers={
                        "Content-Type": "application/json",
                        "Workload-Geo-ID": json.dumps(workload_geo_id, separators=(",", ":")),
                        "Signature-Input": signature_input,
                        "Signature": http_signature,
                    },
                )
                response.raise_for_status()
                
                logger.info("✅ [AGENT] Metrics sent successfully to collector", 
                           response_status=response.status_code,
                           response_size=len(response.content))
                return True, ""
                
            except requests.exceptions.HTTPError as e:
                # Handle HTTP errors with detailed error messages
                error_details = "Unknown error"
                try:
                    error_response = e.response.json()
                    if "error" in error_response:
                        error_details = error_response["error"]
                        if "details" in error_response:
                            error_details += f" - {error_response['details']}"
                except:
                    error_details = e.response.text if e.response.text else str(e)
                
                logger.error("❌ [AGENT] HTTP error from collector", 
                           status_code=e.response.status_code,
                           error_details=error_details,
                           response_text=e.response.text[:200] if e.response.text else "No response text")
                error_counter.add(1, {"operation": "send_metrics", "error": error_details})
                return False, error_details
                
            except Exception as e:
                logger.error("Failed to send metrics to collector", error=str(e))
                error_counter.add(1, {"operation": "send_metrics", "error": str(e)})
                return False, str(e)


# Initialize collector client
collector_client = CollectorClient()


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return jsonify({
        "status": "healthy",
        "service": settings.service_name,
        "version": settings.service_version,
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/metrics/generate', methods=['POST'])
def generate_and_send_metrics():
    """
    Generate metrics, get nonce, sign data, and send to collector.
    
    Expected JSON payload:
    {
        "metric_type": "system" | "application",
        "custom_data": {...}  // optional
    }
    """
    with tracer.start_as_current_span("generate_and_send_metrics"):
        try:
            request_counter.add(1, {"endpoint": "generate_and_send_metrics"})
            
            # Get agent name first (needed for logging)
            agent_name = os.environ.get("AGENT_NAME", settings.service_name)
            
            # Parse request
            data = request.get_json()
            metric_type = data.get("metric_type", "system")
            custom_data = data.get("custom_data", {})
            
            # Generate metrics
            if metric_type == "system":
                metrics_data = MetricsGenerator.generate_system_metrics()
            elif metric_type == "application":
                metrics_data = MetricsGenerator.generate_application_metrics()
            else:
                return jsonify({"error": "Invalid metric_type"}), 400
            
            # Add custom data if provided
            if custom_data:
                metrics_data["custom_data"] = custom_data
            
            # Get nonce from collector
            logger.info("🔄 [AGENT] Initiating nonce retrieval for metrics", 
                       agent_name=agent_name,
                       metric_type=metric_type)
            
            nonce = collector_client.get_nonce()
            
            logger.info("✅ [AGENT] Nonce retrieved for metrics processing", 
                       agent_name=agent_name,
                       nonce_value=nonce[:16] + "...",
                       nonce_length=len(nonce))
            
            # Get geographic region from environment variables only
            
            # Environment variables with agent-specific prefixes
            agent_prefix = f"{agent_name.upper().replace('-', '_')}_"
            
            # Default values (fallback if no env vars set)
            default_region = "US"
            default_state = "California"
            default_city = "Santa Clara"
            
            # Get geographic region from environment variables
            env_region = os.environ.get(f"{agent_prefix}GEOGRAPHIC_REGION", 
                                       os.environ.get("GEOGRAPHIC_REGION", default_region))
            env_state = os.environ.get(f"{agent_prefix}GEOGRAPHIC_STATE", 
                                      os.environ.get("GEOGRAPHIC_STATE", default_state))
            env_city = os.environ.get(f"{agent_prefix}GEOGRAPHIC_CITY", 
                                     os.environ.get("GEOGRAPHIC_CITY", default_city))
            
            # Parse geographic region if it's in "Country/State/City" format
            if '/' in env_region:
                # Parse "Country/State/City" format
                parts = env_region.split('/')
                if len(parts) == 3:
                    country, state, city = parts
                    geographic_region = {
                        "region": country,
                        "state": state,
                        "city": city
                    }
                else:
                    # Fallback to default parsing
                    geographic_region = {
                        "region": env_region,
                        "state": env_state,
                        "city": env_city
                    }
            else:
                # Use individual environment variables
                geographic_region = {
                    "region": env_region,
                    "state": env_state,
                    "city": env_city
                }
            
            # Check if any environment variables are set (agent-specific or global)
            env_override = any([
                os.environ.get(f"{agent_prefix}GEOGRAPHIC_REGION"),
                os.environ.get(f"{agent_prefix}GEOGRAPHIC_STATE"),
                os.environ.get(f"{agent_prefix}GEOGRAPHIC_CITY"),
                os.environ.get("GEOGRAPHIC_REGION"),
                os.environ.get("GEOGRAPHIC_STATE"),
                os.environ.get("GEOGRAPHIC_CITY")
            ])
            
            logger.info("Geographic region configuration", 
                       agent_name=agent_name,
                       region=geographic_region["region"],
                       state=geographic_region["state"],
                       city=geographic_region["city"],
                       agent_prefix=agent_prefix,
                       source="env_override" if env_override else "default")
            
            # Combine metrics and geographic region for signing
            data_to_sign = {
                "metrics": metrics_data,
                "geographic_region": geographic_region
            }
            
            # Convert combined data to JSON string and encode
            data_json = json.dumps(data_to_sign, sort_keys=True)
            data_bytes = data_json.encode('utf-8')
            nonce_bytes = nonce.encode('utf-8')
            
            logger.info("🔍 [AGENT] Data prepared for signing", 
                       agent_name=agent_name,
                       data_json=data_json,
                       data_length=len(data_bytes),
                       nonce=nonce)
            
            # Sign combined data with nonce using TPM2
            signature_data = tpm2_utils.sign_with_nonce(
                data_bytes, 
                nonce_bytes, 
                algorithm=settings.signature_algorithm
            )
            
            logger.info("🔍 [AGENT] Data signed successfully", 
                       agent_name=agent_name,
                       signature=signature_data["signature"][:32] + "...",
                       digest=signature_data["digest"][:32] + "...",
                       algorithm=signature_data["algorithm"])
            
            signature_counter.add(1, {"algorithm": settings.signature_algorithm})
            
            # Get agent information from environment and config
            agent_name = os.environ.get("AGENT_NAME", settings.service_name)
            
            # Read raw public key from agent config
            config_path = f"agents/{agent_name}/config.json"
            with open(config_path, 'r') as f:
                config = json.load(f)
            raw_public_key = config.get("tpm_public_key")
            
            # Generate public key hash for secure transmission
            public_key_hash = hashlib.sha256(raw_public_key.encode('utf-8')).hexdigest()
            
            # Create payload with agent information
            payload = {
                "agent_name": agent_name,
                "tpm_public_key_hash": public_key_hash,  # Include public key hash in payload
                "geolocation": {
                    "country": geographic_region["region"],
                    "state": geographic_region["state"],
                    "city": geographic_region["city"]
                },
                "metrics": metrics_data,
                "geographic_region": geographic_region,
                "nonce": nonce,
                "signature": signature_data["signature"],
                "digest": signature_data["digest"],
                "algorithm": signature_data["algorithm"],
                "timestamp": datetime.utcnow().isoformat()
            }
            
            logger.info("🔍 [AGENT] Payload created for sending", 
                       agent_name=agent_name,
                       payload_fields=list(payload.keys()),
                       metrics_timestamp=metrics_data.get("timestamp"),
                       payload_timestamp=payload["timestamp"])
            
            # Send to collector
            logger.info("📤 [AGENT] Sending signed metrics to collector", 
                       agent_name=agent_name,
                       payload_size=len(json.dumps(payload)),
                       signature_length=len(signature_data["signature"]))
            
            success, error_message = collector_client.send_metrics(payload)
            
            if success:
                logger.info("🎉 [AGENT] Metrics generation and sending completed successfully", 
                           agent_name=agent_name,
                           payload_id=signature_data["digest"][:16],
                           total_processing_time="completed")
                return jsonify({
                    "status": "success",
                    "message": "Metrics generated, signed, and sent successfully",
                    "payload_id": signature_data["digest"][:16]  # Use first 16 chars of digest as ID
                })
            else:
                logger.error("❌ [AGENT] Failed to send metrics to collector", 
                           agent_name=agent_name,
                           error_message=error_message)
                return jsonify({
                    "status": "error",
                    "message": "Failed to send metrics to collector",
                    "details": error_message
                }), 500
                
        except ValueError as e:
            # Handle specific error messages from get_nonce
            logger.error("❌ [AGENT] Nonce request failed", error=str(e))
            error_counter.add(1, {"operation": "generate_and_send_metrics", "error": str(e)})
            return jsonify({
                "status": "error",
                "message": str(e)
            }), 400
        except Exception as e:
            logger.error("Error in generate_and_send_metrics", error=str(e))
            error_counter.add(1, {"operation": "generate_and_send_metrics", "error": str(e)})
            return jsonify({
                "status": "error",
                "message": str(e)
            }), 500


@app.route('/metrics/status', methods=['GET'])
def get_metrics_status():
    """Get current metrics generation status and statistics."""
    return jsonify({
        "service": settings.service_name,
        "version": settings.service_version,
        "tpm2_available": True,
        "collector_connected": True,  # This could be enhanced with actual connectivity check
        "timestamp": datetime.utcnow().isoformat()
    })


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({"error": "Endpoint not found"}), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors."""
    logger.error("Internal server error", error=str(error))
    return jsonify({"error": "Internal server error"}), 500


if __name__ == '__main__':
    # Generate SSL certificates if not provided
    if settings.ssl_enabled and not (settings.ssl_cert_path and settings.ssl_key_path):
        cert_path, key_path = SSLUtils.create_temp_certificate(
            f"{settings.service_name}-agent"
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
