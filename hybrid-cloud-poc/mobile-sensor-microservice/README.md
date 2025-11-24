## Mobile Location Verification Microservice

This standalone microservice implements the flow described in the Sovereign Unified Identity architecture for verifying mobile geolocation sensors via the CAMARA Device Location APIs.

### Features
- Looks up a `sensor_id` in a local SQLite database to resolve the associated MSISDN (phone number).
- Seeds the database with a default mapping `12d1:1433 → +34696810912` so deployments work out-of-the-box (you can add more rows later).
- Executes the CAMARA sequence:
  1. `POST /bc-authorize` to obtain `auth_req_id`.
  2. `POST /token` (grant type `urn:openid:params:grant-type:ciba`) to obtain an access token.
  3. `POST /location/v0/verify` to validate the reported coordinates/accuracy.
- Exposes a REST endpoint (`POST /verify`) that accepts only the sensor identifier:
  ```json
  {
    "sensor_id": "12d1:1433"
  }
  ```
  The microservice looks up the MSISDN and default latitude/longitude/accuracy from SQLite and returns `{"sensor_id": "...", "verification_result": true/false, "latitude": ..., "longitude": ..., "accuracy": ...}`.
- Designed to run over a UNIX Domain Socket (UDS) so that the Keylime Verifier can consume it securely.

### Quick Setup
Before starting the microservice make sure the Python dependencies are installed (Flask is required for the HTTP server and `requests` is used for the CAMARA APIs):

```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc      # repo root
python3 -m venv .venv                         # optional but recommended
source .venv/bin/activate
pip install -r mobile-sensor-microservice/requirements.txt
```

This installs both runtime dependencies (Flask, requests) and the `pytest` tooling used by the bundled unit tests. If you skip the install step you'll see errors such as `ModuleNotFoundError: No module named 'flask'`.

### Configuration
| Environment Variable | Description | Default |
|----------------------|-------------|---------|
| `MOBILE_SENSOR_DB` | Path to SQLite DB (`sensor_map(sensor_id TEXT PRIMARY KEY, msisdn TEXT, latitude REAL, longitude REAL, accuracy REAL)`) | `sensor_mapping.db` (created automatically) |
| `CAMARA_BASE_URL` | Base URL for Telefonica Open Gateway sandbox | `https://sandbox.opengateway.telefonica.com/apigateway` |
| `CAMARA_BASIC_AUTH` | `Basic` header value used for `/bc-authorize` and `/token` | **required** |
| `CAMARA_SCOPE` | Scope used in `/bc-authorize` | `dpv:FraudPreventionAndDetection#device-location-read` |

### Running
```bash
export CAMARA_BASIC_AUTH="Basic <client_id:secret base64>"
python mobile-sensor-microservice/service.py --socket /tmp/mobile-sensor.sock
# Then configure Keylime Verifier to call the microservice via that UDS path.
```

### Unit Tests
The unit test (`tests/test_service.py`) uses `unittest.mock` to stub out HTTP calls so it can run without contacting the live CAMARA sandbox.
Run the tests with:
```bash
python -m pytest mobile-sensor-microservice/tests
```

