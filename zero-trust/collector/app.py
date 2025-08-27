"""
OpenTelemetry Collector Microservice

This microservice is responsible for:
1. Providing nonces to OpenTelemetry Agents
2. Receiving metrics data from agents
3. Verifying signatures using public key verification (no TPM2 required)
4. Processing and storing verified metrics

The collector uses public key verification for signature verification and HTTPS for all communications.
"""

import os
import sys
import json
import secrets
import hashlib
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List, Set
from flask import Flask, jsonify, request
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
import structlog

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config import settings
from utils.public_key_utils import PublicKeyUtils, PublicKeyError
# TPM2Utils not needed in collector - uses pure OpenSSL verification
from utils.ssl_utils import SSLUtils, SSLError
from utils.agent_verification_utils import AgentVerificationUtils, AgentVerificationError

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
DEBUG_COLLECTOR = os.environ.get("DEBUG_COLLECTOR", "false").lower() == "true"

# Set log level based on debug flags
if DEBUG_ALL or DEBUG_COLLECTOR:
    log_level = logging.DEBUG
else:
    log_level = logging.INFO

logging.basicConfig(level=log_level)

# Filter out urllib3 DEBUG messages in non-debug mode
if not (DEBUG_ALL or DEBUG_COLLECTOR):
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("urllib3.connectionpool").setLevel(logging.WARNING)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)

logger = structlog.get_logger(__name__)
logger.info("Collector logging configuration", 
           debug_all=DEBUG_ALL,
           debug_collector=DEBUG_COLLECTOR,
           log_level=logging.getLevelName(log_level))

# Initialize Flask app
app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# Initialize public key utilities for signature verification
try:
    public_key_utils = PublicKeyUtils(
        public_key_path=settings.public_key_path,
        verify_script_path=settings.verify_script_path
    )
    logger.info("Public key utilities initialized successfully")
except PublicKeyError as e:
    logger.error("Failed to initialize public key utilities", error=str(e))
    sys.exit(1)

# Note: Collector does not use TPM2Utils - it uses pure OpenSSL verification
# via PublicKeyUtils for remote signature verification

# Initialize agent verification utilities
try:
    agent_verification_utils = AgentVerificationUtils()
    logger.info("Agent verification utilities initialized successfully")
except AgentVerificationError as e:
    logger.error("Failed to initialize agent verification utilities", error=str(e))
    sys.exit(1)

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
        
        # Instrument Flask
        FlaskInstrumentor().instrument_app(app)
        
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
    name="collector_requests_total",
    description="Total number of requests processed by the collector"
)

nonce_counter = meter.create_counter(
    name="collector_nonces_generated_total",
    description="Total number of nonces generated by the collector"
)

verification_counter = meter.create_counter(
    name="collector_signatures_verified_total",
    description="Total number of signatures verified by the collector"
)

error_counter = meter.create_counter(
    name="collector_errors_total",
    description="Total number of errors encountered by the collector"
)

# In-memory storage for nonces (in production, use a proper database)
active_nonces: Set[str] = set()
nonce_timestamps: Dict[str, datetime] = {}
# Track nonces per agent public key
nonce_agent_mapping: Dict[str, str] = {}  # nonce -> agent_public_key
agent_nonce_counts: Dict[str, int] = {}  # agent_public_key -> count


class NonceManager:
    """Manages nonce generation and validation per agent."""
    
    @staticmethod
    def generate_nonce(agent_public_key: str) -> str:
        """
        Generate a cryptographically secure random nonce for a specific agent.
        The nonce generation is completely independent of the agent's public key.
        If agent already has an active nonce, it will be replaced.
        
        Args:
            agent_public_key: The agent's public key (used only for tracking)
            
        Returns:
            Generated nonce string
        """
        # Remove any existing nonce for this agent (one nonce per agent)
        NonceManager._remove_existing_nonce_for_agent(agent_public_key)
        
        # Generate cryptographically secure random nonce (independent of public key)
        nonce = secrets.token_hex(settings.nonce_length // 2)
        
        # Store nonce and associate it with the agent's public key for tracking
        active_nonces.add(nonce)
        nonce_timestamps[nonce] = datetime.utcnow()
        nonce_agent_mapping[nonce] = agent_public_key
        
        # Track nonce count per agent (increment total count)
        agent_nonce_counts[agent_public_key] = agent_nonce_counts.get(agent_public_key, 0) + 1
        
        logger.info("🎲 [NONCE_MANAGER] Fresh nonce created for agent", 
                   nonce_length=len(nonce),
                   nonce_value=nonce[:16] + "...",
                   agent_public_key_fingerprint=agent_public_key[:16] + "...",
                   agent_nonce_count=agent_nonce_counts[agent_public_key],
                   total_active_nonces=len(active_nonces),
                   total_agents_with_nonces=len(agent_nonce_counts))
        
        return nonce
    
    @staticmethod
    def validate_nonce(nonce: str) -> bool:
        """Validate if a nonce is active and not expired."""
        if nonce not in active_nonces:
            return False
        
        # Get agent public key for this nonce
        agent_public_key = nonce_agent_mapping.get(nonce)
        
        # Check if nonce is expired (5 minutes)
        timestamp = nonce_timestamps.get(nonce)
        if timestamp and datetime.utcnow() - timestamp > timedelta(minutes=5):
            logger.info("⏰ [NONCE_MANAGER] Nonce expired", 
                       nonce_value=nonce[:16] + "...",
                       agent_public_key_fingerprint=agent_public_key[:16] + "..." if agent_public_key else "unknown")
            NonceManager._remove_nonce(nonce)
            return False
        
        return True
    
    @staticmethod
    def validate_nonce_for_agent(nonce: str, agent_public_key: str) -> bool:
        """
        Validate if a nonce is active, not expired, and belongs to the specified agent.
        
        Args:
            nonce: The nonce to validate
            agent_public_key: The agent's public key
            
        Returns:
            True if nonce is valid for this agent, False otherwise
        """
        # First check if nonce exists and is not expired
        if not NonceManager.validate_nonce(nonce):
            return False
        
        # Check if nonce belongs to this agent
        nonce_agent_key = nonce_agent_mapping.get(nonce)
        
        # Debug: Log the exact comparison values
        logger.debug("🔍 [NONCE_MANAGER] Comparing public keys for nonce validation", 
                    nonce_value=nonce[:16] + "...",
                    expected_agent_key_length=len(agent_public_key),
                    actual_agent_key_length=len(nonce_agent_key) if nonce_agent_key else 0,
                    expected_agent_key_start=agent_public_key[:50] + "...",
                    actual_agent_key_start=nonce_agent_key[:50] + "..." if nonce_agent_key else "None")
        
        if nonce_agent_key != agent_public_key:
            logger.warning("🔒 [NONCE_MANAGER] Nonce mismatch for agent", 
                          nonce_value=nonce[:16] + "...",
                          expected_agent_fingerprint=agent_public_key[:16] + "...",
                          actual_agent_fingerprint=nonce_agent_key[:16] + "..." if nonce_agent_key else "unknown")
            return False
        
        return True
    
    @staticmethod
    def consume_nonce(nonce: str) -> bool:
        """Consume a nonce (remove it from active nonces)."""
        if nonce in active_nonces:
            agent_public_key = nonce_agent_mapping.get(nonce)
            logger.info("🍽️ [NONCE_MANAGER] Consuming nonce for agent", 
                       nonce_value=nonce[:16] + "...",
                       agent_public_key_fingerprint=agent_public_key[:16] + "..." if agent_public_key else "unknown",
                       remaining_active_nonces=len(active_nonces) - 1,
                       remaining_agent_nonces=agent_nonce_counts.get(agent_public_key, 0) - 1 if agent_public_key else 0)
            NonceManager._remove_nonce(nonce)
            return True
        return False
    
    @staticmethod
    def _remove_nonce(nonce: str):
        """Remove a nonce and update tracking."""
        if nonce in active_nonces:
            agent_public_key = nonce_agent_mapping.get(nonce)
            if agent_public_key:
                # Decrease count for this agent
                if agent_public_key in agent_nonce_counts:
                    agent_nonce_counts[agent_public_key] = max(0, agent_nonce_counts[agent_public_key] - 1)
                
                # Remove from mappings
                nonce_agent_mapping.pop(nonce, None)
            
            active_nonces.discard(nonce)
            nonce_timestamps.pop(nonce, None)
    
    @staticmethod
    def _remove_existing_nonce_for_agent(agent_public_key: str):
        """Remove any existing nonce for a specific agent."""
        nonces_to_remove = []
        for nonce, key in nonce_agent_mapping.items():
            if key == agent_public_key:
                nonces_to_remove.append(nonce)
        
        for nonce in nonces_to_remove:
            logger.info("🔄 [NONCE_MANAGER] Replacing existing nonce for agent", 
                       nonce_value=nonce[:16] + "...",
                       agent_public_key_fingerprint=agent_public_key[:16] + "...")
            NonceManager._remove_nonce(nonce)
    
    @staticmethod
    def cleanup_expired_nonces():
        """Clean up expired nonces."""
        current_time = datetime.utcnow()
        expired_nonces = [
            nonce for nonce, timestamp in nonce_timestamps.items()
            if current_time - timestamp > timedelta(minutes=5)
        ]
        
        for nonce in expired_nonces:
            NonceManager._remove_nonce(nonce)
        
        if expired_nonces:
            logger.info("🧹 [NONCE_MANAGER] Cleaned up expired nonces", 
                       count=len(expired_nonces),
                       remaining_active_nonces=len(active_nonces))
    
    @staticmethod
    def get_agent_nonce_stats() -> Dict[str, Any]:
        """Get statistics about nonce usage per agent."""
        # Get detailed stats per agent
        agent_stats = {}
        for agent_public_key, count in agent_nonce_counts.items():
            agent_stats[agent_public_key[:16] + "..."] = {
                "nonce_count": count,
                "public_key_fingerprint": agent_public_key[:16] + "..."
            }
        
        return {
            "total_active_nonces": len(active_nonces),
            "agent_nonce_counts": agent_nonce_counts.copy(),
            "total_agents_with_nonces": len(agent_nonce_counts),
            "agent_details": agent_stats
        }
    
    @staticmethod
    def get_agent_nonce_count(agent_public_key: str) -> int:
        """Get the number of active nonces for a specific agent."""
        return agent_nonce_counts.get(agent_public_key, 0)
    
    @staticmethod
    def get_agent_nonces(agent_public_key: str) -> List[str]:
        """Get all active nonces for a specific agent."""
        agent_nonces = []
        for nonce, key in nonce_agent_mapping.items():
            if key == agent_public_key:
                agent_nonces.append(nonce)
        return agent_nonces


class MetricsProcessor:
    """Processes and validates received metrics."""
    
    @staticmethod
    def validate_metrics_payload(payload: Dict[str, Any]) -> bool:
        """
        Validate the structure of the metrics payload.
        
        Args:
            payload: The metrics payload to validate
            
        Returns:
            True if valid, False otherwise
        """
        required_fields = ["agent_name", "tpm_public_key_hash", "geolocation", "metrics", "geographic_region", "nonce", "signature", "algorithm", "timestamp"]
        
        for field in required_fields:
            if field not in payload:
                logger.warning("Missing required field in payload", field=field)
                return False
        
        if not isinstance(payload["agent_name"], str):
            logger.warning("Agent name field must be a string")
            return False
        
        if not isinstance(payload["tpm_public_key_hash"], str):
            logger.warning("TPM public key hash field must be a string")
            return False
        
        if not isinstance(payload["geolocation"], dict):
            logger.warning("Geolocation field must be a dictionary")
            return False
        
        if not isinstance(payload["metrics"], dict):
            logger.warning("Metrics field must be a dictionary")
            return False
        
        if not isinstance(payload["geographic_region"], dict):
            logger.warning("Geographic region field must be a dictionary")
            return False
        
        if not isinstance(payload["nonce"], str):
            logger.warning("Nonce field must be a string")
            return False
        
        if not isinstance(payload["signature"], str):
            logger.warning("Signature field must be a string")
            return False
        
        return True
    
    @staticmethod
    def verify_geographic_region(payload: Dict[str, Any]) -> bool:
        """
        Verify that the geographic region in the payload matches the allowed policy.
        
        Args:
            payload: The metrics payload to verify
            
        Returns:
            True if geographic region is allowed, False otherwise
        """
        try:
            geographic_region = payload["geographic_region"]
            
            if not geographic_region:
                logger.warning("No geographic region information found in payload")
                return False
            
            region = geographic_region.get("region")
            state = geographic_region.get("state")
            city = geographic_region.get("city")
            
            # Check if region is allowed
            if region not in settings.allowed_regions:
                logger.warning("Geographic region not allowed", 
                             region=region, 
                             allowed_regions=settings.allowed_regions)
                return False
            
            # Check if state is allowed (if specified)
            if state and state not in settings.allowed_states:
                logger.warning("Geographic state not allowed", 
                             state=state, 
                             allowed_states=settings.allowed_states)
                return False
            
            # Check if city is allowed (if specified)
            if city and city not in settings.allowed_cities:
                logger.warning("Geographic city not allowed", 
                             city=city, 
                             allowed_cities=settings.allowed_cities)
                return False
            
            logger.info("Geographic region verification successful", 
                       region=region, state=state, city=city)
            return True
            
        except Exception as e:
            logger.warning("Geographic region verification failed", error=str(e))
            return False
    
    @staticmethod
    def verify_signature(payload: Dict[str, Any]) -> bool:
        """
        Verify the signature of the metrics payload using the agent's specific public key.
        
        Args:
            payload: The metrics payload to verify
            
        Returns:
            True if signature is valid, False otherwise
        """
        try:
            logger.info("🔍 [COLLECTOR] Starting signature verification", 
                       agent_name=payload.get("agent_name"),
                       nonce=payload.get("nonce", "")[:16] + "...",
                       signature=payload.get("signature", "")[:32] + "...")
            
            # Get agent's public key from allowlist
            agent_info = agent_verification_utils.get_agent_info(payload["agent_name"])
            if not agent_info:
                logger.error("Agent not found in allowlist", agent_name=payload["agent_name"])
                return False
            
            agent_public_key = agent_info.get("tpm_public_key")
            if not agent_public_key:
                logger.error("Agent public key not found in allowlist", agent_name=payload["agent_name"])
                return False
            
            logger.info("🔍 [COLLECTOR] Found agent in allowlist", 
                       agent_name=payload["agent_name"],
                       public_key_length=len(agent_public_key))
            
            # The agent should send the exact data that was signed
            # We need to reconstruct the exact data structure that was signed
            # The agent signs: {"metrics": {...}, "geographic_region": {...}}
            data_to_verify = {
                "metrics": payload["metrics"],
                "geographic_region": payload["geographic_region"]
            }
            
            # Use the exact same JSON serialization as the agent
            data_json = json.dumps(data_to_verify, sort_keys=True)
            data_bytes = data_json.encode('utf-8')
            nonce_bytes = payload["nonce"].encode('utf-8')
            
            logger.info("🔍 [COLLECTOR] Reconstructed data for verification", 
                       data_json=data_json,
                       data_length=len(data_bytes),
                       nonce=payload["nonce"])
            
            # Verify signature using agent's specific public key
            # Pass signature as hex string (not bytes)
            is_valid = public_key_utils.verify_with_nonce_and_public_key(
                data_bytes,
                nonce_bytes,
                payload["signature"],  # Pass as hex string
                agent_public_key,
                algorithm=payload["algorithm"]
            )
            
            logger.info("🔍 [COLLECTOR] Signature verification result", 
                       is_valid=is_valid,
                       agent_name=payload["agent_name"])
            
            return is_valid
            
        except Exception as e:
            logger.warning("🔍 [COLLECTOR] Signature verification failed", error=str(e))
            return False
    
    @staticmethod
    def verify_signature_with_key(payload: Dict[str, Any], agent_public_key: str) -> bool:
        """
        Verify the signature of the metrics payload using a specific public key.
        
        Args:
            payload: The metrics payload to verify
            agent_public_key: The agent's public key to use for verification
            
        Returns:
            True if signature is valid, False otherwise
        """
        try:
            logger.info("🔍 [COLLECTOR] Starting signature verification with key", 
                       agent_name=payload.get("agent_name"),
                       nonce=payload.get("nonce", "")[:16] + "...",
                       signature=payload.get("signature", "")[:32] + "...",
                       public_key_length=len(agent_public_key))
            
            # The agent should send the exact data that was signed
            # We need to reconstruct the exact data structure that was signed
            # The agent signs: {"metrics": {...}, "geographic_region": {...}}
            data_to_verify = {
                "metrics": payload["metrics"],
                "geographic_region": payload["geographic_region"]
            }
            
            # Use the exact same JSON serialization as the agent
            data_json = json.dumps(data_to_verify, sort_keys=True)
            data_bytes = data_json.encode('utf-8')
            nonce_bytes = payload["nonce"].encode('utf-8')
            
            logger.info("🔍 [COLLECTOR] Reconstructed data for verification with key", 
                       data_json=data_json,
                       data_length=len(data_bytes),
                       nonce=payload["nonce"])
            
            # Use the verify_app_message_signature.sh script with the agent's public key
            # This is the same method used by the agent for verification
            import tempfile
            import subprocess
            import os
            
            # Create temporary files for verification
            with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as pubkey_file, \
                 tempfile.NamedTemporaryFile(mode='wb', suffix='.bin', delete=False) as message_file, \
                 tempfile.NamedTemporaryFile(mode='wb', suffix='.bin', delete=False) as signature_file:
                
                # Write the public key to temporary file
                pubkey_file.write(agent_public_key)
                pubkey_file.flush()
                
                # Write the combined data (data + nonce) to message file
                message_file.write(data_bytes + nonce_bytes)
                message_file.flush()
                
                # Convert hex signature to bytes and write to signature file
                signature_bytes = bytes.fromhex(payload["signature"])
                signature_file.write(signature_bytes)
                signature_file.flush()
                
                # Get the verify script path
                script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                verify_script = os.path.join(script_dir, "tpm", "verify_app_message_signature.sh")
                
                # Make sure the script is executable
                os.chmod(verify_script, 0o755)
                
                # Run the verification script with the agent's public key
                cmd = [
                    verify_script,
                    pubkey_file.name,  # Use the agent's public key file
                    message_file.name,     # Message file
                    signature_file.name    # Signature file
                ]
                
                try:
                    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                    is_valid = True
                    logger.info("🔍 [COLLECTOR] TPM2 signature verification successful")
                except subprocess.CalledProcessError as e:
                    is_valid = False
                    logger.warning("🔍 [COLLECTOR] TPM2 signature verification failed", 
                                 stderr=e.stderr, stdout=e.stdout)
                finally:
                    # Clean up temporary files
                    for temp_file in [pubkey_file.name, message_file.name, signature_file.name]:
                        try:
                            os.unlink(temp_file)
                        except:
                            pass
            
            logger.info("🔍 [COLLECTOR] Signature verification result with key", 
                       is_valid=is_valid,
                       agent_name=payload["agent_name"])
            
            return is_valid
            
        except Exception as e:
            logger.warning("🔍 [COLLECTOR] Signature verification failed with key", error=str(e))
            return False
    
    @staticmethod
    def process_metrics(payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process and store the verified metrics.
        
        Args:
            payload: The verified metrics payload
            
        Returns:
            Processing result
        """
        try:
            # Extract metrics data
            metrics_data = payload["metrics"]
            
            # Add processing metadata
            processed_metrics = {
                "original_metrics": metrics_data,
                "processing_timestamp": datetime.utcnow().isoformat(),
                "signature_verified": True,
                "nonce_consumed": True,
                "collector_id": os.getenv("COLLECTOR_ID", "unknown")
            }
            
            # In a real implementation, you would store this in a database
            # or forward it to a metrics storage system
            
            logger.info("Metrics processed successfully", 
                       service=metrics_data.get("service", {}).get("name"),
                       timestamp=metrics_data.get("timestamp"))
            
            return processed_metrics
            
        except Exception as e:
            logger.error("Failed to process metrics", error=str(e))
            raise


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return jsonify({
        "status": "healthy",
        "service": settings.service_name,
        "version": settings.service_version,
        "active_nonces": len(active_nonces),
        "collector_allowlist": {
            "agent_count": len(agent_verification_utils.allowed_agents),
            "agents": [agent.get('agent_name') for agent in agent_verification_utils.allowed_agents]
        },
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/nonces/stats', methods=['GET'])
def get_nonce_stats():
    """Get nonce statistics per agent."""
    with tracer.start_as_current_span("get_nonce_stats"):
        try:
            request_counter.add(1, {"endpoint": "get_nonce_stats"})
            
            stats = NonceManager.get_agent_nonce_stats()
            
            logger.info("Retrieved nonce statistics", 
                       total_active_nonces=stats["total_active_nonces"],
                       total_agents=stats["total_agents_with_nonces"])
            
            return jsonify({
                "nonce_statistics": stats,
                "timestamp": datetime.utcnow().isoformat()
            })
            
        except Exception as e:
            logger.error("Error getting nonce statistics", error=str(e))
            error_counter.add(1, {"operation": "get_nonce_stats", "error": str(e)})
            return jsonify({
                "error": "Failed to get nonce statistics"
            }), 500


@app.route('/nonce', methods=['GET'])
def get_nonce():
    """Generate and return a nonce for agents."""
    with tracer.start_as_current_span("get_nonce"):
        try:
            request_counter.add(1, {"endpoint": "get_nonce"})
            
            # Get public key hash from request
            public_key_hash = request.args.get("public_key_hash")
            if not public_key_hash:
                logger.warning("No public key hash provided for nonce request")
                return jsonify({"error": "public_key_hash parameter is required"}), 400
            
            # Find the agent by public key hash
            agent_found = False
            agent_name = None
            raw_public_key = None
            
            for agent in agent_verification_utils.allowed_agents:
                agent_raw_key = agent.get('tpm_public_key')
                if agent_raw_key:
                    agent_key_hash = hashlib.sha256(agent_raw_key.encode('utf-8')).hexdigest()
                    if agent_key_hash == public_key_hash:
                        agent_found = True
                        agent_name = agent.get('agent_name')
                        raw_public_key = agent_raw_key
                        break
            
            if not agent_found:
                logger.warning("❌ [COLLECTOR] Nonce request from unauthorized agent", 
                             agent_public_key_hash=public_key_hash[:16] + "...",
                             request_ip=request.remote_addr)
                return jsonify({
                    "error": "Agent not found in allowlist",
                    "rejected_by": "collector",
                    "validation_type": "agent_verification",
                    "details": {
                        "public_key_hash": public_key_hash,
                        "validation_type": "public_key_hash",
                        "allowlist_status": "not_found"
                    },
                    "timestamp": datetime.utcnow().isoformat()
                }), 403
            
            # Clean up expired nonces
            NonceManager.cleanup_expired_nonces()
            
            # Generate cryptographically secure random nonce for this agent
            # The raw public key is used only for tracking which agent the nonce belongs to
            logger.info("🔄 [COLLECTOR] Starting nonce generation", 
                       agent_name=agent_name,
                       agent_public_key_fingerprint=raw_public_key[:16] + "...",
                       request_ip=request.remote_addr)
            
            nonce = NonceManager.generate_nonce(raw_public_key)
            nonce_counter.add(1)
            
            logger.info("✅ [COLLECTOR] Nonce generated successfully", 
                       nonce_length=len(nonce),
                       nonce_value=nonce[:16] + "...",
                       agent_public_key_fingerprint=raw_public_key[:16] + "...",
                       total_active_nonces=len(active_nonces))
            
            return jsonify({
                "nonce": nonce,
                "expires_in": "5 minutes",
                "timestamp": datetime.utcnow().isoformat(),
                "agent_public_key_fingerprint": raw_public_key[:16] + "..."
            })
            
        except Exception as e:
            logger.error("Error generating nonce", error=str(e))
            error_counter.add(1, {"operation": "get_nonce", "error": str(e)})
            return jsonify({
                "error": "Failed to generate nonce"
            }), 500





@app.route('/metrics', methods=['POST'])
def receive_metrics():
    """
    Receive and verify metrics from agents.
    
    Expected JSON payload:
    {
        "agent_name": "agent-001",
        "tpm_public_key_hash": "a1b2c3d4e5f6...",
        "geolocation": {
            "country": "US",
            "state": "California", 
            "city": "Santa Clara"
        },
        "metrics": {...},
        "geographic_region": {
            "region": "US",
            "state": "California", 
            "city": "Santa Clara"
        },
        "nonce": "...",
        "signature": "...",
        "algorithm": "sha256",
        "timestamp": "..."
    }
    """
    with tracer.start_as_current_span("receive_metrics"):
        try:
            request_counter.add(1, {"endpoint": "receive_metrics"})
            
            # Parse request
            payload = request.get_json()
            
            if not payload:
                return jsonify({"error": "No payload provided"}), 400
            
            # Validate payload structure
            if not MetricsProcessor.validate_metrics_payload(payload):
                return jsonify({"error": "Invalid payload structure"}), 400
            
            # Get agent's raw public key for nonce validation
            agent_info = agent_verification_utils.get_agent_info(payload["agent_name"])
            if not agent_info:
                logger.error("Agent not found in allowlist", agent_name=payload["agent_name"])
                return jsonify({"error": "Agent not found in allowlist"}), 400
            
            agent_raw_public_key = agent_info.get("tpm_public_key")
            if not agent_raw_public_key:
                logger.error("Agent public key not found in allowlist", agent_name=payload["agent_name"])
                return jsonify({"error": "Agent public key not found"}), 400
            
            # Convert raw public key to PEM format for signature verification
            agent_public_key_pem = f"-----BEGIN PUBLIC KEY-----\n{agent_raw_public_key}\n-----END PUBLIC KEY-----"
            
            # Get the public key hash from the payload for validation
            payload_public_key_hash = payload.get("tpm_public_key_hash")
            if not payload_public_key_hash:
                logger.error("No TPM public key hash in payload", agent_name=payload["agent_name"])
                return jsonify({"error": "No TPM public key hash in payload"}), 400
            
            # Generate hash from the allowlist public key for comparison
            allowlist_public_key_hash = hashlib.sha256(agent_raw_public_key.encode('utf-8')).hexdigest()
            
            # Validate that the public key hash in the payload matches the one in the allowlist
            if payload_public_key_hash != allowlist_public_key_hash:
                logger.error("Public key hash mismatch between payload and allowlist", 
                           agent_name=payload["agent_name"],
                           payload_hash=payload_public_key_hash[:16] + "...",
                           allowlist_hash=allowlist_public_key_hash[:16] + "...")
                return jsonify({"error": "Public key hash mismatch"}), 400
            
            # Validate nonce for this specific agent (using raw public key for tracking)
            logger.info("🔍 [COLLECTOR] Validating nonce for agent", 
                       nonce_value=payload["nonce"][:16] + "...",
                       agent_name=payload.get("agent_name"),
                       agent_public_key_fingerprint=agent_raw_public_key[:16] + "...")
            
            if not NonceManager.validate_nonce_for_agent(payload["nonce"], agent_raw_public_key):
                logger.warning("❌ [COLLECTOR] Nonce validation failed for agent", 
                             nonce=payload["nonce"][:16] + "...",
                             agent_name=payload.get("agent_name"),
                             agent_public_key_fingerprint=agent_raw_public_key[:16] + "...")
                return jsonify({"error": "Invalid or expired nonce for this agent"}), 400
            
            logger.info("✅ [COLLECTOR] Nonce validation successful for agent", 
                       nonce_value=payload["nonce"][:16] + "...",
                       agent_name=payload.get("agent_name"),
                       agent_public_key_fingerprint=agent_raw_public_key[:16] + "...")
            
            # Verify signature using the agent's public key
            if not MetricsProcessor.verify_signature_with_key(payload, agent_public_key_pem):
                logger.warning("Signature verification failed", 
                             service=payload["metrics"].get("service", {}).get("name"),
                             agent_name=payload.get("agent_name"))
                verification_counter.add(1, {"status": "failed"})
                return jsonify({
                    "error": "Signature verification failed",
                    "rejected_by": "collector",
                    "validation_type": "signature_verification",
                    "details": {
                        "agent_name": payload.get("agent_name"),
                        "validation_type": "signature_verification",
                        "error_type": "verification_failed"
                    },
                    "timestamp": datetime.utcnow().isoformat()
                }), 400
            
            # Verify agent information with detailed error checking
            agent_name = payload.get("agent_name")
            geolocation = payload.get("geolocation", {})
            
            # Check if agent exists in allowlist
            agent_config = agent_verification_utils.get_agent_info(agent_name)
            if not agent_config:
                logger.warning("Agent not found in allowlist", agent_name=agent_name)
                verification_counter.add(1, {"status": "failed"})
                return jsonify({
                    "error": f"Agent '{agent_name}' not found in allowlist",
                    "rejected_by": "collector",
                    "validation_type": "agent_verification",
                    "details": {
                        "agent_name": agent_name,
                        "validation_type": "agent_verification",
                        "error_type": "agent_not_found",
                        "allowlist_status": "not_found"
                    },
                    "timestamp": datetime.utcnow().isoformat()
                }), 400
            
            # Check geolocation specifically
            expected_geo = agent_config.get('geolocation', {})
            if (expected_geo.get('country') != geolocation.get('country') or
                expected_geo.get('state') != geolocation.get('state') or
                expected_geo.get('city') != geolocation.get('city')):
                
                logger.warning("Geolocation mismatch", 
                             agent_name=agent_name,
                             expected_geo=expected_geo,
                             received_geo=geolocation)
                verification_counter.add(1, {"status": "failed"})
                return jsonify({
                    "error": "Geolocation verification failed",
                    "rejected_by": "collector",
                    "validation_type": "geolocation_policy",
                    "details": {
                        "expected": expected_geo,
                        "received": geolocation,
                        "agent_name": agent_name
                    },
                    "timestamp": datetime.utcnow().isoformat()
                }), 400
            
            # Verify agent information (this will check public key and other details)
            if not agent_verification_utils.verify_agent(payload):
                logger.warning("Agent verification failed", 
                             agent_name=agent_name,
                             service=payload["metrics"].get("service", {}).get("name"))
                verification_counter.add(1, {"status": "failed"})
                return jsonify({
                    "error": "Agent verification failed",
                    "rejected_by": "collector",
                    "validation_type": "agent_verification",
                    "details": {
                        "agent_name": agent_name,
                        "validation_type": "agent_verification",
                        "error_type": "verification_failed",
                        "service": payload["metrics"].get("service", {}).get("name")
                    },
                    "timestamp": datetime.utcnow().isoformat()
                }), 400
            
            # Verify geographic region
            if not MetricsProcessor.verify_geographic_region(payload):
                logger.warning("Geographic region verification failed", 
                             service=payload["metrics"].get("service", {}).get("name"))
                verification_counter.add(1, {"status": "failed"})
                return jsonify({
                    "error": "Geographic region verification failed",
                    "rejected_by": "collector",
                    "validation_type": "geographic_region",
                    "details": {
                        "agent_name": payload.get("agent_name"),
                        "validation_type": "geographic_region",
                        "error_type": "verification_failed",
                        "service": payload["metrics"].get("service", {}).get("name")
                    },
                    "timestamp": datetime.utcnow().isoformat()
                }), 400
            
            # Consume nonce
            NonceManager.consume_nonce(payload["nonce"])
            
            # Process metrics
            processed_metrics = MetricsProcessor.process_metrics(payload)
            
            verification_counter.add(1, {"status": "success"})
            
            logger.info("Metrics received and verified successfully",
                       service=payload["metrics"].get("service", {}).get("name"))
            
            return jsonify({
                "status": "success",
                "message": "Metrics received and verified successfully",
                "processing_id": processed_metrics["processing_timestamp"]
            })
            
        except Exception as e:
            logger.error("Error processing metrics", error=str(e))
            error_counter.add(1, {"operation": "receive_metrics", "error": str(e)})
            return jsonify({
                "error": "Failed to process metrics"
            }), 500


@app.route('/metrics/status', methods=['GET'])
def get_metrics_status():
    """Get current metrics processing status and statistics."""
    return jsonify({
        "service": settings.service_name,
        "version": settings.service_version,
        "tpm2_available": True,
        "active_nonces": len(active_nonces),
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/agents', methods=['GET'])
def list_allowed_agents():
    """List all allowed agents."""
    try:
        agent_names = agent_verification_utils.list_allowed_agents()
        return jsonify({
            "status": "success",
            "allowed_agents": agent_names,
            "count": len(agent_names),
            "timestamp": datetime.utcnow().isoformat()
        })
    except Exception as e:
        logger.error("Error listing allowed agents", error=str(e))
        return jsonify({
            "error": "Failed to list allowed agents"
        }), 500


@app.route('/agents/<agent_name>', methods=['GET'])
def get_agent_info(agent_name):
    """Get information about a specific agent."""
    try:
        agent_info = agent_verification_utils.get_agent_info(agent_name)
        if agent_info:
            return jsonify({
                "status": "success",
                "agent_info": agent_info,
                "timestamp": datetime.utcnow().isoformat()
            })
        else:
            return jsonify({
                "error": "Agent not found"
            }), 404
    except Exception as e:
        logger.error("Error getting agent info", error=str(e))
        return jsonify({
            "error": "Failed to get agent info"
        }), 500


@app.route('/nonces/cleanup', methods=['POST'])
def cleanup_nonces():
    """Manually trigger nonce cleanup."""
    try:
        before_count = len(active_nonces)
        NonceManager.cleanup_expired_nonces()
        after_count = len(active_nonces)
        
        cleaned_count = before_count - after_count
        
        logger.info("Manual nonce cleanup completed", 
                   cleaned_count=cleaned_count,
                   remaining_count=after_count)
        
        return jsonify({
            "status": "success",
            "cleaned_count": cleaned_count,
            "remaining_count": after_count
        })
        
    except Exception as e:
        logger.error("Error during nonce cleanup", error=str(e))
        return jsonify({"error": "Cleanup failed"}), 500


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
            f"{settings.service_name}-collector"
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
