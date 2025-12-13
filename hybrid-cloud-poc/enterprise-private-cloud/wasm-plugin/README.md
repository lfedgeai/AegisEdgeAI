# WASM Filter for Sensor Verification

This directory contains a WebAssembly (WASM) filter for Envoy that:
- Extracts sensor ID directly from SPIRE certificate Unified Identity extension
- Calls mobile location service to verify the sensor
- Adds `X-Sensor-ID` header to verified requests

## Building

### Prerequisites

1. **Rust**: Install from https://rustup.rs/
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source ~/.cargo/env
   ```

2. **wasm32-wasi target**:
   ```bash
   rustup target add wasm32-wasi
   ```

### Build

```bash
cd enterprise-private-cloud/wasm-plugin
bash build.sh
```

This will:
1. Compile the Rust code to WASM
2. Copy the WASM module to `/opt/envoy/plugins/sensor_verification_wasm.wasm`

## How It Works

1. **Certificate Extraction**: The filter gets the client certificate from the TLS connection
2. **Sensor Information Extraction**: Parses the X.509 certificate to find the Unified Identity extension (OID `1.3.6.1.4.1.99999.2`)
3. **JSON Parsing**: Extracts the JSON from the extension and parses `grc.geolocation` (sensor_id, sensor_type, sensor_imei, sensor_imsi)
4. **Sensor Type Handling**:
   - **GPS/GNSS sensors**: Trusted hardware, bypass mobile location service entirely (allow request directly)
   - **Mobile sensors**: Calls the mobile location service at `localhost:5000/verify` with sensor_id, sensor_imei, and sensor_imsi
     - Note: CAMARA API caching is handled by the mobile location service (15-minute TTL, configurable), not in the WASM filter
5. **Header Injection**: If verification succeeds, adds `X-Sensor-ID` header and forwards to backend

## Advantages Over Lua Filter

- **Direct Certificate Parsing**: Can parse X.509 extensions natively without external services
- **Better Performance**: WASM is more performant than Lua for complex operations
- **Type Safety**: Rust provides compile-time type checking
- **No External Dependencies**: Eliminates the need for the sensor-id-extractor service

