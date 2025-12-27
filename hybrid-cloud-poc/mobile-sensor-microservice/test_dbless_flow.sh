#!/bin/bash
# test_dbless_flow.sh

# Start the service in the background if it's not running
# For this test, we assume the service is running or we'll just test the logic with a curl command

echo "[+] Testing DB-LESS flow with full location data in SVID claims payload"
curl -s -X POST http://localhost:9050/verify -d '{
    "sensor_id": "test-mobile-01",
    "sensor_type": "mobile",
    "msisdn": "+34696810912",
    "latitude": 40.33,
    "longitude": -3.7707,
    "accuracy": 7.0
}'

echo -e "\n\n[+] Testing DB-BASED flow (default sensor)"
curl -s -X POST http://localhost:9050/verify -d '{
    "sensor_id": "12d1:1433"
}'

echo -e "\n\n[+] Testing GNSS rejection (should fail in Pure Mobile sidecar if it ever reaches it)"
curl -s -X POST http://localhost:9050/verify -d '{
    "sensor_id": "GNSS-USB-01",
    "sensor_type": "gnss"
}'
