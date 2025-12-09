# Environment Variable Setup Guide

This guide explains how to populate `CAMARA_BASIC_AUTH` and other CAMARA-related environment variables in different scenarios.

## Table of Contents
1. [Obtaining CAMARA Credentials](#obtaining-camara-credentials)
2. [Local Development](#local-development)
3. [CI/CD Pipelines](#cicd-pipelines)
4. [Production Deployments](#production-deployments)
5. [Test Scripts](#test-scripts)
6. [Troubleshooting](#troubleshooting)

---

## Obtaining CAMARA Credentials

Before setting environment variables, you need to obtain valid CAMARA credentials:

1. **Register for Telefonica Open Gateway Sandbox**:
   - Visit: https://opengateway.telefonica.com/
   - Sign up for sandbox access
   - Create an application to get `client_id` and `client_secret`

2. **Generate Basic Auth Header**:
   ```bash
   # Format: Base64(client_id:client_secret)
   echo -n "your_client_id:your_client_secret" | base64
   # Output: e.g., "eW91cl9jbGllbnRfaWQ6eW91cl9jbGllbnRfc2VjcmV0"
   
   # Full value with "Basic " prefix:
   export CAMARA_BASIC_AUTH="Basic eW91cl9jbGllbnRfaWQ6eW91cl9jbGllbnRfc2VjcmV0"
   ```

3. **Verify Credentials**:
   ```bash
   curl -X POST https://sandbox.opengateway.telefonica.com/apigateway/bc-authorize \
     -H "Authorization: $CAMARA_BASIC_AUTH" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "login_hint=tel:+34696810912&scope=dpv:FraudPreventionAndDetection#device-location-read"
   ```

---

## Local Development

### Method 1: Export in Current Shell Session

```bash
# Set for current terminal session
export CAMARA_BASIC_AUTH="Basic <your_base64_encoded_credentials>"
export CAMARA_BYPASS="false"  # Optional: set to "true" to bypass CAMARA API

# Verify it's set
echo $CAMARA_BASIC_AUTH

# Run your script
./test_onprem.sh
```

**Pros**: Quick and simple  
**Cons**: Lost when terminal closes

---

### Method 2: Shell Profile (Persistent)

Add to your `~/.bashrc`, `~/.zshrc`, or `~/.profile`:

```bash
# Add to ~/.bashrc or ~/.zshrc
export CAMARA_BASIC_AUTH="Basic <your_base64_encoded_credentials>"
export CAMARA_BYPASS="false"
```

Then reload:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

**Pros**: Persistent across terminal sessions  
**Cons**: Visible in shell history, shared across all projects

---

### Method 3: `.env` File (Recommended for Local Development)

Create a `.env` file in the project root (add to `.gitignore`):

```bash
# .env (DO NOT COMMIT THIS FILE)
CAMARA_BASIC_AUTH="Basic <your_base64_encoded_credentials>"
CAMARA_BYPASS="false"
CAMARA_BASE_URL="https://sandbox.opengateway.telefonica.com/apigateway"
```

Load it before running scripts:

```bash
# Option A: Source the file
set -a  # automatically export all variables
source .env
set +a
./test_onprem.sh

# Option B: Use a helper script
cat .env | xargs export
./test_onprem.sh

# Option C: Use dotenv (if available)
# Install: pip install python-dotenv
# Then use: dotenv run ./test_onprem.sh
```

Create `.env.example` template (commit this):
```bash
# .env.example (COMMIT THIS FILE)
# Copy this file to .env and fill in your credentials
CAMARA_BASIC_AUTH="Basic <base64(client_id:client_secret)>"
CAMARA_BYPASS="false"
CAMARA_BASE_URL="https://sandbox.opengateway.telefonica.com/apigateway"
```

**Pros**: 
- ✅ Not committed to git
- ✅ Easy to manage
- ✅ Can have different values per environment

**Cons**: 
- ⚠️ Must remember to load it
- ⚠️ Could be accidentally committed

---

### Method 4: Using `direnv` (Advanced)

Install `direnv` and create `.envrc`:

```bash
# Install direnv
# Ubuntu/Debian: sudo apt install direnv
# macOS: brew install direnv

# Create .envrc
echo 'export CAMARA_BASIC_AUTH="Basic <your_credentials>"' > .envrc
echo 'export CAMARA_BYPASS="false"' >> .envrc

# Allow direnv (one-time setup)
direnv allow

# Now variables are automatically loaded when you cd into the directory
```

**Pros**: Automatic loading, secure  
**Cons**: Requires additional tool installation

---

## CI/CD Pipelines

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up environment
        env:
          CAMARA_BASIC_AUTH: ${{ secrets.CAMARA_BASIC_AUTH }}
          CAMARA_BYPASS: ${{ secrets.CAMARA_BYPASS }}
        run: |
          echo "CAMARA_BASIC_AUTH is set"
          ./test_onprem.sh
```

**Setup Secrets in GitHub**:
1. Go to repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `CAMARA_BASIC_AUTH`
4. Value: `Basic <your_base64_encoded_credentials>`
5. Click "Add secret"

---

### GitLab CI

```yaml
# .gitlab-ci.yml
test:
  script:
    - export CAMARA_BASIC_AUTH="${CAMARA_BASIC_AUTH}"
    - export CAMARA_BYPASS="${CAMARA_BYPASS:-false}"
    - ./test_onprem.sh
  variables:
    CAMARA_BYPASS: "false"
```

**Setup Variables in GitLab**:
1. Go to project → Settings → CI/CD → Variables
2. Click "Add variable"
3. Key: `CAMARA_BASIC_AUTH`
4. Value: `Basic <your_base64_encoded_credentials>`
5. Check "Mask variable" (recommended)
6. Click "Add variable"

---

### Jenkins

```groovy
// Jenkinsfile
pipeline {
    agent any
    environment {
        CAMARA_BASIC_AUTH = credentials('camara-basic-auth')
        CAMARA_BYPASS = 'false'
    }
    stages {
        stage('Test') {
            steps {
                sh './test_onprem.sh'
            }
        }
    }
}
```

**Setup Credentials in Jenkins**:
1. Go to Jenkins → Manage Jenkins → Credentials
2. Add new "Secret text" credential
3. ID: `camara-basic-auth`
4. Secret: `Basic <your_base64_encoded_credentials>`

---

## Production Deployments

### Method 1: Systemd Service File

```ini
# /etc/systemd/system/mobile-sensor-service.service
[Unit]
Description=Mobile Sensor Microservice
After=network.target

[Service]
Type=simple
User=mobile-sensor
WorkingDirectory=/opt/mobile-sensor-microservice
Environment="CAMARA_BASIC_AUTH=Basic <your_base64_encoded_credentials>"
Environment="CAMARA_BYPASS=false"
Environment="MOBILE_SENSOR_DB=/var/lib/mobile-sensor/sensor_mapping.db"
ExecStart=/usr/bin/python3 /opt/mobile-sensor-microservice/service.py
Restart=always

[Install]
WantedBy=multi-user.target
```

**Load credentials from file** (more secure):
```ini
[Service]
EnvironmentFile=/etc/mobile-sensor-service.env
```

Then create `/etc/mobile-sensor-service.env` (chmod 600):
```bash
CAMARA_BASIC_AUTH="Basic <your_base64_encoded_credentials>"
CAMARA_BYPASS="false"
```

---

### Method 2: Docker

#### Using Environment Variables

```bash
# Run with environment variable
docker run -e CAMARA_BASIC_AUTH="Basic <your_credentials>" \
           -e CAMARA_BYPASS="false" \
           mobile-sensor-service:latest
```

#### Using Environment File

```bash
# Create .env file
echo 'CAMARA_BASIC_AUTH="Basic <your_credentials>"' > .env
echo 'CAMARA_BYPASS="false"' >> .env

# Run with env file
docker run --env-file .env mobile-sensor-service:latest
```

#### Using Docker Secrets (Docker Swarm)

```bash
# Create secret
echo "Basic <your_credentials>" | docker secret create camara_basic_auth -

# Use in docker-compose.yml
version: '3.8'
services:
  mobile-sensor:
    image: mobile-sensor-service:latest
    secrets:
      - camara_basic_auth
    environment:
      CAMARA_BASIC_AUTH_FILE: /run/secrets/camara_basic_auth
```

---

### Method 3: Kubernetes

#### Using Secrets

```bash
# Create secret
kubectl create secret generic camara-credentials \
  --from-literal=camara-basic-auth="Basic <your_base64_encoded_credentials>"

# Or from file
kubectl create secret generic camara-credentials \
  --from-env-file=camara.env
```

**Deployment YAML**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mobile-sensor-service
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: mobile-sensor
        image: mobile-sensor-service:latest
        env:
        - name: CAMARA_BASIC_AUTH
          valueFrom:
            secretKeyRef:
              name: camara-credentials
              key: camara-basic-auth
        - name: CAMARA_BYPASS
          value: "false"
```

#### Using ConfigMap (for non-sensitive config)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: camara-config
data:
  CAMARA_BYPASS: "false"
  CAMARA_BASE_URL: "https://sandbox.opengateway.telefonica.com/apigateway"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mobile-sensor-service
spec:
  template:
    spec:
      containers:
      - name: mobile-sensor
        envFrom:
        - configMapRef:
            name: camara-config
        env:
        - name: CAMARA_BASIC_AUTH
          valueFrom:
            secretKeyRef:
              name: camara-credentials
              key: camara-basic-auth
```

---

### Method 4: Cloud Provider Secret Management

#### AWS (Secrets Manager)

```python
import boto3
import os

def get_camara_credentials():
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId='camara/credentials')
    secret = json.loads(response['SecretString'])
    return secret['basic_auth']

# Set environment variable
os.environ['CAMARA_BASIC_AUTH'] = get_camara_credentials()
```

#### Azure Key Vault

```python
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
client = SecretClient(vault_url="https://your-vault.vault.azure.net/", credential=credential)
os.environ['CAMARA_BASIC_AUTH'] = client.get_secret("camara-basic-auth").value
```

#### Google Cloud Secret Manager

```python
from google.cloud import secretmanager

client = secretmanager.SecretManagerServiceClient()
name = f"projects/{project_id}/secrets/camara-basic-auth/versions/latest"
response = client.access_secret_version(request={"name": name})
os.environ['CAMARA_BASIC_AUTH'] = response.payload.data.decode('UTF-8')
```

---

## Test Scripts

### Method 1: Export Before Running

```bash
# Set environment variables
export CAMARA_BASIC_AUTH="Basic <your_credentials>"
export CAMARA_BYPASS="false"

# Run test script
./test_onprem.sh
```

### Method 2: Inline with Script

```bash
# Run with inline environment variables
CAMARA_BASIC_AUTH="Basic <your_credentials>" \
CAMARA_BYPASS="false" \
./test_onprem.sh
```

### Method 3: Create Wrapper Script

```bash
#!/bin/bash
# run_tests.sh

# Load credentials from .env if it exists
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Check if credentials are set
if [ -z "${CAMARA_BASIC_AUTH:-}" ] && [ "${CAMARA_BYPASS:-true}" != "true" ]; then
    echo "ERROR: CAMARA_BASIC_AUTH is required when CAMARA_BYPASS=false"
    echo "Set it with: export CAMARA_BASIC_AUTH='Basic <base64_encoded>'"
    exit 1
fi

# Run the actual test script
./test_onprem.sh
```

### Method 4: Using `env` Command

```bash
# Create credentials file (chmod 600)
cat > /tmp/camara.env <<EOF
CAMARA_BASIC_AUTH="Basic <your_credentials>"
CAMARA_BYPASS="false"
EOF
chmod 600 /tmp/camara.env

# Run with env file
env $(cat /tmp/camara.env | xargs) ./test_onprem.sh
```

---

## Troubleshooting

### Check if Variable is Set

```bash
# Check if variable exists
if [ -z "${CAMARA_BASIC_AUTH:-}" ]; then
    echo "CAMARA_BASIC_AUTH is not set"
else
    echo "CAMARA_BASIC_AUTH is set (but not showing value for security)"
fi

# Print all CAMARA-related variables (for debugging)
env | grep CAMARA
```

### Verify Variable Format

```bash
# Check if it starts with "Basic "
if [[ "$CAMARA_BASIC_AUTH" =~ ^Basic\ .+ ]]; then
    echo "Format looks correct"
else
    echo "ERROR: CAMARA_BASIC_AUTH should start with 'Basic '"
fi
```

### Test Credentials

```bash
# Test if credentials work
curl -X POST https://sandbox.opengateway.telefonica.com/apigateway/bc-authorize \
  -H "Authorization: $CAMARA_BASIC_AUTH" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "login_hint=tel:+34696810912&scope=dpv:FraudPreventionAndDetection#device-location-read"

# Should return 200 with auth_req_id if valid
# Should return 401 if invalid
```

### Common Issues

1. **Variable not persisting**: Make sure to `export` it, not just set it
2. **Wrong format**: Must start with `"Basic "` prefix
3. **Base64 encoding**: Make sure credentials are properly base64 encoded
4. **Quotes**: Use quotes if value contains special characters
5. **Spaces**: Be careful with spaces in the value

---

## Security Best Practices

1. **Never commit credentials to git**
   - Add `.env` to `.gitignore`
   - Use `.env.example` as template
   - Use secret scanning tools

2. **Use secret management in production**
   - AWS Secrets Manager
   - HashiCorp Vault
   - Kubernetes Secrets
   - Cloud provider secret stores

3. **Rotate credentials regularly**
   - Set up rotation schedule
   - Update all environments when rotating
   - Document rotation process

4. **Limit access**
   - Use least privilege principle
   - Restrict who can access secrets
   - Audit secret access

5. **Use different credentials per environment**
   - Development
   - Staging
   - Production

---

## Quick Reference

```bash
# Generate credentials
echo -n "client_id:client_secret" | base64

# Set for current session
export CAMARA_BASIC_AUTH="Basic <base64_encoded>"

# Set for bypass mode (no credentials needed)
export CAMARA_BYPASS="true"

# Verify it's set
echo $CAMARA_BASIC_AUTH

# Run script
./test_onprem.sh
```

