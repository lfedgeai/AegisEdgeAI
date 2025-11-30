use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use std::sync::{Arc, Mutex};

// Unified Identity extension OIDs (as ASN.1 OID bytes)
// 1.3.6.1.4.1.99999.2 = 0x2b, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37, 0x63, 0x02
// 1.3.6.1.4.1.99999.1 = 0x2b, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37, 0x63, 0x01
const UNIFIED_IDENTITY_OID_STR: &str = "1.3.6.1.4.1.99999.2";
const LEGACY_OID_STR: &str = "1.3.6.1.4.1.99999.1";

#[derive(Serialize, Deserialize)]
struct VerifyRequest {
    sensor_id: String,
}

#[derive(Deserialize)]
struct VerifyResponse {
    verification_result: Option<bool>,
    error: Option<String>,
    #[serde(flatten)]
    extra: serde_json::Map<String, serde_json::Value>,
}

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
        Box::new(SensorVerificationRoot::default())
    });
}}

// Shared cache state (persists across requests)
struct CacheState {
    verification_cache: Option<(String, std::time::SystemTime)>, // (sensor_id, timestamp when cached)
    verification_result: Option<bool>, // Cached verification result
}

struct SensorVerificationRoot {
    cache: Arc<Mutex<CacheState>>,
}

impl Default for SensorVerificationRoot {
    fn default() -> Self {
        Self {
            cache: Arc::new(Mutex::new(CacheState {
                verification_cache: None,
                verification_result: None,
            })),
        }
    }
}

impl Context for SensorVerificationRoot {}

impl RootContext for SensorVerificationRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(SensorVerificationFilter {
            sensor_id: None,
            cache: Arc::clone(&self.cache),
        }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct SensorVerificationFilter {
    sensor_id: Option<String>,
    cache: Arc<Mutex<CacheState>>, // Shared cache from root context
}

impl Context for SensorVerificationFilter {
    // Handle HTTP call response from mobile location service
    fn on_http_call_response(&mut self, _token_id: u32, num_headers: usize, body_size: usize, _num_trailers: usize) {
        // Get HTTP status code
        let status_code = self.get_http_call_response_header(":status")
            .and_then(|s| s.parse::<u16>().ok())
            .unwrap_or(0);
        
        // Get response body
        let body_result = self.get_http_call_response_body(0, body_size);
        let body = match body_result {
            Some(b) => b,
            None => {
                proxy_wasm::hostcalls::log(LogLevel::Warn, "Failed to get HTTP call response body");
                self.send_http_response(
                    503,
                    vec![("content-type", "text/plain")],
                    Some(b"Verification service response error"),
                );
                return;
            }
        };
        let body_str = String::from_utf8_lossy(&body);
        
        proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Mobile location service response: status={}, body={}", status_code, body_str));
        
        // Check if status code indicates error
        if status_code >= 400 {
            let error_msg = if let Ok(json) = serde_json::from_str::<serde_json::Value>(&body_str) {
                json.get("error")
                    .and_then(|e| e.as_str())
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| "unknown error".to_string())
            } else {
                "http error".to_string()
            };
            proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Mobile location service error (status {}): {}", status_code, error_msg));
            // On service error, reject request (fail closed for security)
            self.send_http_response(
                503,
                vec![("content-type", "text/plain")],
                Some(b"Verification service error"),
            );
            return;
        }
        
        // Parse response (expecting 200 OK with verification_result)
        match serde_json::from_str::<VerifyResponse>(&body_str) {
            Ok(response) => {
                let sensor_id = self.sensor_id.clone().unwrap_or_default();
                
                // Check if response has an error field
                if let Some(error) = &response.error {
                    proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Mobile location service returned error: {} for sensor_id: {}", error, sensor_id));
                    self.send_http_response(
                        503,
                        vec![("content-type", "text/plain")],
                        Some(b"Verification service error"),
                    );
                    return;
                }
                
                // Get verification result
                let verified = response.verification_result.unwrap_or(false);
                
                proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Verification result for sensor_id {}: {}", sensor_id, verified));
                
                // Update cache with verification result and current timestamp
                let current_time = self.get_current_time();
                if let Ok(mut cache) = self.cache.lock() {
                    cache.verification_cache = Some((sensor_id.clone(), current_time));
                    cache.verification_result = Some(verified);
                }
                
                if verified {
                    // Verification successful - resume request
                    proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Sensor verification successful for sensor_id: {} - resuming request", sensor_id));
                    self.resume_http_request();
                } else {
                    // Verification failed - reject request
                    proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Sensor verification failed for sensor_id: {} - rejecting request", sensor_id));
                    self.send_http_response(
                        403,
                        vec![("content-type", "text/plain")],
                        Some(b"Sensor verification failed"),
                    );
                }
            }
            Err(e) => {
                proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Failed to parse verification response: {:?}, body: {}", e, body_str));
                // On parse error, reject request
                self.send_http_response(
                    503,
                    vec![("content-type", "text/plain")],
                    Some(b"Verification service response invalid"),
                );
            }
        }
    }
}

impl HttpContext for SensorVerificationFilter {
    fn on_http_request_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        // Get certificate chain from x-forwarded-client-cert header (set by forward_client_cert_details in Envoy)
        // Format: "By=...;Cert=\"...\";Chain=\"...\";Subject=...;URI=..."
        // The Unified Identity extension is in the intermediate certificate (agent SVID) in the Chain
        let cert_pem: Option<Vec<u8>> = self.get_http_request_header("x-forwarded-client-cert")
            .and_then(|header| {
                // Try to get Chain first (contains full chain: leaf + intermediate)
                // If Chain is not available, fall back to Cert (leaf only)
                let chain_str = if let Some(chain_start) = header.find("Chain=") {
                    let chain_part = &header[chain_start + 6..];
                    // Remove quotes if present
                    let chain_part = if chain_part.starts_with('"') {
                        &chain_part[1..]
                    } else {
                        chain_part
                    };
                    let chain_end = chain_part.find(';').unwrap_or(chain_part.len());
                    let chain_str = &chain_part[..chain_end];
                    // Remove trailing quote if present
                    Some(chain_str.trim_end_matches('"'))
                } else {
                    // Fall back to Cert (leaf certificate)
                    header.find("Cert=").map(|cert_start| {
                        let cert_part = &header[cert_start + 5..];
                        let cert_part = if cert_part.starts_with('"') {
                            &cert_part[1..]
                        } else {
                            cert_part
                        };
                        let cert_end = cert_part.find(';').unwrap_or(cert_part.len());
                        let cert_str = &cert_part[..cert_end];
                        cert_str.trim_end_matches('"')
                    })
                };
                
                chain_str.map(|cert_str| {
                    // URL-decode the certificate (Envoy URL-encodes it: %20=space, %0A=newline, etc.)
                    let url_decoded = cert_str
                        .replace("%20", " ")
                        .replace("%0A", "\n")
                        .replace("%0D", "\r")
                        .replace("%2F", "/")
                        .replace("%2B", "+")
                        .replace("%3D", "=")
                        .replace("%22", "\"")
                        .replace("%3B", ";")
                        .replace("%3A", ":");
                    
                    url_decoded.as_bytes().to_vec()
                })
            });

        let cert_pem = match cert_pem {
            Some(cert) => cert,
            None => {
                proxy_wasm::hostcalls::log(LogLevel::Warn, "Failed to get peer certificate from header or property paths");
                self.send_http_response(
                    403,
                    vec![("content-type", "text/plain")],
                    Some(b"Client certificate required"),
                );
                return Action::Pause;
            }
        };

        // Extract sensor ID from certificate
        let sensor_id = match extract_sensor_id_from_cert(&cert_pem) {
            Some(id) => id,
            None => {
                self.send_http_response(
                    403,
                    vec![("content-type", "text/plain")],
                    Some(b"Invalid certificate: no sensor ID"),
                );
                return Action::Pause;
            }
        };

        // Store sensor_id for use in verification
        self.sensor_id = Some(sensor_id.clone());
        
        // Check verification cache (15 second TTL to avoid expensive CAMARA API calls)
        let cache_ttl = Duration::from_secs(15);
        let current_time = self.get_current_time();
        
        // Access shared cache from root context
        let (should_verify, cached_verified) = {
            let cache_guard = match self.cache.lock() {
                Ok(guard) => guard,
                Err(_) => {
                    proxy_wasm::hostcalls::log(LogLevel::Warn, "Failed to lock cache, will verify");
                    return Action::Pause;
                }
            };
            
            let should_verify = match &cache_guard.verification_cache {
                Some((cached_sensor_id, cached_timestamp)) => {
                    if cached_sensor_id == &sensor_id {
                        // Calculate cache age
                        let cache_age = current_time.duration_since(*cached_timestamp)
                            .unwrap_or(Duration::from_secs(0));
                        let cache_age_seconds = cache_age.as_secs();
                        
                        if cache_age < cache_ttl {
                            proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Using cached verification for sensor_id: {} (age: {}s, TTL: 15s)", sensor_id, cache_age_seconds));
                            false // Use cached result
                        } else {
                            proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Cache expired for sensor_id: {} (age: {}s, TTL: 15s), re-verifying", sensor_id, cache_age_seconds));
                            true // Cache expired, need to verify
                        }
                    } else {
                        proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Different sensor_id: {} (cached: {}), verifying", sensor_id, cached_sensor_id));
                        true // Different sensor_id, need to verify
                    }
                }
                None => {
                    proxy_wasm::hostcalls::log(LogLevel::Info, &format!("No cache for sensor_id: {}, verifying", sensor_id));
                    true // No cache, need to verify
                }
            };
            
            let cached_verified = cache_guard.verification_result;
            (should_verify, cached_verified)
        };
        
        if should_verify {
            // Call mobile location service to verify sensor (blocking - request paused until response)
            let verify_body = serde_json::to_string(&VerifyRequest {
                sensor_id: sensor_id.clone(),
            }).unwrap_or_default();
            
            let headers = vec![
                (":method", "POST"),
                (":path", "/verify"),
                (":authority", "localhost:5000"),
                ("content-type", "application/json"),
            ];
            
            // Dispatch HTTP call for verification (blocking - pause request until response)
            match self.dispatch_http_call(
                "mobile_location_service",
                headers,
                Some(verify_body.as_bytes()),
                vec![],
                Duration::from_secs(5),
            ) {
                Ok(_) => {
                    proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Dispatched blocking verification request for sensor_id: {} (request paused, waiting for response)", sensor_id));
                    // Pause request processing until verification response is received
                    Action::Pause
                }
                Err(e) => {
                    proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Failed to call mobile location service for sensor_id {}: {:?} - rejecting request", sensor_id, e));
                    // On dispatch error, reject request
                    self.send_http_response(
                        503,
                        vec![("content-type", "text/plain")],
                        Some(b"Verification service unavailable"),
                    );
                    Action::Pause
                }
            }
        } else {
            // Use cached verification result - allow request
            if let Some(verified) = cached_verified {
                if verified {
                    proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Extracted sensor_id: {} (using cached verification result: verified)", sensor_id));
                    Action::Continue
                } else {
                    proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Extracted sensor_id: {} (using cached verification result: rejected)", sensor_id));
                    self.send_http_response(
                        403,
                        vec![("content-type", "text/plain")],
                        Some(b"Sensor verification failed (cached)"),
                    );
                    Action::Pause
                }
            } else {
                // Cache exists but no result stored - should not happen, but allow request
                proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Extracted sensor_id: {} (cache exists but no result - allowing request)", sensor_id));
                Action::Continue
            }
        }
    }
}

fn extract_sensor_id_from_cert(cert_pem: &[u8]) -> Option<String> {
    // Parse certificate chain (may contain multiple certificates: leaf + intermediates)
    // The Unified Identity extension is in the intermediate certificate (agent SVID)
    let pem_str = std::str::from_utf8(cert_pem).ok()?;
    
    // Split PEM into individual certificates
    let mut cert_blocks = Vec::new();
    let parts: Vec<&str> = pem_str.split("-----BEGIN CERTIFICATE-----").collect();
    for part in parts {
        if !part.trim().is_empty() {
            cert_blocks.push(format!("-----BEGIN CERTIFICATE-----{}", part));
        }
    }
    
    // Try each certificate in the chain (leaf first, then intermediates)
    for cert_block in cert_blocks {
        // Extract base64 content from PEM
        let lines: Vec<&str> = cert_block
            .lines()
            .filter(|l| !l.starts_with("-----"))
            .collect();
        let cert_bytes = match base64::decode(&lines.join("")) {
            Ok(bytes) => bytes,
            Err(_) => continue,
        };

        // Parse X.509 certificate
        let (_, cert) = match x509_parser::parse_x509_certificate(&cert_bytes) {
            Ok(parsed) => parsed,
            Err(_) => continue,
        };

        // Find Unified Identity extension in this certificate
        for ext in cert.extensions() {
            let oid_str = format!("{}", ext.oid);
            
            if oid_str == UNIFIED_IDENTITY_OID_STR || oid_str == LEGACY_OID_STR {
                // Parse extension value as JSON
                let ext_value = &ext.value;
                if let Ok(json_str) = std::str::from_utf8(ext_value) {
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(json_str) {
                        if let Some(geo) = json.get("grc.geolocation") {
                            if let Some(sensor_id) = geo.get("sensor_id") {
                                if let Some(id_str) = sensor_id.as_str() {
                                    return Some(id_str.to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    None
}

