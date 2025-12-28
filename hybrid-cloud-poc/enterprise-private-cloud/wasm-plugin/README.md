# WASM Filter for Sensor Verification

This directory contains a WebAssembly (WASM) filter for Envoy that:
- Extracts sensor information from SPIRE certificate Unified Identity extension
- Applies policy-based verification modes (trust/runtime/strict)
- Calls mobile location sidecar for CAMARA verification when needed
- Adds sensor headers to verified requests

## Building

### Prerequisites

1. **Rust**: Install from https://rustup.rs/
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source ~/.cargo/env
   ```

2. **wasm32-wasip1 target**:
   ```bash
   rustup target add wasm32-wasip1
   ```

### Build

```bash
cd enterprise-private-cloud/wasm-plugin
bash build.sh
```

## Configuration

The filter accepts JSON configuration via Envoy WASM config:

```yaml
configuration:
  "@type": "type.googleapis.com/google.protobuf.StringValue"
  value: |
    {
      "verification_mode": "runtime",
      "sidecar_endpoint": "http://localhost:9050"
    }
```

### Verification Modes

| Mode | Sidecar Call | Cache | Use Case |
|------|--------------|-------|----------|
| **trust** | ❌ None | N/A | Low-security workloads, trust attestation-time verification |
| **runtime** (default) | ✅ Yes | ✅ 15min TTL | Standard workloads, balanced security & performance |
| **strict** | ✅ Yes | ❌ Real-time | Critical infrastructure, banking, military |

## How It Works

1. **Certificate Extraction**: Gets client certificate from TLS connection
2. **Sensor Info Extraction**: Parses X.509 Unified Identity extension (OID `1.3.6.1.4.1.99999.2`)
3. **Claim Parsing**: Extracts sensor metadata from nested `grc.geolocation` structure:
   - **Mobile**: `grc.geolocation.mobile` → `sensor_id`, `sensor_imei`, `sim_imsi`, `sim_msisdn`, and `location_verification` (lat/lon/acc)
   - **GNSS**: `grc.geolocation.gnss` → `sensor_id`, `sensor_serial_number`, and `retrieved_location` (lat/lon/acc)
   - **Legacy Fallback**: Also supports flattened `grc.geolocation` for backward compatibility.
4. **Policy Application**:
   - **GNSS sensors**: Trusted hardware, allow directly (no sidecar call)
   - **Mobile sensors**: Apply verification_mode policy
     - Trust: Allow without sidecar call
     - Runtime: Call sidecar with caching (DB-less if coordinates present in SVID)
     - Strict: Call sidecar with `skip_cache=true` (DB-less if coordinates present in SVID)
5. **Header Injection**: Adds `X-Sensor-Type`, `X-Sensor-ID`, `X-Mobile-MSISDN` headers

## Sidecar Request Format

When calling sidecar (runtime/strict modes):

```json
POST /verify
{
  "sensor_id": "12d1:1433",
  "sensor_imei": "356345043865103",
  "sim_imsi": "214070610960475",
  "sim_msisdn": "tel:+34696810912",
  "latitude": 0,
  "longitude": 0,
  "accuracy": 0,
  "skip_cache": true
}
```

- `msisdn`, `latitude`, `longitude`, `accuracy`: Extracted from SVID claims (enables DB-less flow)
- `skip_cache`: Set to `true` in strict mode
