// Copyright 2025 AegisSovereignAI Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde::{Deserialize, Serialize};
use std::time::Duration;

// Unified Identity extension OIDs (as ASN.1 OID bytes)
// 1.3.6.1.4.1.55744.1.1 = 0x2b, 0x06, 0x01, 0x04, 0x01, 0x83, 0xb3, 0x40, 0x01, 0x01
const UNIFIED_IDENTITY_OID_STR: &str = "1.3.6.1.4.1.55744.1.1";
const LEGACY_OID_STR: &str = "1.3.6.1.4.1.55744.1.1";

#[derive(Serialize, Deserialize)]
struct VerifyRequest {
    sensor_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    sensor_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    sensor_imei: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    sensor_imsi: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    sensor_serial_number: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    msisdn: Option<String>,        // Task 8: MSISDN from SVID (no DB lookup needed)
    #[serde(skip_serializing_if = "Option::is_none")]
    skip_cache: Option<bool>,      // Task 7: true for Strict mode
    #[serde(skip_serializing_if = "Option::is_none")]
    latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    longitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    accuracy: Option<f64>,
}

#[derive(Deserialize)]
struct VerifyResponse {
    verification_result: Option<bool>,
    error: Option<String>,
    #[serde(flatten)]
    extra: serde_json::Map<String, serde_json::Value>,
}

// Policy-based verification modes (Task 7)
#[derive(Clone, Copy, Debug, PartialEq)]
enum VerificationMode {
    Trust,    // No sidecar call (default) - trust attestation-time verification
    Runtime,  // Sidecar call with caching (15min TTL)
    Strict,   // Sidecar call without caching (real-time)
}

impl Default for VerificationMode {
    fn default() -> Self {
        VerificationMode::Trust
    }
}

// Plugin configuration parsed from Envoy WASM config
#[derive(Clone)]
struct PluginConfig {
    verification_mode: VerificationMode,
    sidecar_endpoint: String,
}

// Metric IDs for Envoy stats (Task 18: Observability)
#[derive(Clone, Default)]
struct MetricIds {
    request_total: u32,
    verification_success: u32,
    verification_failure: u32,
    sidecar_call_total: u32,
    sidecar_latency_ms: u32,
}

impl Default for PluginConfig {
    fn default() -> Self {
        PluginConfig {
            verification_mode: VerificationMode::Runtime, // Default to runtime (cached CAMARA verification)
            sidecar_endpoint: "http://localhost:9050".to_string(),
        }
    }
}

impl PluginConfig {
    fn from_json(json_str: &str) -> Self {
        let mut config = PluginConfig::default();

        if let Ok(json) = serde_json::from_str::<serde_json::Value>(json_str) {
            // Parse verification_mode
            if let Some(mode_str) = json.get("verification_mode").and_then(|v| v.as_str()) {
                config.verification_mode = match mode_str.to_lowercase().as_str() {
                    "trust" => VerificationMode::Trust,
                    "runtime" => VerificationMode::Runtime,
                    "strict" => VerificationMode::Strict,
                    _ => {
                        proxy_wasm::hostcalls::log(LogLevel::Warn, &format!(
                            "Unknown verification_mode '{}', defaulting to 'trust'", mode_str
                        ));
                        VerificationMode::Trust
                    }
                };
            }

            // Parse sidecar_endpoint
            if let Some(endpoint) = json.get("sidecar_endpoint").and_then(|v| v.as_str()) {
                config.sidecar_endpoint = endpoint.to_string();
            }
        }

        config
    }
}

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
        Box::new(SensorVerificationRoot {
            config: PluginConfig::default(),
            metrics: MetricIds::default(),
        })
    });
}}

struct SensorVerificationRoot {
    config: PluginConfig,
    metrics: MetricIds,
}

impl Context for SensorVerificationRoot {}

impl RootContext for SensorVerificationRoot {
    fn on_configure(&mut self, _plugin_configuration_size: usize) -> bool {
        // Parse configuration from Envoy
        if let Some(config_bytes) = self.get_plugin_configuration() {
            if let Ok(config_str) = String::from_utf8(config_bytes) {
                self.config = PluginConfig::from_json(&config_str);
                let mode_str = match self.config.verification_mode {
                    VerificationMode::Trust => "trust",
                    VerificationMode::Runtime => "runtime",
                    VerificationMode::Strict => "strict",
                };
                proxy_wasm::hostcalls::log(LogLevel::Info, &format!(
                    "WASM filter configured: verification_mode={}, sidecar_endpoint={}",
                    mode_str, self.config.sidecar_endpoint
                ));
            }
        } else {
            proxy_wasm::hostcalls::log(LogLevel::Info, "WASM filter using default config: verification_mode=runtime");
        }

        // Define metrics (Task 18: Observability)
        self.metrics.request_total = proxy_wasm::hostcalls::define_metric(
            MetricType::Counter,
            "wasm_filter_request_total"
        ).unwrap_or(0);
        self.metrics.verification_success = proxy_wasm::hostcalls::define_metric(
            MetricType::Counter,
            "wasm_filter_verification_success_total"
        ).unwrap_or(0);
        self.metrics.verification_failure = proxy_wasm::hostcalls::define_metric(
            MetricType::Counter,
            "wasm_filter_verification_failure_total"
        ).unwrap_or(0);
        self.metrics.sidecar_call_total = proxy_wasm::hostcalls::define_metric(
            MetricType::Counter,
            "wasm_filter_sidecar_call_total"
        ).unwrap_or(0);
        self.metrics.sidecar_latency_ms = proxy_wasm::hostcalls::define_metric(
            MetricType::Histogram,
            "wasm_filter_sidecar_latency_ms"
        ).unwrap_or(0);
        proxy_wasm::hostcalls::log(LogLevel::Info, &format!(
            "WASM metrics defined: request_total={}, success={}, failure={}, sidecar_call={}, latency={}",
            self.metrics.request_total, self.metrics.verification_success, self.metrics.verification_failure,
            self.metrics.sidecar_call_total, self.metrics.sidecar_latency_ms
        ));

        true
    }

    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(SensorVerificationFilter {
            config: self.config.clone(),
            metrics: self.metrics.clone(),
            sensor_id: None,
            sensor_type: None,
            sensor_imei: None,
            sensor_imsi: None,
            sensor_serial_number: None,
            sensor_msisdn: None,
            sensor_latitude: None,
            sensor_longitude: None,
            sensor_accuracy: None,
            sidecar_call_start_ms: None,
        }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct SensorVerificationFilter {
    config: PluginConfig,
    metrics: MetricIds,
    sensor_id: Option<String>,
    sensor_type: Option<String>, // "mobile" or "gnss"
    sensor_imei: Option<String>,
    sensor_imsi: Option<String>,
    sensor_serial_number: Option<String>,
    sensor_msisdn: Option<String>, // Task 8: MSISDN from SVID
    sensor_latitude: Option<f64>,
    sensor_longitude: Option<f64>,
    sensor_accuracy: Option<f64>,
    sidecar_call_start_ms: Option<u64>,
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
        
        // Record latency (Task 18: Observability)
        if let Some(start_time) = self.sidecar_call_start_ms {
            let now = self.get_current_time().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
            let latency = now.saturating_sub(start_time);
            let _ = proxy_wasm::hostcalls::record_metric(self.metrics.sidecar_latency_ms, latency);
            proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Recorded sidecar latency: {}ms", latency));
        }

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
                let sensor_imei = self.sensor_imei.as_ref().map(|s| s.as_str()).unwrap_or("none");
                let sensor_imsi = self.sensor_imsi.as_ref().map(|s| s.as_str()).unwrap_or("none");

                // Check if response has an error field
                if let Some(error) = &response.error {
                    proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Mobile location service returned error: {} for sensor_id: {}, sensor_imei: {}, sensor_imsi: {}", error, sensor_id, sensor_imei, sensor_imsi));
                    self.send_http_response(
                        503,
                        vec![("content-type", "text/plain")],
                        Some(b"Verification service error"),
                    );
                    return;
                }

                // Get verification result
                let verified = response.verification_result.unwrap_or(false);

                proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Verification result for sensor_id: {}, sensor_imei: {}, sensor_imsi: {} - result: {}", sensor_id, sensor_imei, sensor_imsi, verified));

                if verified {
                    // Verification successful - resume request
                    proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Sensor verification successful for sensor_id: {} - resuming request", sensor_id));
                    let _ = proxy_wasm::hostcalls::increment_metric(self.metrics.verification_success, 1);
                    self.resume_http_request();
                } else {
                    // Verification failed - reject request
                    proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Sensor verification failed for sensor_id: {} - rejecting request", sensor_id));
                    let _ = proxy_wasm::hostcalls::increment_metric(self.metrics.verification_failure, 1);
                    self.send_http_response(
                        403,
                        vec![("content-type", "text/plain")],
                        Some(b"Geo Claim Missing"),
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
        // Increment request total (Task 18: Observability)
        let _ = proxy_wasm::hostcalls::increment_metric(self.metrics.request_total, 1);
        proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Incremented request_total (ID: {})", self.metrics.request_total));

        // Get certificate chain from x-forwarded-client-cert header (set by forward_client_cert_details in Envoy)
        // Format: "By=...;Cert=\"...\";Chain=\"...\";Subject=...;URI=..."
        // The Unified Identity extension is in the agent SVID (second certificate in chain)
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

        // Unified-Identity: Extract sensor_id, sensor_imei, and sensor_imsi from certificate
        let sensor_info = match extract_sensor_info_from_cert(&cert_pem) {
            Some(info) => info,
            None => {
                proxy_wasm::hostcalls::log(LogLevel::Warn, "=== SENSOR INFORMATION MISSING ===\n  sensor_id: MISSING\n  sensor_imei: MISSING\n  sensor_imsi: MISSING\n========================================\nGeo Claim Missing: No sensor information found in certificate Unified Identity extension (sensor may be unplugged)");
                self.send_http_response(
                    403,
                    vec![("content-type", "text/plain")],
                    Some(b"Geo Claim Missing"),
                );
                return Action::Pause;
            }
        };

        // Store sensor information for use in verification
        self.sensor_id = Some(sensor_info.sensor_id.clone());
        self.sensor_type = sensor_info.sensor_type.clone();
        self.sensor_imei = sensor_info.sensor_imei.clone();
        self.sensor_imsi = sensor_info.sensor_imsi.clone();
        self.sensor_msisdn = sensor_info.sensor_msisdn.clone(); // Task 8: Store MSISDN from SVID
        self.sensor_latitude = sensor_info.latitude;
        self.sensor_longitude = sensor_info.longitude;
        self.sensor_accuracy = sensor_info.accuracy;

        let sensor_id = sensor_info.sensor_id;
        let sensor_type_str = self.sensor_type.as_ref().map(|s| s.as_str()).unwrap_or("unknown");
        let imei_str = self.sensor_imei.as_ref().map(|s| s.as_str()).unwrap_or("(not present)");
        let imsi_str = self.sensor_imsi.as_ref().map(|s| s.as_str()).unwrap_or("(not present)");
        let msisdn_str = self.sensor_msisdn.as_ref().map(|s| s.as_str()).unwrap_or("(not present)");

        // Log sensor information with type
        if sensor_type_str == "mobile" {
            proxy_wasm::hostcalls::log(LogLevel::Info, &format!(
                "Sensor information stored for verification: type={}, sensor_id={}, sensor_imei={}, sensor_imsi={}, sensor_msisdn={}, lat={:?}, lon={:?}, acc={:?}",
                sensor_type_str, sensor_id, imei_str, imsi_str, msisdn_str,
                self.sensor_latitude, self.sensor_longitude, self.sensor_accuracy
            ));
        } else {
            proxy_wasm::hostcalls::log(LogLevel::Info, &format!(
                "Sensor information stored for verification: type={}, sensor_id={}",
                sensor_type_str, sensor_id
            ));
        }

        // Unified-Identity: Apply policy-based verification modes (Task 7)
        // GPS/GNSS sensors are always trusted hardware - allow directly
        // Mobile sensors: apply verification_mode policy
        // Unified-Identity: Apply policy-based verification modes (Task 7 & 12b)
        // All sensor types (mobile/gnss) now route through the Sidecar Adapter Backends
        let mode_str = match self.config.verification_mode {
            VerificationMode::Trust => "trust",
            VerificationMode::Runtime => "runtime",
            VerificationMode::Strict => "strict",
        };

        if sensor_type_str == "mobile" {
            let mode_str = match self.config.verification_mode {
                VerificationMode::Trust => "trust",
                VerificationMode::Runtime => "runtime",
                VerificationMode::Strict => "strict",
            };

            match self.config.verification_mode {
                VerificationMode::Trust => {
                    // Trust mode: No sidecar call - trust attestation-time verification
                    proxy_wasm::hostcalls::log(LogLevel::Info, &format!(
                        "Mobile sensor (sensor_id={}): verification_mode=trust - allowing without sidecar call",
                        sensor_id
                    ));
                    Action::Continue
                }
                VerificationMode::Runtime | VerificationMode::Strict => {
                    // Runtime/Strict mode: Call sidecar for CAMARA verification
                    let skip_cache = self.config.verification_mode == VerificationMode::Strict;

                    let verify_body = serde_json::to_string(&VerifyRequest {
                        sensor_id: sensor_id.clone(),
                        sensor_type: self.sensor_type.clone(),
                        sensor_imei: self.sensor_imei.clone(),
                        sensor_imsi: self.sensor_imsi.clone(),
                        sensor_serial_number: self.sensor_serial_number.clone(),
                        msisdn: self.sensor_msisdn.clone(),
                        skip_cache: if skip_cache { Some(true) } else { None },
                        // Pass location details if available (enables DB-less sidecar flow)
                        latitude: self.sensor_latitude,
                        longitude: self.sensor_longitude,
                        accuracy: self.sensor_accuracy,
                    }).unwrap_or_default();

                    let headers = vec![
                        (":method", "POST"),
                        (":path", "/verify"),
                        (":authority", "localhost:9050"),
                        ("content-type", "application/json"),
                    ];

                    match self.dispatch_http_call(
                        "mobile_location_service",
                        headers,
                        Some(verify_body.as_bytes()),
                        vec![],
                        Duration::from_secs(5),
                    ) {
                        Ok(_) => {
                            // Record start time and increment sidecar call count (Task 18: Observability)
                            self.sidecar_call_start_ms = Some(self.get_current_time().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64);
                            let _ = proxy_wasm::hostcalls::increment_metric(self.metrics.sidecar_call_total, 1);

                            proxy_wasm::hostcalls::log(LogLevel::Info, &format!(
                                "Mobile sensor (sensor_id={}): verification_mode={}, skip_cache={} - dispatched sidecar call",
                                sensor_id, mode_str, skip_cache
                            ));
                            Action::Pause
                        }
                        Err(e) => {
                            proxy_wasm::hostcalls::log(LogLevel::Warn, &format!(
                                "Failed to call sidecar for sensor_id {}: {:?} - rejecting request", sensor_id, e
                            ));
                            self.send_http_response(
                                503,
                                vec![("content-type", "text/plain")],
                                Some(b"Verification service unavailable"),
                            );
                            Action::Pause
                        }
                    }
                }
            }
        } else {
            // Task 12b: GNSS sensors are always trusted hardware - no sidecar call needed (Pure Mobile Sidecar)
            proxy_wasm::hostcalls::log(LogLevel::Info, &format!(
                "{} sensor (sensor_id={}): Trusted hardware - allowing directly",
                sensor_type_str, sensor_id
            ));
            Action::Continue
        }
    }
}

// Unified-Identity: Sensor information extracted from certificate
struct SensorInfo {
    sensor_id: String,
    sensor_type: Option<String>,
    sensor_imei: Option<String>,
    sensor_imsi: Option<String>,
    sensor_serial_number: Option<String>,
    sensor_msisdn: Option<String>,
    latitude: Option<f64>,
    longitude: Option<f64>,
    accuracy: Option<f64>,
}

fn extract_sensor_info_from_cert(cert_pem: &[u8]) -> Option<SensorInfo> {
    // Parse certificate chain (may contain multiple certificates: leaf + agent SVID)
    // The Unified Identity extension is in the agent SVID (second certificate in chain)
    let pem_str = match std::str::from_utf8(cert_pem) {
        Ok(s) => s,
        Err(e) => {
            proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Failed to parse certificate PEM as UTF-8: {:?}", e));
            return None;
        }
    };

    // Split PEM into individual certificates
    let mut cert_blocks = Vec::new();
    let parts: Vec<&str> = pem_str.split("-----BEGIN CERTIFICATE-----").collect();
    for part in parts {
        if !part.trim().is_empty() {
            cert_blocks.push(format!("-----BEGIN CERTIFICATE-----{}", part));
        }
    }

    proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Parsed certificate chain: found {} certificate(s)", cert_blocks.len()));

    // Try each certificate in the chain (leaf first, then intermediates)
    for (cert_idx, cert_block) in cert_blocks.iter().enumerate() {
        // Extract base64 content from PEM
        let lines: Vec<&str> = cert_block
            .lines()
            .filter(|l| !l.starts_with("-----"))
            .collect();
        let cert_bytes = match base64::decode(&lines.join("")) {
            Ok(bytes) => bytes,
            Err(e) => {
                proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Certificate {}: Failed to decode base64: {:?}", cert_idx, e));
                continue;
            }
        };

        // Parse X.509 certificate
        let (_, cert) = match x509_parser::parse_x509_certificate(&cert_bytes) {
            Ok(parsed) => parsed,
            Err(e) => {
                proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Certificate {}: Failed to parse X.509: {:?}", cert_idx, e));
                continue;
            }
        };

        proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Certificate {}: Examining {} extension(s)", cert_idx, cert.extensions().len()));

        // Find Unified Identity extension in this certificate
        for (ext_idx, ext) in cert.extensions().iter().enumerate() {
            let oid_str = format!("{}", ext.oid);

            proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Certificate {}: Extension {}: OID = {}", cert_idx, ext_idx, oid_str));

            if oid_str == UNIFIED_IDENTITY_OID_STR || oid_str == LEGACY_OID_STR {
                proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Certificate {}: Found Unified Identity extension (OID: {})", cert_idx, oid_str));

                // Parse extension value as JSON
                let ext_value = &ext.value;
                match std::str::from_utf8(ext_value) {
                    Ok(json_str) => {
                        proxy_wasm::hostcalls::log(LogLevel::Debug, &format!("Certificate {}: Extension value (first 500 chars): {}", cert_idx, json_str.chars().take(500).collect::<String>()));

                        match serde_json::from_str::<serde_json::Value>(json_str) {
                            Ok(json) => {
                                // 3. Parse Nested grc.geolocation (Refined Schema)
                                if let Some(geo) = json.get("grc.geolocation") {
                                    proxy_wasm::hostcalls::log(LogLevel::Info, &format!("Certificate {}: Found grc.geolocation claim", cert_idx));

                                    // Check for "mobile" nested object
                                    if let Some(mobile) = geo.get("mobile") {
                                        return Some(SensorInfo {
                                            sensor_id: mobile.get("sensor_id").and_then(|v| v.as_str()).unwrap_or("unknown").to_string(),
                                            sensor_type: Some("mobile".to_string()),
                                            sensor_imei: mobile.get("sensor_imei").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                            sensor_imsi: mobile.get("sim_imsi").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                            sensor_serial_number: None,
                                            sensor_msisdn: mobile.get("sim_msisdn").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                            latitude: mobile.get("location_verification").and_then(|v| v.get("latitude")).and_then(|v| v.as_f64()),
                                            longitude: mobile.get("location_verification").and_then(|v| v.get("longitude")).and_then(|v| v.as_f64()),
                                            accuracy: mobile.get("location_verification").and_then(|v| v.get("accuracy")).and_then(|v| v.as_f64()),
                                        });
                                    }

                                    // Check for "gnss" nested object
                                    if let Some(gnss) = geo.get("gnss") {
                                        return Some(SensorInfo {
                                            sensor_id: gnss.get("sensor_id").and_then(|v| v.as_str()).unwrap_or("unknown").to_string(),
                                            sensor_type: Some("gnss".to_string()),
                                            sensor_imei: None,
                                            sensor_imsi: None,
                                            sensor_serial_number: gnss.get("sensor_serial_number").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                            sensor_msisdn: None,
                                            latitude: gnss.get("retrieved_location").and_then(|v| v.get("latitude")).and_then(|v| v.as_f64()),
                                            longitude: gnss.get("retrieved_location").and_then(|v| v.get("longitude")).and_then(|v| v.as_f64()),
                                            accuracy: gnss.get("retrieved_location").and_then(|v| v.get("accuracy")).and_then(|v| v.as_f64()),
                                        });
                                    }

                                    // Fallback for legacy flattened grc.geolocation (Backward Compatibility)
                                    if let Some(sensor_id_val) = geo.get("sensor_id") {
                                        if let Some(sensor_id_str) = sensor_id_val.as_str() {
                                            return Some(SensorInfo {
                                                sensor_id: sensor_id_str.to_string(),
                                                sensor_type: geo.get("type").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                                sensor_imei: geo.get("sensor_imei").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                                sensor_imsi: geo.get("sensor_imsi").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                                sensor_serial_number: geo.get("sensor_serial_number").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                                sensor_msisdn: geo.get("sensor_msisdn").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                                latitude: geo.get("latitude").and_then(|v| v.as_f64()),
                                                longitude: geo.get("longitude").and_then(|v| v.as_f64()),
                                                accuracy: geo.get("accuracy").and_then(|v| v.as_f64()),
                                            });
                                        }
                                    }
                                }
                            }
                            Err(e) => {
                                proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Certificate {}: Failed to parse JSON: {:?}", cert_idx, e));
                            }
                        }
                    }
                    Err(e) => {
                        proxy_wasm::hostcalls::log(LogLevel::Warn, &format!("Certificate {}: Extension value is not valid UTF-8: {:?}", cert_idx, e));
                    }
                }
            }
        }
    }

    proxy_wasm::hostcalls::log(LogLevel::Warn, "=== SENSOR INFORMATION MISSING ===\n  sensor_id: MISSING\n  sensor_imei: MISSING\n  sensor_imsi: MISSING\n========================================\nNo sensor information found in certificate chain");
    None
}
