#!/bin/bash
# Diagnose verification service errors
# Usage: ./diagnose-verification-errors.sh

echo "=========================================="
echo "Diagnosing Verification Service Errors"
echo "=========================================="
echo ""

# Check if mobile location service is running
echo "1. Checking if mobile location service is running..."
if ss -tlnp 2>/dev/null | grep -q ':5000' || netstat -tlnp 2>/dev/null | grep -q ':5000'; then
    echo "   ✓ Mobile location service is listening on port 5000"
    PID=$(ss -tlnp 2>/dev/null | grep ':5000' | grep -oP 'pid=\K[0-9]+' | head -1 || \
          netstat -tlnp 2>/dev/null | grep ':5000' | awk '{print $7}' | cut -d'/' -f1 | head -1)
    if [ -n "$PID" ]; then
        echo "   PID: $PID"
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "   ✓ Process is running"
        else
            echo "   ✗ Process not found (port may be stale)"
        fi
    fi
else
    echo "   ✗ Mobile location service is NOT listening on port 5000"
    echo "   → Restart it: cd ~/AegisSovereignAI/hybrid-cloud-poc/mobile-sensor-microservice"
    echo "                 source .venv/bin/activate"
    echo "                 export CAMARA_BYPASS=true"
    echo "                 python3 service.py --port 5000 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &"
fi

echo ""
echo "2. Recent mobile location service logs (last 20 lines):"
if [ -f /tmp/mobile-sensor.log ]; then
    tail -20 /tmp/mobile-sensor.log | sed 's/^/   /'
else
    echo "   ✗ Log file not found: /tmp/mobile-sensor.log"
fi

echo ""
echo "3. Recent Envoy WASM filter logs (verification-related, last 30 lines):"
if [ -f /opt/envoy/logs/envoy.log ]; then
    sudo tail -100 /opt/envoy/logs/envoy.log | grep -E "(sensor|verification|Mobile location service|Verification service)" | tail -30 | sed 's/^/   /'
else
    echo "   ✗ Log file not found: /opt/envoy/logs/envoy.log"
fi

echo ""
echo "4. Testing mobile location service directly:"
if command -v curl >/dev/null 2>&1; then
    echo "   Testing /verify endpoint..."
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST http://localhost:5000/verify \
        -H "Content-Type: application/json" \
        -d '{"sensor_id": "12d1:1433"}' 2>&1)
    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | grep -v "HTTP_STATUS:")
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "   ✓ Service responded with HTTP 200"
        echo "   Response: $BODY"
    else
        echo "   ✗ Service returned HTTP $HTTP_STATUS"
        echo "   Response: $BODY"
    fi
else
    echo "   ⚠ curl not available, skipping direct test"
fi

echo ""
echo "5. Recent errors in mobile location service:"
if [ -f /tmp/mobile-sensor.log ]; then
    grep -i "error\|exception\|traceback\|failed" /tmp/mobile-sensor.log | tail -10 | sed 's/^/   /'
else
    echo "   (no log file)"
fi

echo ""
echo "=========================================="
echo "Diagnosis complete"
echo "=========================================="

