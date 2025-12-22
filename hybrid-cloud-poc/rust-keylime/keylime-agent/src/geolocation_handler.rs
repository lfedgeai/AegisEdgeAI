// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Keylime Authors

//! Geolocation Handler
//!
//! This module provides a dedicated endpoint for attested geolocation data,
//! separated from TPM quote operations. Part of Unified Identity (Pillar 2 Task 2).
//!
//! Endpoint: GET /v2/agent/attested_geolocation
//!
//! Features:
//! - Nested mobile/GNSS sensor structure
//! - PCR 17 attestation binding
//! - Feature flag gating (unified_identity_enabled)

use actix_web::{web, HttpResponse, Responder};
use keylime::json_wrapper::JsonWrapper; // Fixed import
use log::{debug, info, warn};
use serde::{Deserialize, Serialize};
use std::process::Command;

use crate::QuoteData;

/// Request parameters for geolocation endpoint
#[derive(Deserialize, Debug)]
pub struct GeolocationRequest {
    pub nonce: String, // Required for TOCTOU protection
}

/// Nested geolocation response structure
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct GeolocationResponse {
    pub sensor_type: String, // "mobile" or "gnss"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mobile: Option<MobileSensor>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gnss: Option<GNSSSensor>,
    pub tpm_attested: bool, // Always true for this endpoint
    pub tpm_pcr_index: u32,  // PCR 15 for geolocation
    pub nonce: String, // Nonce used in attestation (for verification)
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct MobileSensor {
    pub sensor_id: String,
    pub sensor_imei: String,
    pub sensor_imsi: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct GNSSSensor {
    pub sensor_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sensor_serial_number: Option<String>,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sensor_signature: Option<String>, // Optional - GNSS sensor's own signature
}

/// Raw sensor data detected from system
#[derive(Debug, Clone)]
struct RawSensorData {
    sensor_type: String,
    sensor_id: String,
    imei: Option<String>,
    imsi: Option<String>,
    // GNSS fields (future)
    lat: Option<f64>,
    lon: Option<f64>,
    accuracy: Option<f64>,
}

/// Main endpoint handler for attested geolocation
/// Requires nonce parameter for TOCTOU protection
pub(crate) async fn attested_geolocation(
    query: web::Query<GeolocationRequest>,
    data: web::Data<QuoteData<'_>>,
) -> impl Responder {
    // Feature flag check
    if !data.unified_identity_enabled {
        warn!("Unified-Identity: Attested geolocation endpoint accessed but feature disabled");
        return HttpResponse::Forbidden().json(JsonWrapper::error(
            403,
            "Unified Identity feature disabled".to_string(),
        ));
    }

    info!(
        "Unified-Identity: Geolocation request with nonce: {}",
        &query.nonce[..8.min(query.nonce.len())]
    );

    // Detect sensor
    let sensor_data = detect_geolocation_sensor();

    if sensor_data.is_none() {
        info!("Unified-Identity: No geolocation sensor detected");
        return HttpResponse::NotFound().json(JsonWrapper::error(
            404,
            "No geolocation sensor detected".to_string(),
        ));
    }

    let raw_sensor = sensor_data.unwrap(); //#[allow_ci]

    // Build nested structure (without nonce first)
    let mut response = build_nested_geolocation(raw_sensor);
    
    // Add nonce to response
    response.nonce = query.nonce.clone();

    // CRITICAL: Extend PCR 15 with geolocation + nonce for TOCTOU protection
    if let Err(e) = extend_pcr_15_with_geolocation_and_nonce(&data, &response, &query.nonce) {
        warn!("Unified-Identity: Failed to extend PCR 15: {}", e);
        return HttpResponse::InternalServerError().json(JsonWrapper::error(
            500,
            format!("Failed to extend PCR 15: {}", e),
        ));
    }

    info!(
        "Unified-Identity: Returning {} geolocation data",
        response.sensor_type
    );
    HttpResponse::Ok().json(JsonWrapper::success(response))
}

/// Build nested geolocation response from raw sensor data
fn build_nested_geolocation(raw: RawSensorData) -> GeolocationResponse {
    match raw.sensor_type.as_str() {
        "mobile" => GeolocationResponse {
            sensor_type: "mobile".to_string(),
            mobile: Some(MobileSensor {
                sensor_id: raw.sensor_id.clone(),
                sensor_imei: raw.imei.unwrap_or_else(|| "unknown".to_string()),
                sensor_imsi: raw.imsi.unwrap_or_else(|| "unknown".to_string()),
            }),
            gnss: None,
            tpm_attested: true,
            tpm_pcr_index: 15, // PCR 15 dedicated to geolocation
            nonce: String::new(), // Filled in by handler
        },
        "gnss" => GeolocationResponse {
            sensor_type: "gnss".to_string(),
            mobile: None,
            gnss: Some(GNSSSensor {
                sensor_id: raw.sensor_id.clone(),
                sensor_serial_number: None, // TODO: Extract from device
                latitude: raw.lat.unwrap_or(0.0),
                longitude: raw.lon.unwrap_or(0.0),
                accuracy: raw.accuracy.unwrap_or(0.0),
                sensor_signature: None, // Optional field
            }),
            tpm_attested: true,
            tpm_pcr_index: 15,
            nonce: String::new(), // Filled in by handler
        },
        _ => {
            // Fallback to mobile with unknown values
            GeolocationResponse {
                sensor_type: "mobile".to_string(),
                mobile: Some(MobileSensor {
                    sensor_id: raw.sensor_id.clone(),
                    sensor_imei: "unknown".to_string(),
                    sensor_imsi: "unknown".to_string(),
                }),
                gnss: None,
                tpm_attested: true,
                tpm_pcr_index: 15,
                nonce: String::new(), // Filled in by handler
            }
        }
    }
}

/// Detect geolocation sensor (mobile or GNSS)
/// Moved from quotes_handler.rs
fn detect_geolocation_sensor() -> Option<RawSensorData> {
    // Try lsusb first for USB-connected sensors
    match Command::new("lsusb").output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                let line_lower = line.to_lowercase();

                if line_lower.contains("mobile") {
                    let sensor_id = extract_usb_id(line);
                    info!(
                        "Unified-Identity: Mobile geolocation sensor detected via lsusb: {}",
                        sensor_id
                    );

                    // Get IMEI and IMSI from script
                    let (imei, imsi) = get_imei_imsi();

                    return Some(RawSensorData {
                        sensor_type: "mobile".to_string(),
                        sensor_id,
                        imei,
                        imsi,
                        lat: None,
                        lon: None,
                        accuracy: None,
                    });
                }

                if line_lower.contains("gnss")
                    || line_lower.contains("gps")
                    || line_lower.contains("nmea")
                {
                    let sensor_id = extract_usb_id(line);
                    info!(
                        "Unified-Identity: GNSS/GPS sensor detected via lsusb: {}",
                        sensor_id
                    );
                    return Some(RawSensorData {
                        sensor_type: "gnss".to_string(),
                        sensor_id,
                        imei: None,
                        imsi: None,
                        lat: None, // TODO: Parse from GNSS device
                        lon: None,
                        accuracy: None,
                    });
                }
            }
        }
        Err(e) => {
            debug!("Unified-Identity: Failed to run lsusb: {}", e);
        }
    }

    // Fallback: Check for GNSS device nodes
    let gnss_paths = ["/dev/ttyUSB0", "/dev/ttyACM0", "/dev/gps", "/dev/gps0"];

    for path in &gnss_paths {
        if std::path::Path::new(path).exists() {
            info!("Unified-Identity: GNSS device detected at {}", path);
            return Some(RawSensorData {
                sensor_type: "gnss".to_string(),
                sensor_id: path.to_string(),
                imei: None,
                imsi: None,
                lat: None,
                lon: None,
                accuracy: None,
            });
        }
    }

    None
}

/// Extract USB device ID from lsusb output line
fn extract_usb_id(line: &str) -> String {
    // lsusb format: "Bus 001 Device 005: ID 12d1:1433 Huawei Technologies Co., Ltd."
    if let Some(id_pos) = line.find("ID ") {
        let after_id = &line[id_pos + 3..];
        if let Some(space_pos) = after_id.find(' ') {
            return after_id[..space_pos].to_string();
        }
    }
    "unknown".to_string()
}

/// Get IMEI and IMSI from Huawei script
fn get_imei_imsi() -> (Option<String>, Option<String>) {
    let script_paths = [
        "/usr/local/bin/get_imei_imsi_huawei.sh",
        "./get_imei_imsi_huawei.sh",
        "../get_imei_imsi_huawei.sh",
    ];

    for script_path in &script_paths {
        if !std::path::Path::new(script_path).exists() {
            continue;
        }

        debug!(
            "Unified-Identity: Running script to get IMEI/IMSI: {}",
            script_path
        );

        match Command::new(script_path).output() {
            Ok(output) => {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut imei: Option<String> = None;
                let mut imsi: Option<String> = None;

                for line in stdout.lines() {
                    // Look for "SIM IMEI:   <value>"
                    if line.contains("SIM IMEI:") {
                        if let Some(colon_pos) = line.find(':') {
                            let value = line[colon_pos + 1..].trim();
                            if !value.is_empty()
                                && value != "Missing"
                                && value != "Locked/Unreadable"
                            {
                                imei = Some(value.to_string());
                                debug!(
                                    "Unified-Identity: Found IMEI in script output: {}",
                                    value
                                );
                            }
                        }
                    }
                    // Look for "SIM IMSI:   <value>"
                    if line.contains("SIM IMSI:") {
                        if let Some(colon_pos) = line.find(':') {
                            let value = line[colon_pos + 1..].trim();
                            if !value.is_empty()
                                && value != "Missing"
                                && value != "Locked/Unreadable"
                            {
                                imsi = Some(value.to_string());
                                debug!(
                                    "Unified-Identity: Found IMSI in script output: {}",
                                    value
                                );
                            }
                        }
                    }
                }

                if imei.is_some() || imsi.is_some() {
                    info!(
                        "Unified-Identity: Retrieved IMEI/IMSI from script {}: IMEI={:?}, IMSI={:?}",
                        script_path, imei, imsi
                    );
                    return (imei, imsi);
                } else {
                    debug!(
                        "Unified-Identity: Script {} ran successfully but no IMEI/IMSI found in output",
                        script_path
                    );
                }
            }
            Err(e) => {
                warn!(
                    "Unified-Identity: Failed to run script {}: {}",
                    script_path, e
                );
            }
        }
    }

    (None, None)
}


/// Extend PCR 15 with geolocation data hash INCLUDING nonce
///
/// This function provides TOCTOU protection by binding geolocation to a fresh nonce:
/// 1. Serializes the geolocation nested structure to JSON (without nonce field)
/// 2. Concatenates geolocation JSON with nonce
/// 3. Computes SHA-256 hash of (geolocation + nonce)
/// 4. Creates DigestValues for TPM
/// 5. Extends PCR 15 (dedicated to geolocation)
///
/// Security: The nonce ensures geolocation freshness. An attacker cannot reuse
/// old geolocation data with a new nonce because the PCR 15 hash won't match.
fn extend_pcr_15_with_geolocation_and_nonce(
    quote_data: &QuoteData,
    geolocation: &GeolocationResponse,
    nonce: &str,
) -> Result<(), String> {
    use keylime::tpm;
    use openssl::hash::{Hasher, MessageDigest};
    use tss_esapi::structures::{DigestValues, PcrSlot};
    use tss_esapi::interface_types::algorithm::HashingAlgorithm;

    // 1. Serialize geolocation data to JSON (create temp struct without nonce to avoid circularity)
    let geo_for_hash = serde_json::json!({
        "sensor_type": geolocation.sensor_type,
        "mobile": geolocation.mobile,
        "gnss": geolocation.gnss,
        "tpm_attested": geolocation.tpm_attested,
        "tpm_pcr_index": geolocation.tpm_pcr_index,
    });
    
    let geo_json = serde_json::to_string(&geo_for_hash)
        .map_err(|e| format!("Failed to serialize geolocation: {}", e))?;

    // 2. Concatenate geolocation JSON with nonce for TOCTOU protection
    let data_to_hash = format!("{}{}", geo_json, nonce);

    debug!(
        "Unified-Identity: Hashing for PCR 17: geo({} bytes) + nonce({} bytes)",
        geo_json.len(),
        nonce.len()
    );

    // 3. Compute SHA-256 hash
    let mut hasher = Hasher::new(MessageDigest::sha256())
        .map_err(|e| format!("Failed to create hasher: {}", e))?;
    hasher
        .update(data_to_hash.as_bytes())
        .map_err(|e| format!("Failed to update hasher: {}", e))?;
    let hash_bytes = hasher
        .finish()
        .map_err(|e| format!("Failed to finish hash: {}", e))?;

    info!(
        "Unified-Identity: PCR 15 hash (geo + nonce): {}",
        hex::encode(&hash_bytes)
    );

    // 4. Create DigestValues for TPM
    let mut digest_values = DigestValues::new();
    let digest = tss_esapi::structures::Digest::try_from(hash_bytes.as_ref())
        .map_err(|e| format!("Failed to create TPM digest: {}", e))?;
    digest_values.set(HashingAlgorithm::Sha256, digest);

    // 5. Access TPM context and extend PCR 15
    let mut tpm_ctx = quote_data.tpmcontext.lock()
        .map_err(|e| format!("Failed to lock TPM context: {}", e))?;
    
    tpm_ctx.extend_pcr(tss_esapi::handles::PcrHandle::Pcr15, digest_values)
        .map_err(|e| format!("Failed to extend PCR 15: {:?}", e))?;

    info!(
        "Unified-Identity: PCR 15 extended with geolocation + nonce (nonce: {}...)",
        &nonce[..8.min(nonce.len())]
    );

    Ok(())
}
