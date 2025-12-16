#!/bin/bash
# Fix verifier config - ensure enabled_revocation_notifications is properly formatted

CONFIG_FILE="keylime/verifier.conf.minimal"

echo "Fixing verifier config: ${CONFIG_FILE}"
echo ""

# Check if file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

# Show current value
echo "Current value:"
grep -A 1 "enabled_revocation_notifications" "${CONFIG_FILE}" || echo "  (not found)"
echo ""

# Backup the file
cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup.$(date +%s)"
echo "Backup created: ${CONFIG_FILE}.backup.*"
echo ""

# Fix the line - ensure it's exactly "enabled_revocation_notifications = []"
# Use sed to replace any variation with the correct format
sed -i 's/^enabled_revocation_notifications.*$/enabled_revocation_notifications = []/' "${CONFIG_FILE}"

echo "Fixed value:"
grep -A 1 "enabled_revocation_notifications" "${CONFIG_FILE}"
echo ""

# Verify the fix with Python
echo "Verifying with Python ast.literal_eval..."
python3 << 'EOF'
import configparser
import ast

config = configparser.ConfigParser()
config.read('keylime/verifier.conf.minimal')

try:
    value = config.get('revocations', 'enabled_revocation_notifications').strip('" ')
    print(f"  Raw value: '{value}'")
    
    if value:
        parsed = ast.literal_eval(value)
        print(f"  Parsed value: {parsed}")
        print(f"  Type: {type(parsed)}")
        if isinstance(parsed, list):
            print("  ✓ Valid list format!")
        else:
            print("  ✗ Not a list!")
    else:
        print("  ✗ Empty value - this will cause an error!")
except Exception as e:
    print(f"  ✗ Error: {e}")
EOF

echo ""
echo "Fix complete. Try starting the verifier again:"
echo "  ./test_complete_control_plane.sh --no-pause"
