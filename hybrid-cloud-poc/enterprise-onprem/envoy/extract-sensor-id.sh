#!/bin/bash
# Helper script to extract sensor ID from SPIRE certificate DER
# Used by Envoy Lua filter when direct extraction is needed

CERT_DER_B64="$1"

if [ -z "$CERT_DER_B64" ]; then
    echo '{"error":"cert_der_b64 required"}' >&2
    exit 1
fi

# Decode base64 and extract Unified Identity extension
# OID: 1.3.6.1.4.1.99999.2 or 1.3.6.1.4.1.99999.1
echo "$CERT_DER_B64" | base64 -d | openssl asn1parse -inform DER 2>/dev/null | \
    grep -A 20 "1.3.6.1.4.1.99999" | \
    grep -oP 'HEXDUMP:\K[0-9a-fA-F]+' | \
    xxd -r -p | \
    python3 -c "
import sys
import json
try:
    data = sys.stdin.buffer.read()
    # Try to parse as JSON
    claims = json.loads(data.decode('utf-8', errors='ignore'))
    if 'grc.geolocation' in claims:
        geo = claims['grc.geolocation']
        if isinstance(geo, dict) and 'sensor_id' in geo:
            print(json.dumps({'sensor_id': geo['sensor_id']}))
            sys.exit(0)
except:
    pass
print(json.dumps({'error': 'sensor_id not found'}))
sys.exit(1)
" 2>/dev/null || echo '{"error":"failed to extract sensor_id"}'

