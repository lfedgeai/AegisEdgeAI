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
import requests
from datetime import datetime
from typing import Dict, Any, Optional
from flask import Flask, jsonify, request
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
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger(__name__)

# Initialize Flask app
app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# Initialize TPM2 utilities
try:
    tpm2_utils = TPM2Utils(
        app_ctx_path=settings.tpm2_app_ctx_path,
        device=settings.tpm2_device,
        use_swtpm=True  # Use software TPM
    )
    logger.info("TPM2 utilities initialized successfully (using software TPM)")
except TPM2Error as e:
    logger.error("Failed to initialize TPM2 utilities", error=str(e))
    sys.exit(1)

# Initialize OpenTelemetry
def setup_opentelemetry():
    """Setup OpenTelemetry tracing and metrics."""
    try:
        # Setup trace provider
        trace_provider = TracerProvider()
        trace.set_tracer_provider(trace_provider)
        
        # Setup metric provider
        metric_reader = PeriodicExportingMetricReader(
            OTLPMetricExporter(endpoint=settings.otel_endpoint)
        )
        metric_provider = MeterProvider(metric_reader=metric_reader)
        metrics.set_meter_provider(metric_provider)
        
        # Add span processor
        otlp_exporter = OTLPSpanExporter(endpoint=settings.otel_endpoint)
        span_processor = BatchSpanProcessor(otlp_exporter)
        trace_provider.add_span_processor(span_processor)
        
        # Instrument Flask and requests
        FlaskInstrumentor().instrument_app(app)
        RequestsInstrumentor().instrument()
        
        logger.info("OpenTelemetry setup completed")
        
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
                "requests_per_second": secrets.uniform(10.0, 100.0),
                "error_rate": secrets.uniform(0.0, 5.0),
                "response_time_ms": secrets.uniform(50.0, 500.0)
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
        self.base_url = f"https://{settings.collector_host}:{settings.collector_port}"
        self.session = requests.Session()
        
        # Setup SSL context for collector communication
        if not settings.collector_ssl_verify:
            self.session.verify = False
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    def get_nonce(self) -> str:
        """
        Get a nonce from the OpenTelemetry Collector.
        
        Returns:
            Nonce string from the collector
        """
        with tracer.start_as_current_span("get_nonce"):
            try:
                response = self.session.get(f"{self.base_url}/nonce")
                response.raise_for_status()
                
                data = response.json()
                nonce = data.get("nonce")
                
                if not nonce:
                    raise ValueError("No nonce received from collector")
                
                logger.info("Received nonce from collector", nonce_length=len(nonce))
                return nonce
                
            except Exception as e:
                logger.error("Failed to get nonce from collector", error=str(e))
                error_counter.add(1, {"operation": "get_nonce", "error": str(e)})
                raise
    
    def send_metrics(self, payload: Dict[str, Any]) -> bool:
        """
        Send signed metrics payload to the OpenTelemetry Collector.
        
        Args:
            payload: Signed metrics payload
            
        Returns:
            True if successful, False otherwise
        """
        with tracer.start_as_current_span("send_metrics"):
            try:
                response = self.session.post(
                    f"{self.base_url}/metrics",
                    json=payload,
                    headers={"Content-Type": "application/json"}
                )
                response.raise_for_status()
                
                logger.info("Metrics sent successfully to collector")
                return True
                
            except Exception as e:
                logger.error("Failed to send metrics to collector", error=str(e))
                error_counter.add(1, {"operation": "send_metrics", "error": str(e)})
                return False


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
            nonce = collector_client.get_nonce()
            
            # Convert metrics to JSON string and encode
            metrics_json = json.dumps(metrics_data, sort_keys=True)
            metrics_bytes = metrics_json.encode('utf-8')
            nonce_bytes = nonce.encode('utf-8')
            
            # Sign metrics with nonce using TPM2
            signature_data = tpm2_utils.sign_with_nonce(
                metrics_bytes, 
                nonce_bytes, 
                algorithm=settings.signature_algorithm
            )
            
            signature_counter.add(1, {"algorithm": settings.signature_algorithm})
            
            # Create payload
            payload = {
                "metrics": metrics_data,
                "nonce": nonce,
                "signature": signature_data["signature"],
                "digest": signature_data["digest"],
                "algorithm": signature_data["algorithm"],
                "timestamp": datetime.utcnow().isoformat()
            }
            
            # Send to collector
            success = collector_client.send_metrics(payload)
            
            if success:
                logger.info("Metrics generation and sending completed successfully")
                return jsonify({
                    "status": "success",
                    "message": "Metrics generated, signed, and sent successfully",
                    "payload_id": signature_data["digest"][:16]  # Use first 16 chars of digest as ID
                })
            else:
                return jsonify({
                    "status": "error",
                    "message": "Failed to send metrics to collector"
                }), 500
                
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
