## Mobile Location Verification Microservice

This standalone microservice implements the flow described in the Sovereign Unified Identity architecture for verifying mobile geolocation sensors via the CAMARA Device Location APIs.

### Features
- **Pure Mobile Focus**: Optimized for mobile sensors. Non-mobile sensors (e.g., GNSS) are rejected by the sidecar as they are handled directly by the WASM filter.
- **DB-LESS Verification Flow**: Prioritizes using `msisdn`, `latitude`, `longitude`, and `accuracy` directly from the request payload (extracted from SVID claims).
- **Future-Proof Hardware Location**: Captures and logs `sensor_imei` and `sensor_imsi` for integration with the [AegisSovereignAI hardware-location proposal](https://github.com/lfedgeai/AegisSovereignAI/blob/main/proposals/camara-hardware-location.md).
- **Fallback DB-BASED Flow**: Looks up a `sensor_id` in a local SQLite database to resolve parameters if they are missing from the request.
- **Enhanced Mapping**: Database includes `sensor_imei`, `sensor_imsi`, and `sensor_serial` for improved sensor-to-subscriber mapping.
- **CAMARA Integration**: Executes the standard CAMARA Device Location verification sequence with intelligent caching.
- **UNIX Domain Socket Support**: Designed for secure, local consumption by the Keylime Verifier.

### Quick Setup
Before starting the microservice make sure the Python dependencies are installed (Flask is required for the HTTP server and `requests` is used for the CAMARA APIs):

```bash
cd .      # repo root
python3 -m venv .venv                         # optional but recommended
source .venv/bin/activate
pip install -r mobile-sensor-microservice/requirements.txt
```

This installs both runtime dependencies (Flask, requests) and the `pytest` tooling used by the bundled unit tests. If you skip the install step you'll see errors such as `ModuleNotFoundError: No module named 'flask'`.

### Configuration
| Environment Variable | Description | Default |
|----------------------|-------------|---------|
| `MOBILE_SENSOR_DB` | Path to SQLite DB | `sensor_mapping.db` (created automatically) |
| `CAMARA_BASE_URL` | Base URL for Telefonica Open Gateway sandbox | `https://sandbox.opengateway.telefonica.com/apigateway` |
| `CAMARA_BASIC_AUTH` | `Basic` header value used for `/bc-authorize` and `/token` | **required** |
| `CAMARA_SCOPE` | Scope used in `/bc-authorize` | `dpv:FraudPreventionAndDetection#device-location-read` |
| `CAMARA_BYPASS` | Set to `true` to skip CAMARA API calls (for testing only) | `false` |
| `DEMO_MODE` | Set to `true` to suppress CAMARA_BYPASS log messages (useful for demos). Defaults to `true` when `CAMARA_BYPASS` is enabled. | `false` (or `true` if `CAMARA_BYPASS=true`) |
| `CAMARA_VERIFY_CACHE_TTL_SECONDS` | Cache TTL for `verify_location` API results. The actual CAMARA API is called at most once per TTL period; subsequent calls return the cached result. | `900` (15 minutes) |

### Obtaining CAMARA Credentials

To use the CAMARA API, you need valid credentials from Telefonica Open Gateway:

1. **Register for Telefonica Open Gateway Sandbox**:
   - Visit: https://opengateway.telefonica.com/
   - Sign up for sandbox access
   - Create an application to get `client_id` and `client_secret`

2. **Generate Basic Auth Header**:
   ```bash
   # Format: Base64(client_id:client_secret)
   echo -n "your_client_id:your_client_secret" | base64
   # Output: e.g., "eW91cl9jbGllbnRfaWQ6eW91cl9jbGllbnRfc2VjcmV0"

   # Set environment variable:
   export CAMARA_BASIC_AUTH="Basic eW91cl9jbGllbnRfaWQ6eW91cl9jbGllbnRfc2VjcmV0"
   ```

3. **Verify Credentials**:
   ```bash
   # Test the credentials:
   curl -X POST https://sandbox.opengateway.telefonica.com/apigateway/bc-authorize \
     -H "Authorization: $CAMARA_BASIC_AUTH" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "login_hint=tel:+34696810912&scope=dpv:FraudPreventionAndDetection#device-location-read"
   ```
   If credentials are valid, you'll get a 200 response with `auth_req_id`. If invalid, you'll get 401.

### Running
```bash
# With valid CAMARA credentials:
export CAMARA_BASIC_AUTH="Basic <your_base64_encoded_credentials>"
export CAMARA_VERIFY_CACHE_TTL_SECONDS=900  # Optional: 15 minutes (default)
python mobile-sensor-microservice/service.py --port 5000 --host 0.0.0.0

# For testing without CAMARA (bypass mode):
# DEMO_MODE defaults to true when CAMARA_BYPASS is enabled (bypass messages are suppressed)
export CAMARA_BYPASS=true
python mobile-sensor-microservice/service.py --port 5000 --host 0.0.0.0

# To show bypass messages even when CAMARA_BYPASS is enabled:
export CAMARA_BYPASS=true
export DEMO_MODE=false
python mobile-sensor-microservice/service.py --port 5000 --host 0.0.0.0
```

### CAMARA API Caching

The service implements intelligent caching for CAMARA `verify_location` API calls:

- **Default TTL**: 15 minutes (900 seconds), configurable via `CAMARA_VERIFY_CACHE_TTL_SECONDS`
- **Behavior**: The actual CAMARA API is called at most once per TTL period
- **Cache hits**: Subsequent calls within the TTL return the cached result without making API calls
- **Benefits**:
  - Reduces CAMARA API calls significantly
  - Improves response time for cached requests
  - Reduces API rate limiting issues
  - Lowers operational costs

### Kubernetes Deployment (Secrets)

To deploying securely in Kubernetes, mount the secret as a file and point `CAMARA_BASIC_AUTH_FILE` to it:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mobile-sensor
spec:
  template:
    spec:
      containers:
        - name: mobile-sensor
          image: mobile-sensor-microservice:latest
          env:
            # 1. Point the app to the mounted secret file
            - name: CAMARA_BASIC_AUTH_FILE
              value: "/etc/secrets/camara/basic-auth"
          volumeMounts:
            # 2. Mount the secret volume
            - name: camara-secret-vol
              mountPath: "/etc/secrets/camara"
              readOnly: true
      volumes:
        - name: camara-secret-vol
          secret:
            secretName: camara-api-credentials
            items:
              - key: basic-auth
                path: basic-auth
```

**Logging**: All cache operations are logged with clear tags:
- `[CACHE HIT]` - Using cached result (NO API CALL)
- `[CACHE MISS]` - No cache available (CALLING API)
- `[CACHE EXPIRED]` - Cache expired (CALLING API)
- `[API CALL]` - Making actual CAMARA API call
- `[API RESPONSE]` - Response received (with cache status)
- `[LOCATION VERIFY]` - Location verification initiated/completed

### Logging

The service provides comprehensive logging for all operations:

- **Startup**: Logs cache configuration (enabled/disabled, TTL)
- **Location Verification**: Every verification call is logged with `[LOCATION VERIFY]` tags
- **Cache Status**: Clear indication of cache hits, misses, and API calls
- **CAMARA Bypass**: Logs when bypass is enabled and verification is skipped

Example log entries:
```
CAMARA verify_location caching: ENABLED (TTL: 900 seconds = 15.0 minutes)
[LOCATION VERIFY] Initiating location verification for sensor_id=12d1:1433...
[CACHE MISS] No cached CAMARA verify_location result available (TTL: 900 seconds) - CALLING API
[API CALL] CAMARA verify_location API call...
[API RESPONSE] CAMARA verify_location API response... [CACHED for 900 seconds]
[LOCATION VERIFY] Location verification completed for sensor_id=12d1:1433: result=true
```

### Unit Tests
The unit test (`tests/test_service.py`) uses `unittest.mock` to stub out HTTP calls so it can run without contacting the live CAMARA sandbox.
Run the tests with:
```bash
python -m pytest mobile-sensor-microservice/tests
```

### CAMARA Credentials Setup

For information on setting up CAMARA credentials (including file-based storage to avoid hardcoded credentials), see:
- **[CAMARA_CREDENTIALS_SETUP.md](CAMARA_CREDENTIALS_SETUP.md)** - Complete guide for setting up credentials

### Testing Credential Loading

Test scripts are available to verify the credential loading logic:
```bash
cd mobile-sensor-microservice
./test_camara_credentials.sh          # Basic verification tests
./test_integration_scenarios.sh        # Integration tests
```

See **[TEST_RESULTS.md](TEST_RESULTS.md)** for detailed test results.
