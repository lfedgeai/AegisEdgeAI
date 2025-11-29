-- Envoy Lua filter to extract sensor ID from SPIRE cert and verify with mobile location service
-- This runs in Envoy's Lua runtime

function envoy_on_request(request_handle)
  -- Get client certificate from TLS connection
  local cert = request_handle:connection():ssl():peerCertificate()
  
  if not cert then
    request_handle:logErr("No client certificate found")
    request_handle:respond({[":status"] = "403", ["body"] = "Client certificate required"}, "")
    return
  end
  
  -- Extract sensor ID from certificate
  -- SPIRE certs have sensor ID in Unified Identity extension (OID 1.3.6.1.4.1.99999.2)
  -- For now, we'll extract from SPIFFE ID or use a helper service
  -- Since Lua can't easily parse X.509 extensions, we'll use a helper approach:
  -- 1. Extract SPIFFE ID from cert SAN
  -- 2. Call a helper service to extract sensor ID from cert
  
  local spiffe_id = cert:getSubjectAlternativeNames()
  if not spiffe_id or #spiffe_id == 0 then
    request_handle:logErr("No SPIFFE ID found in certificate")
    request_handle:respond({[":status"] = "403", ["body"] = "Invalid certificate: no SPIFFE ID"}, "")
    return
  end
  
  -- For now, extract sensor ID from a helper service
  -- We'll create a simple Python service that extracts sensor ID from cert
  local sensor_id = extract_sensor_id_from_cert(cert, request_handle)
  
  if not sensor_id then
    request_handle:logErr("Could not extract sensor ID from certificate")
    request_handle:respond({[":status"] = "403", ["body"] = "Invalid certificate: no sensor ID"}, "")
    return
  end
  
  -- Call mobile location service
  local mobile_service_url = "http://localhost:5000/verify"
  local body = '{"sensor_id":"' .. sensor_id .. '"}'
  
  local headers = {
    [":method"] = "POST",
    [":path"] = "/verify",
    [":authority"] = "localhost:5000",
    ["content-type"] = "application/json",
    ["content-length"] = tostring(#body)
  }
  
  local response = request_handle:httpCall(
    "mobile_location_service",
    headers,
    body,
    5000  -- timeout in ms
  )
  
  if response:status() ~= 200 then
    request_handle:logErr("Mobile location service returned status: " .. response:status())
    request_handle:respond({[":status"] = "403", ["body"] = "Sensor verification failed"}, "")
    return
  end
  
  local response_body = response:body()
  local verification_result = false
  
  -- Parse JSON response (simple parsing)
  if string.find(response_body, '"verification_result":true') or 
     string.find(response_body, '"verification_result": true') then
    verification_result = true
  end
  
  if not verification_result then
    request_handle:logErr("Sensor verification failed for sensor_id: " .. sensor_id)
    request_handle:respond({[":status"] = "403", ["body"] = "Sensor verification failed"}, "")
    return
  end
  
  -- Add sensor ID to request header for backend
  request_handle:headers():add("X-Sensor-ID", sensor_id)
  request_handle:logInfo("Sensor verified successfully: " .. sensor_id)
end

function extract_sensor_id_from_cert(cert, request_handle)
  -- Lua can't easily parse X.509 extensions, so we'll use a helper service
  -- For now, return nil - we'll implement this via a helper HTTP service
  return nil
end

