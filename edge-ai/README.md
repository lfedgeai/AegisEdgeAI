# OpenTelemetry Microservice Architecture with TPM2 Security

A production-ready microservice architecture that implements secure metrics collection using OpenTelemetry, TPM2 hardware
security, and HTTPS communication. This system provides end-to-end hardware-backed cryptographically verifiable security and
trust with proof of residency and proof of geofencing for telemetry data collection.

## Architecture Overview

The system consists of three main microservices:

1. **OpenTelemetry Agent** - Generates metrics, gets nonces, signs data with TPM2, and sends to collector
2. **OpenTelemetry Collector** - Provides nonces, receives metrics, verifies signatures using TPM2
3. **API Gateway** - Man-in-the-middle proxy that terminates TLS from agents and reinitiates TLS to collector

### Security Features

- **TPM2 Hardware Security**: All cryptographic operations use TPM2 hardware
- **HTTPS/TLS**: All communications are encrypted with self-signed certificates
- **Nonce-based Authentication**: Prevents replay attacks
- **Rate Limiting**: API Gateway implements request rate limiting
- **Signature Verification**: All metrics are cryptographically signed and verified
- **Geographic Region Verification**: Enforces geographic compliance and data residency requirements
- **Geofencing**: Ensures metrics only come from authorized geographic regions

## Geographic Region Security

### Overview

The system implements geographic region verification to ensure data compliance and residency requirements. This feature:

- **Enforces Geographic Policy**: Only accepts metrics from authorized regions/states/cities
- **Signed Geographic Data**: Geographic region information is cryptographically signed with TPM2
- **Separate from Metrics**: Geographic region is kept separate from metrics data but both are signed together
- **Configurable Policy**: Easy to configure allowed geographic areas via environment variables

### Geographic Region Structure

The geographic region is included in the payload as a separate field:

```json
{
  "metrics": {
    "timestamp": "2025-08-15T06:00:00Z",
    "metrics": {...},
    "service": {...}
  },
  "geographic_region": {
    "region": "US",
    "state": "California",
    "city": "Santa Clara"
  },
  "nonce": "...",
  "signature": "...",
  "digest": "...",
  "algorithm": "sha256",
  "timestamp": "..."
}
```

### Geographic Policy Enforcement

The collector verifies geographic regions against configured policies:

1. **Region Verification**: Checks if the region is in the allowed regions list
2. **State Verification**: Checks if the state is in the allowed states list (if specified)
3. **City Verification**: Checks if the city is in the allowed cities list (if specified)
4. **Signature Verification**: Ensures geographic region data is cryptographically signed
5. **Policy Rejection**: Metrics from unauthorized regions are rejected with appropriate error messages

### Geographic Region Configuration

Configure geographic regions and policies using environment variables:

```bash
# Agent Geographic Region (where the agent is located)
GEOGRAPHIC_REGION=US
GEOGRAPHIC_STATE=California
GEOGRAPHIC_CITY=Santa Clara

# Collector Geographic Policy (allowed regions)
ALLOWED_REGIONS=["US"]
ALLOWED_STATES=["California", "Texas", "New York"]
ALLOWED_CITIES=["Santa Clara", "San Francisco", "Austin", "New York"]
```

## Prerequisites

### System Requirements

- Python 3.11+
- Software TPM (swtpm) - no hardware TPM required
- TPM2 tools installed
- Docker and Docker Compose (optional)

### Software TPM (swtpm) Setup

Before running the microservices, ensure swtpm is properly configured with persistent keys:

```bash
# Install swtpm and TPM2 tools
sudo apt-get install swtpm swtpm-tools tpm2-tools

# Start software TPM and set up persistent keys
./swtpm.sh
./tpm-ek-ak-persist.sh
./tpm-app-persist.sh

# Verify swtpm is accessible
TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321" tpm2_getcap properties-fixed

# Verify persistent handles
TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321" tpm2 getcap handles-persistent
```

### Required TPM2 Context Files

The system requires the following TPM2 context files (already present in the repository):

- `app.ctx` - Application context for signing
- `primary.ctx` - Primary key context
- `ak.ctx` - Attestation key context
- `ek.ctx` - Endorsement key context

## Installation

### Option 1: Direct Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd edge-ai
   ```

2. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Set up environment variables** (optional):
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

### Option 2: Docker Deployment

1. **Build and run with Docker Compose**:
   ```bash
   docker-compose up --build
   ```

2. **Or build individual container**:
   ```bash
   docker build -t opentelemetry-microservices .
   docker run -d --name opentelemetry-microservices \
     -p 8442:8442 -p 8443:8443 -p 8444:8444 \
     --device /dev/tpm0:/dev/tpm0 \
     opentelemetry-microservices
   ```

## Usage

### Starting the Services

#### Using the Startup Script

```bash

# Start all microservices
python start_services.py
```

This will start:
- Collector on port 8444
- Gateway on port 8443  
- Agent on port 8442

#### Manual Service Startup

```bash
# First, start software TPM (swtpm)
python start_swtpm.py &

# Start Collector
SERVICE_NAME=opentelemetry-collector PORT=8444 python collector/app.py &

# Start Gateway
SERVICE_NAME=opentelemetry-gateway PORT=8443 python gateway/app.py &

# Start Agent
SERVICE_NAME=opentelemetry-agent PORT=8442 python agent/app.py &
```

### Testing the System

#### Test Software TPM Setup

First, test that the software TPM is properly configured:

```bash
python test_swtpm_setup.py
```

This will test:
- swtpm accessibility
- TPM2 initialization
- Persistent key handles
- Basic TPM2 operations
- Key operations

#### Test Microservices

Then test the complete microservice architecture:

```bash
python test_client.py
```

This will test:
- Health endpoints
- Nonce generation
- Metrics generation and signing
- Signature verification
- Rate limiting
- System status endpoints

#### Test Geographic Region Functionality

Test the geographic region verification and policy enforcement:

```bash
# Test with valid geographic region
curl -X POST https://localhost:8442/metrics/generate \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "system"}' \
  --insecure

# The agent will automatically include geographic region information
# and the collector will verify it against the configured policy
```

To test geographic region policy enforcement, you can:

1. **Modify the agent's geographic region** in the environment variables
2. **Update the collector's allowed regions** to exclude the agent's region
3. **Verify that metrics are rejected** when geographic policy is violated

Example geographic region test:

```bash
# Set agent to a different region
export GEOGRAPHIC_REGION=EU
export GEOGRAPHIC_STATE=Unknown
export GEOGRAPHIC_CITY=Unknown

# Restart the agent
python agent/app.py &

# Try to send metrics (should be rejected)
curl -X POST https://localhost:8442/metrics/generate \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "system"}' \
  --insecure

# Expected response: {"error": "Geographic region verification failed"}
```

### API Endpoints

#### Agent Endpoints (Port 8442)

- `GET /health` - Health check
- `POST /metrics/generate` - Generate and send metrics
- `GET /metrics/status` - Get agent status

#### Gateway Endpoints (Port 8443)

- `GET /health` - Health check
- `GET /nonce` - Get nonce (proxied to collector)
- `POST /metrics` - Send metrics (proxied to collector)
- `GET /gateway/status` - Gateway status
- `GET /gateway/rate-limits` - Rate limit information

#### Collector Endpoints (Port 8444)

- `GET /health` - Health check
- `GET /nonce` - Generate nonce
- `POST /metrics` - Receive and verify metrics (includes geographic region verification)
- `GET /metrics/status` - Collector status
- `POST /nonces/cleanup` - Clean up expired nonces

### Example API Usage

#### Generate and Send Metrics

```bash
# Generate system metrics (includes geographic region)
curl -X POST https://localhost:8442/metrics/generate \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "system"}' \
  --insecure

# Generate application metrics with custom data
curl -X POST https://localhost:8442/metrics/generate \
  -H "Content-Type: application/json" \
  -d '{
    "metric_type": "application",
    "custom_data": {
      "user_id": "12345",
      "session_id": "abc123"
    }
  }' \
  --insecure
```

The agent automatically includes geographic region information in the payload:

```json
{
  "metrics": {
    "timestamp": "2025-08-15T06:00:00Z",
    "metrics": {
      "cpu_percent": 45.2,
      "memory_percent": 67.8,
      "disk_usage_percent": 23.1
    },
    "service": {
      "name": "opentelemetry-agent",
      "version": "1.0.0",
      "instance_id": "instance-001"
    }
  },
  "geographic_region": {
    "region": "US",
    "state": "California",
    "city": "Santa Clara"
  },
  "nonce": "abc123...",
  "signature": "def456...",
  "digest": "ghi789...",
  "algorithm": "sha256",
  "timestamp": "2025-08-15T06:00:00Z"
}
```

#### Check Service Health

```bash
# Check all services
curl https://localhost:8442/health --insecure
curl https://localhost:8443/health --insecure
curl https://localhost:8444/health --insecure
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVICE_NAME` | `opentelemetry-service` | Service name |
| `PORT` | `5000` | Service port |
| `SSL_ENABLED` | `true` | Enable HTTPS |
| `TPM2_DEVICE` | `/dev/tpm0` | TPM2 device path (for hardware TPM) |
| `SWTPM_DIR` | `$HOME/.swtpm/ztpm` | Software TPM directory |
| `SWTPM_PORT` | `2321` | Software TPM server port |
| `SWTPM_CTRL` | `2322` | Software TPM control port |
| `TPM2TOOLS_TCTI` | `swtpm:host=127.0.0.1,port=2321` | TPM2 tools TCTI string |
| `OTEL_ENDPOINT` | `http://localhost:4317` | OpenTelemetry endpoint |
| `LOG_LEVEL` | `INFO` | Logging level |
| `NONCE_LENGTH` | `32` | Nonce length in bytes |
| `SIGNATURE_ALGORITHM` | `sha256` | TPM2 signature algorithm |
| `GEOGRAPHIC_REGION` | `US` | Agent's geographic region |
| `GEOGRAPHIC_STATE` | `California` | Agent's geographic state |
| `GEOGRAPHIC_CITY` | `Santa Clara` | Agent's geographic city |
| `ALLOWED_REGIONS` | `["US"]` | List of allowed regions for collector |
| `ALLOWED_STATES` | `["California", "Texas", "New York"]` | List of allowed states for collector |
| `ALLOWED_CITIES` | `["Santa Clara", "San Francisco", "Austin", "New York"]` | List of allowed cities for collector |

### Configuration File

Create a `.env` file for environment-specific configuration:

```bash
# Service Configuration
SERVICE_NAME=opentelemetry-service
SERVICE_VERSION=1.0.0
DEBUG=false

# Server Configuration
HOST=0.0.0.0
PORT=5000

# SSL Configuration
SSL_ENABLED=true
SSL_CERT_PATH=/path/to/cert.pem
SSL_KEY_PATH=/path/to/key.pem

# TPM2 Configuration
TPM2_DEVICE=/dev/tpm0
TPM2_APP_CTX_PATH=app.ctx

# OpenTelemetry Configuration
OTEL_ENDPOINT=http://localhost:4317
OTEL_SERVICE_NAME=opentelemetry-service

# Security Configuration
NONCE_LENGTH=32
SIGNATURE_ALGORITHM=sha256

# Geographic Region Configuration
GEOGRAPHIC_REGION=US
GEOGRAPHIC_STATE=California
GEOGRAPHIC_CITY=Santa Clara

# Geographic Policy Configuration (for collector)
ALLOWED_REGIONS=["US"]
ALLOWED_STATES=["California", "Texas", "New York"]
ALLOWED_CITIES=["Santa Clara", "San Francisco", "Austin", "New York"]
```

## Security Considerations

### TPM2 Security

- All cryptographic operations use software TPM (swtpm)
- Private keys never leave the TPM2 environment
- Signatures are TPM-backed and tamper-resistant
- Nonce-based authentication prevents replay attacks

### Geographic Region Security

- Geographic region information is cryptographically signed with TPM2
- Geographic policy enforcement prevents data from unauthorized regions
- Geographic region is separate from metrics but both are signed together
- Configurable geographic policies for compliance and data residency
- Geographic verification happens after signature verification for security

### Network Security

- All communications use HTTPS/TLS
- Self-signed certificates for development (use proper CA for production)
- Rate limiting prevents abuse
- Request validation and sanitization

### Production Deployment

For production deployment, consider:

1. **Proper SSL Certificates**: Replace self-signed certificates with CA-signed certificates
2. **Database Storage**: Replace in-memory storage with persistent database
3. **Load Balancing**: Add load balancers for high availability
4. **Monitoring**: Add comprehensive monitoring and alerting
5. **Backup**: Implement regular backup of TPM2 contexts and certificates
6. **Access Control**: Implement proper authentication and authorization
7. **Geographic Compliance**: Configure geographic policies for data residency requirements
8. **Geographic Monitoring**: Monitor and alert on geographic policy violations

## Troubleshooting

### Common Issues

#### Software TPM (swtpm) Not Found

```bash
# Check if swtpm is installed
swtpm --version

# Check if swtpm is running
ps aux | grep swtpm

# Test swtpm access
TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321" tpm2_getcap properties-fixed

# Check persistent handles
TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321" tpm2 getcap handles-persistent

# Start swtpm with persistent keys if not running
python start_swtpm.py
```

#### SSL Certificate Issues

```bash
# Generate new certificates
python -c "
from utils.ssl_utils import SSLUtils
SSLUtils.generate_certificate_files('localhost', 'cert.pem', 'key.pem')
"
```

#### Service Connection Issues

```bash
# Check service ports
netstat -tlnp | grep :844

# Check service logs
tail -f logs/*.log

# Test service health
curl https://localhost:8442/health --insecure
```

#### Geographic Region Issues

```bash
# Check geographic region configuration
echo "Agent region: $GEOGRAPHIC_REGION"
echo "Agent state: $GEOGRAPHIC_STATE"
echo "Agent city: $GEOGRAPHIC_CITY"

# Check collector geographic policy
echo "Allowed regions: $ALLOWED_REGIONS"
echo "Allowed states: $ALLOWED_STATES"
echo "Allowed cities: $ALLOWED_CITIES"

# Test geographic region verification
curl -X POST https://localhost:8442/metrics/generate \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "system"}' \
  --insecure

# Check for geographic region errors in logs
grep -i "geographic" logs/*.log
```

### Logging

The system uses structured logging with JSON format. Log levels can be controlled via the `LOG_LEVEL` environment variable.

### Performance Tuning

- Adjust rate limiting parameters in the gateway
- Configure TPM2 timeout values
- Optimize OpenTelemetry batch processing
- Monitor memory usage and adjust accordingly

## Development

### Project Structure

```
├── agent/                 # OpenTelemetry Agent microservice
│   └── app.py            # Includes geographic region in metrics payload
├── collector/             # OpenTelemetry Collector microservice
│   └── app.py            # Includes geographic region verification
├── gateway/               # API Gateway microservice
│   └── app.py
├── utils/                 # Shared utilities
│   ├── __init__.py
│   ├── tpm2_utils.py      # TPM2 operations (uses shell scripts)
│   └── ssl_utils.py       # SSL/TLS utilities
├── config.py              # Configuration management (includes geographic settings)
├── start_services.py      # Service startup script
├── start_swtpm.py         # Software TPM startup script
├── sign_app_message.sh    # TPM2 signing script
├── verify_app_message_signature.sh # TPM2 verification script
├── test_client.py         # Test client
├── test_swtpm_setup.py    # Software TPM setup test
├── requirements.txt       # Python dependencies
├── Dockerfile             # Docker configuration
├── docker-compose.yml     # Docker Compose configuration
└── README.md              # This file
```

### Adding New Features

1. **New Metrics Types**: Extend `MetricsGenerator` class in `agent/app.py`
2. **Additional Security**: Enhance `SecurityManager` in `gateway/app.py`
3. **Custom Processors**: Add new processors in `collector/app.py`
4. **New Endpoints**: Add Flask routes to respective services
5. **Geographic Policies**: Modify geographic region policies in `config.py` and environment variables
6. **Custom Geographic Verification**: Extend geographic verification logic in `collector/app.py`

### Testing

```bash
# Run unit tests
python -m pytest tests/

# Run integration tests
python test_client.py

# Run load tests
python load_test.py
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:

1. Check the troubleshooting section
2. Review the logs for error messages
3. Open an issue on GitHub
4. Contact the development team

## Acknowledgments

- OpenTelemetry project for the telemetry framework
- TPM2 Software Stack for hardware security integration
- Flask framework for the web services
- Docker for containerization support
