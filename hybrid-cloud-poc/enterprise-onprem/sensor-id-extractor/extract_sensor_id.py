#!/usr/bin/env python3
"""
Helper service to extract sensor ID from SPIRE certificate.
Called by Envoy Lua filter or WASM plugin.
"""

import os
import sys
import json
import base64
from flask import Flask, request, jsonify
from cryptography import x509
from cryptography.hazmat.backends import default_backend

app = Flask(__name__)

# Unified Identity OID
UNIFIED_IDENTITY_OID = "1.3.6.1.4.1.99999.2"
LEGACY_OID = "1.3.6.1.4.1.99999.1"

def extract_sensor_id_from_cert_pem(cert_pem):
    """Extract sensor ID from SPIRE certificate PEM."""
    try:
        # Parse certificate
        cert = x509.load_pem_x509_certificate(cert_pem.encode('utf-8'), default_backend())
        
        # Extract Unified Identity extension
        unified_identity_ext = None
        for ext in cert.extensions:
            oid_str = ".".join(map(str, ext.oid._numbers))
            if oid_str == UNIFIED_IDENTITY_OID or oid_str == LEGACY_OID:
                unified_identity_ext = ext.value
                break
        
        if not unified_identity_ext:
            return None
        
        # Parse JSON from extension
        import json
        try:
            claims_data = json.loads(unified_identity_ext.decode('utf-8'))
        except:
            # Try ASN.1 decoding if JSON doesn't work
            claims_data = json.loads(unified_identity_ext)
        
        # Extract sensor ID from geolocation
        if "grc.geolocation" in claims_data:
            geo = claims_data["grc.geolocation"]
            if isinstance(geo, dict) and "sensor_id" in geo:
                return geo["sensor_id"]
        
        return None
    except Exception as e:
        print(f"Error extracting sensor ID: {e}", file=sys.stderr)
        return None

def extract_sensor_id_from_cert_der(cert_der_bytes):
    """Extract sensor ID from SPIRE certificate DER bytes."""
    try:
        # Parse certificate from DER
        cert = x509.load_der_x509_certificate(cert_der_bytes, default_backend())
        
        # Extract Unified Identity extension
        unified_identity_ext = None
        for ext in cert.extensions:
            oid_str = ".".join(map(str, ext.oid._numbers))
            if oid_str == UNIFIED_IDENTITY_OID or oid_str == LEGACY_OID:
                unified_identity_ext = ext.value
                break
        
        if not unified_identity_ext:
            return None
        
        # Parse JSON from extension
        try:
            claims_data = json.loads(unified_identity_ext.decode('utf-8'))
        except:
            # Try ASN.1 decoding if JSON doesn't work
            claims_data = json.loads(unified_identity_ext)
        
        # Extract sensor ID from geolocation
        if "grc.geolocation" in claims_data:
            geo = claims_data["grc.geolocation"]
            if isinstance(geo, dict) and "sensor_id" in geo:
                return geo["sensor_id"]
        
        return None
    except Exception as e:
        print(f"Error extracting sensor ID: {e}", file=sys.stderr)
        return None

@app.route('/extract', methods=['POST'])
def extract_sensor_id():
    """Extract sensor ID from certificate provided in request."""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON body required"}), 400
        
        # Support both PEM and DER (base64) formats
        if 'cert_pem' in data:
            cert_pem = data['cert_pem']
            sensor_id = extract_sensor_id_from_cert_pem(cert_pem)
        elif 'cert_der_b64' in data:
            import base64
            cert_der = base64.b64decode(data['cert_der_b64'])
            sensor_id = extract_sensor_id_from_cert_der(cert_der)
        else:
            return jsonify({"error": "cert_pem or cert_der_b64 required"}), 400
        
        if sensor_id:
            return jsonify({"sensor_id": sensor_id}), 200
        else:
            return jsonify({"error": "sensor_id not found in certificate"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5001))
    app.run(host='0.0.0.0', port=port, debug=False)

