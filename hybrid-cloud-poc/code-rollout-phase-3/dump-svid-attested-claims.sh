#!/bin/bash
# Unified-Identity - Phase 1 & Phase 2: Dump SVID Certificate with AttestedClaims
# Shows the AttestedClaims extension embedded in the SVID certificate

set -euo pipefail

SVID_FILE="${1:-/tmp/svid-dump/svid.pem}"

if [ ! -f "$SVID_FILE" ]; then
    echo "Error: SVID certificate not found at $SVID_FILE"
    echo "Usage: $0 [path-to-svid.pem]"
    exit 1
fi

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SVID Certificate with AttestedClaims Extension               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Certificate: $SVID_FILE"
echo ""

# Method 1: Using OpenSSL to show the extension
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Method 1: OpenSSL - Certificate Extensions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show basic certificate info
echo "Certificate Subject:"
openssl x509 -in "$SVID_FILE" -noout -subject 2>/dev/null || echo "  (could not read)"

echo ""
echo "Certificate SPIFFE ID:"
openssl x509 -in "$SVID_FILE" -noout -text 2>/dev/null | grep -oP 'URI:spiffe://[^\s,]+' | head -1 || echo "  (not found)"

echo ""
echo "AttestedClaims Extension (OID: 1.3.6.1.4.1.99999.1):"
if openssl x509 -in "$SVID_FILE" -text -noout 2>/dev/null | grep -q "1.3.6.1.4.1.99999.1"; then
    echo "  ✓ Extension found in certificate"
    echo ""
    openssl x509 -in "$SVID_FILE" -text -noout 2>/dev/null | grep -A 2 "1.3.6.1.4.1.99999.1" | head -5
else
    echo "  ✗ Extension NOT found in certificate"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Method 2: Python - Extract and Display AttestedClaims"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

python3 << PYEOF
from cryptography import x509
from cryptography.hazmat.backends import default_backend
import json
import sys

try:
    with open("$SVID_FILE", 'rb') as f:
        cert = x509.load_pem_x509_certificate(f.read(), default_backend())
    
    # Get SPIFFE ID
    try:
        san_ext = cert.extensions.get_extension_for_oid(x509.oid.ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
        spiffe_id = san_ext.value.get_values_for_type(x509.UniformResourceIdentifier)[0]
        print(f"SPIFFE ID: {spiffe_id}")
    except:
        print("SPIFFE ID: (not found)")
    
    print("")
    
    # Find AttestedClaims extension
    found = False
    for ext in cert.extensions:
        if ext.oid.dotted_string == "1.3.6.1.4.1.99999.1":
            found = True
            print("✓ AttestedClaims Extension Found!")
            print(f"  OID: {ext.oid.dotted_string}")
            print(f"  Critical: {ext.critical}")
            print("")
            
            # Extract JSON
            claims_json = ext.value.value if hasattr(ext.value, 'value') else ext.value
            claims = json.loads(claims_json)
            
            print("  AttestedClaims (from certificate extension):")
            print(json.dumps(claims, indent=4))
            break
    
    if not found:
        print("✗ AttestedClaims extension NOT found in certificate")
        print("")
        print("Available extensions:")
        for ext in cert.extensions:
            print(f"  - {ext.oid.dotted_string}")
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The AttestedClaims are embedded in the X.509 certificate extension"
echo "with OID 1.3.6.1.4.1.99999.1, implementing Model 3 from federated-jwt.md"

