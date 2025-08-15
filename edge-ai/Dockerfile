# Multi-stage Dockerfile for OpenTelemetry Microservice Architecture
FROM python:3.11-slim as base

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg2 \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Install TPM2 tools and swtpm
RUN apt-get update && apt-get install -y \
    tpm2-tools \
    swtpm \
    swtpm-tools \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p /app/certs /app/logs

# Set permissions
RUN chmod +x start_services.py test_client.py start_swtpm.py tpm-ek-ak-persist.sh tpm-app-persist.sh

# Expose ports
EXPOSE 8442 8443 8444

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f https://localhost:8442/health || exit 1

# Default command
CMD ["python", "start_services.py"]
