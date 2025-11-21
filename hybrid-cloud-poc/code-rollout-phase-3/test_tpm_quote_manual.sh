#!/usr/bin/env bash
# Manual TPM quote test to diagnose hardware TPM issues
set -euo pipefail

echo "=== Manual TPM Quote Test ==="
echo ""

# Check TPM accessibility
echo "1. Testing TPM accessibility..."
if [ ! -c /dev/tpmrm0 ] && [ ! -c /dev/tpm0 ]; then
    echo "   ✗ No TPM device found"
    exit 1
fi

TPM_DEVICE="/dev/tpmrm0"
if [ ! -c "$TPM_DEVICE" ]; then
    TPM_DEVICE="/dev/tpm0"
fi
echo "   ✓ Using TPM device: $TPM_DEVICE"
export TCTI="device:${TPM_DEVICE}"

# Check tpm2-abrmd
echo ""
echo "2. Checking tpm2-abrmd..."
if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
    echo "   ⚠ tpm2-abrmd not running, starting it..."
    tpm2-abrmd --tcti=device 2>/dev/null &
    sleep 2
fi
if pgrep -x tpm2-abrmd >/dev/null 2>&1; then
    echo "   ✓ tpm2-abrmd is running"
else
    echo "   ⚠ tpm2-abrmd may not be running properly"
fi

# Test basic TPM operations
echo ""
echo "3. Testing basic TPM operations..."
echo "   Getting random bytes..."
if TCTI="$TCTI" tpm2_getrandom 16 >/dev/null 2>&1; then
    echo "   ✓ TPM getrandom works"
else
    echo "   ✗ TPM getrandom failed"
    exit 1
fi

# Check persistent handles
echo ""
echo "4. Checking persistent handles..."
HANDLES=$(TCTI="$TCTI" tpm2_getcap handles-persistent 2>&1)
echo "$HANDLES"
HANDLE_COUNT=$(echo "$HANDLES" | grep -E "^0x[0-9a-fA-F]+" | wc -l)
echo "   Found $HANDLE_COUNT persistent handles"

if [ "$HANDLE_COUNT" -eq 0 ]; then
    echo "   ⚠ No persistent handles found - agent may need to create AK first"
    echo "   This is expected if the agent hasn't been fully initialized"
fi

# Try to read one of the handles to see if they're valid
echo ""
echo "5. Testing handle accessibility..."
if [ "$HANDLE_COUNT" -gt 0 ]; then
    FIRST_HANDLE=$(echo "$HANDLES" | grep "^0x" | head -1)
    echo "   Testing handle: $FIRST_HANDLE"
    if TCTI="$TCTI" tpm2_readpublic -c "$FIRST_HANDLE" >/dev/null 2>&1; then
        echo "   ✓ Handle $FIRST_HANDLE is accessible"
    else
        echo "   ⚠ Handle $FIRST_HANDLE may be invalid or require authorization"
    fi
fi

# Check TPM error logs
echo ""
echo "6. Checking for TPM errors in system logs..."
if command -v dmesg >/dev/null 2>&1; then
    TPM_ERRORS=$(dmesg | grep -i "tpm\|0x14a" | tail -10)
    if [ -n "$TPM_ERRORS" ]; then
        echo "   TPM-related messages in dmesg:"
        echo "$TPM_ERRORS" | sed 's/^/     /'
    else
        echo "   ✓ No TPM errors in dmesg"
    fi
fi

# Test quote operation if we have a valid handle
echo ""
echo "7. Testing quote operation..."
if [ "$HANDLE_COUNT" -gt 0 ]; then
    FIRST_HANDLE=$(echo "$HANDLES" | grep "^0x" | head -1)
    NONCE=$(TCTI="$TCTI" tpm2_getrandom 16 2>&1 | head -1 | awk '{print $2}')
    echo "   Using handle: $FIRST_HANDLE"
    echo "   Nonce: $NONCE"
    echo "   Attempting quote (this may hang if TPM is stuck)..."
    
    timeout 10 TCTI="$TCTI" tpm2_quote \
        -c "$FIRST_HANDLE" \
        -l sha256:0,1,2,3,4,5,6,7 \
        -q "$NONCE" \
        -m /tmp/quote.msg \
        -s /tmp/quote.sig \
        -g sha256 2>&1 &
    QUOTE_PID=$!
    
    sleep 2
    if ps -p $QUOTE_PID >/dev/null 2>&1; then
        echo "   ⚠ Quote operation is still running (may hang)..."
        sleep 3
        if ps -p $QUOTE_PID >/dev/null 2>&1; then
            echo "   ✗ Quote operation hung - killing it"
            kill $QUOTE_PID 2>/dev/null || true
            wait $QUOTE_PID 2>/dev/null || true
            echo "   This confirms the TPM quote operation is hanging"
        else
            echo "   ✓ Quote operation completed"
            if [ -f /tmp/quote.msg ] && [ -f /tmp/quote.sig ]; then
                echo "   ✓ Quote files created successfully"
                rm -f /tmp/quote.msg /tmp/quote.sig
            fi
        fi
    else
        wait $QUOTE_PID
        QUOTE_EXIT=$?
        if [ $QUOTE_EXIT -eq 0 ]; then
            echo "   ✓ Quote operation succeeded"
        else
            echo "   ✗ Quote operation failed with exit code: $QUOTE_EXIT"
        fi
    fi
else
    echo "   ⚠ Skipping quote test - no persistent handles available"
    echo "   The agent needs to create an AK (Attestation Key) first"
fi

echo ""
echo "=== Summary ==="
echo "If the manual quote operation also hangs, the issue is with the TPM hardware."
echo "If it works, the issue may be in how the agent is calling the TPM."
echo ""
echo "Next steps:"
echo "1. If quote hangs: Check TPM hardware, try TPM reset/clear"
echo "2. If quote works: Investigate agent's TPM quote implementation"
echo "3. Consider testing with swtpm (software TPM) to isolate hardware issues"

