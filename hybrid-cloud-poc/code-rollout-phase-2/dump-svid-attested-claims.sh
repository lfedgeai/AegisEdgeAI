#!/bin/bash
# Unified-Identity - Phase 3: Dump SVID Certificate and certificate chain
# Shows the AttestedClaims extension embedded in the workload SVID and
# highlights the agent SVID that is now included in the chain for policy enforcement

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

# Method 1: Certificate chain summary (Python)
export DUMP_SVID_FILE="$SVID_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Method 1: Certificate Chain Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
python3 <<'PYEOF'
import json
import re
import sys
import os
from datetime import timezone
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.x509.oid import ExtensionOID

path = Path(os.environ["DUMP_SVID_FILE"])
try:
    pem_data = path.read_bytes()
except Exception as exc:
    print(f"Error reading {path}: {exc}")
    sys.exit(1)

blocks = re.findall(
    b"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
    pem_data,
    re.DOTALL,
)
if not blocks:
    print("✗ No PEM certificates found in file")
    sys.exit(1)

certs = []
for block in blocks:
    block_bytes = block if block.endswith(b"\n") else block + b"\n"
    certs.append(x509.load_pem_x509_certificate(block_bytes, default_backend()))

print(f"Found {len(certs)} certificate(s) in chain.")
print("")

def extract_spiffe_id(cert):
    try:
        san = cert.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
    except x509.ExtensionNotFound:
        return None
    for uri in san.value.get_values_for_type(x509.UniformResourceIdentifier):
        if uri.startswith("spiffe://"):
            return uri
    return None

def classify_cert(index, cert, spiffe_id):
    if index == 0:
        return "Workload SVID (leaf)"
    if spiffe_id and "/spire/agent/" in spiffe_id:
        return "Agent SVID (policy enforcement)"
    if spiffe_id:
        return "SPIFFE Identity"
    if cert.is_ca:
        return "CA Certificate"
    return "Certificate"

attested_claims = None
attested_extension = None

for idx, cert in enumerate(certs):
    spiffe_id = extract_spiffe_id(cert)
    role = classify_cert(idx, cert, spiffe_id)
    print(f"[{idx}] {role}")
    print(f"     Subject: {cert.subject.rfc4514_string()}")
    if spiffe_id:
        print(f"     SPIFFE ID: {spiffe_id}")
    else:
        print("     SPIFFE ID: (none)")
    print(f"     Issuer: {cert.issuer.rfc4514_string()}")
    try:
        expires = cert.not_valid_after_utc
    except AttributeError:
        expires = cert.not_valid_after
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
    print(f"     Expires: {expires.isoformat()}")

    for ext in cert.extensions:
        if ext.oid.dotted_string == "1.3.6.1.4.1.99999.1":
            attested_extension = ext
            try:
                data = ext.value.value if hasattr(ext.value, "value") else ext.value
                attested_claims = json.loads(data)
                print("     ✓ AttestedClaims extension present")
            except Exception as exc:
                print(f"     ⚠ Failed to decode AttestedClaims: {exc}")
            break
    print("")

if attested_extension:
    print("AttestedClaims Extension details (from workload SVID):")
    print(f"  OID: {attested_extension.oid.dotted_string}")
    print(f"  Critical: {attested_extension.critical}")
else:
    print("✗ AttestedClaims extension not found in any certificate")

print("")
if attested_claims:
    print("AttestedClaims payload:")
    print(json.dumps(attested_claims, indent=4))
else:
    print("AttestedClaims payload not available.")
PYEOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Method 2: OpenSSL - Workload Certificate (leaf)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show basic workload certificate info
echo "Workload Certificate Subject:"
openssl x509 -in "$SVID_FILE" -noout -subject 2>/dev/null || echo "  (could not read)"

echo ""
echo "Workload Certificate SPIFFE ID:"
openssl x509 -in "$SVID_FILE" -noout -text 2>/dev/null | grep -oP 'URI:spiffe://[^\s,]+' | head -1 || echo "  (not found)"

echo ""
echo "AttestedClaims Extension (OID: 1.3.6.1.4.1.99999.1):"
if openssl x509 -in "$SVID_FILE" -text -noout 2>/dev/null | grep -q "1.3.6.1.4.1.99999.1"; then
    echo "  ✓ Extension found in workload certificate"
    echo ""
    openssl x509 -in "$SVID_FILE" -text -noout 2>/dev/null | grep -A 2 "1.3.6.1.4.1.99999.1" | head -5
else
    echo "  ✗ Extension NOT found in workload certificate"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The workload SVID now ships with the agent SVID in the certificate chain."
echo "Use the chain summary above to verify which agent issued the workload SVID."

