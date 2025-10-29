#!/bin/sh
i=0
while true; do
  i=$((i+1))
  
  # This curl command sends the JSON payload with the incrementing ID
  curl -s -o /dev/null -w "Request $i: %{http_code}\n" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"id\":$i}" \
    http://frontend-svc:8080
    
  sleep 0.05
done
