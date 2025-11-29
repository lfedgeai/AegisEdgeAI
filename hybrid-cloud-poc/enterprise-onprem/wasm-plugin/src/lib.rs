use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde::{Deserialize, Serialize};

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
    verification_result: bool,
}

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
        Box::new(SensorVerificationRoot)
    });
}}

struct SensorVerificationRoot;

impl Context for SensorVerificationRoot {}

impl RootContext for SensorVerificationRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(SensorVerificationFilter))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct SensorVerificationFilter {
    sensor_id: Option<String>,
}

impl Default for SensorVerificationFilter {
    fn default() -> Self {
        Self { sensor_id: None }
    }
}

impl Context for SensorVerificationFilter {}

impl HttpContext for SensorVerificationFilter {
    fn on_http_request_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        // Get client certificate from TLS connection (PEM format)
        let cert_pem = match self.get_property(&["connection", "tls", "peer_certificate"]) {
            Some(cert) => cert,
            None => {
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

        // Store sensor_id for use in response callback
        self.sensor_id = Some(sensor_id.clone());

        // Call mobile location service to verify sensor
        let verify_body = serde_json::to_string(&VerifyRequest {
            sensor_id: sensor_id.clone(),
        })
        .unwrap_or_default();

        let headers = vec![
            (":method", "POST"),
            (":path", "/verify"),
            (":authority", "localhost:5000"),
            ("content-type", "application/json"),
        ];

        match self.dispatch_http_call(
            "mobile_location_service",
            headers,
            Some(verify_body.as_bytes()),
            vec![],
            Duration::from_secs(5),
        ) {
            Ok(_) => Action::Pause,
            Err(_) => {
                self.send_http_response(
                    500,
                    vec![("content-type", "text/plain")],
                    Some(b"Failed to call mobile location service"),
                );
                Action::Pause
            }
        }
    }

    fn on_http_call_response(
        &mut self,
        _token_id: u32,
        _num_headers: usize,
        body_size: usize,
        _num_trailers: usize,
    ) {
        // Get response body from mobile location service
        let body = self.get_http_call_response_body(0, body_size);
        let body_str = String::from_utf8_lossy(&body);

        // Parse response
        let verify_response: VerifyResponse = match serde_json::from_str(&body_str) {
            Ok(resp) => resp,
            Err(_) => {
                self.send_http_response(
                    403,
                    vec![("content-type", "text/plain")],
                    Some(b"Sensor verification failed: invalid response"),
                );
                return;
            }
        };

        if !verify_response.verification_result {
            self.send_http_response(
                403,
                vec![("content-type", "text/plain")],
                Some(b"Sensor verification failed"),
            );
            return;
        }

        // Get sensor_id and add header, then continue to backend
        if let Some(sensor_id) = &self.sensor_id {
            self.add_http_request_header("X-Sensor-ID", sensor_id);
        }
        self.resume_http_request();
    }
}

fn extract_sensor_id_from_cert(cert_pem: &[u8]) -> Option<String> {
    // Parse certificate (handle both PEM and DER)
    let cert_bytes = if cert_pem.starts_with(b"-----BEGIN") {
        // PEM format - extract base64 content
        let pem_str = std::str::from_utf8(cert_pem).ok()?;
        let lines: Vec<&str> = pem_str
            .lines()
            .filter(|l| !l.starts_with("-----"))
            .collect();
        base64::decode(&lines.join("")).ok()?
    } else {
        cert_pem.to_vec()
    };

    // Parse X.509 certificate
    let (_, cert) = x509_parser::parse_x509_certificate(&cert_bytes).ok()?;

    // Find Unified Identity extension
    for ext in cert.extensions() {
        let oid_str = format!("{}", ext.oid());
        
        if oid_str == UNIFIED_IDENTITY_OID_STR || oid_str == LEGACY_OID_STR {
            // Parse extension value as JSON
            let ext_value = ext.value();
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

    None
}

