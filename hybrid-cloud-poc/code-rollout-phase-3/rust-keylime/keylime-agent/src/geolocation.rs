// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Geolocation PCR extension for TPM-bound geolocation attestation

use keylime::algorithms::HashAlgorithm;
use keylime::tpm::{Context as TpmContext, TpmError};
use log::*;
use sha2::{Digest, Sha256};
use std::convert::TryFrom;
use std::time::{SystemTime, UNIX_EPOCH};
use tss_esapi::{
    handles::PcrHandle,
    interface_types::algorithm::HashingAlgorithm,
    structures::{Digest as TpmDigest, DigestValues},
};

/// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
/// PCR index reserved for TPM-bound geolocation attestation
/// Per federated-jwt.md Appendix, PCR 17 or 18 is typically used
pub const GEOLOCATION_PCR_INDEX: u32 = 17;

/// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
/// Get current geolocation data with sensor detection
/// Returns a structured geolocation string that can be hashed and extended into PCR
/// Format: "mobile:sensor_id:geolocation" or "GNSS:sensor_id:geolocation" or "none"
fn get_current_geolocation() -> String {
    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Check for specific USB device IDs to determine sensor type
    let lsusb_output = std::process::Command::new("lsusb")
        .output()
        .ok()
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .unwrap_or_default();

    let mut sensor_type = None;
    let mut sensor_id = None;
    let mut geolocation_data: Option<String> = None;

    // Check for Huawei Mobile (12d1:1433)
    if lsusb_output.contains("12d1:1433") {
        sensor_type = Some("mobile");
        sensor_id = Some("12d1:1433");
        // Check if geolocation is provided via environment variable
        if let Ok(env_value) = std::env::var("KEYLIME_AGENT_GEOLOCATION") {
            let trimmed = env_value.trim();
            if !trimmed.is_empty() && !trimmed.eq_ignore_ascii_case("none") {
                geolocation_data = Some(trimmed.to_string());
            }
        }
        // If no geolocation data available, set to "none"
        if geolocation_data.is_none() {
            geolocation_data = Some("none".to_string());
        }
    }
    // Check for common u-blox GNSS receivers (example VIDs/PIDs)
    else if lsusb_output.contains("1546:01a7") || lsusb_output.contains("1546:01a8") || lsusb_output.contains("0403:6015") {
        sensor_type = Some("GNSS");
        // Extract sensor ID from lsusb output
        for line in lsusb_output.lines() {
            if line.contains("1546:01a7") {
                sensor_id = Some("1546:01a7");
                break;
            } else if line.contains("1546:01a8") {
                sensor_id = Some("1546:01a8");
                break;
            } else if line.contains("0403:6015") {
                sensor_id = Some("0403:6015");
                break;
            }
        }
        // Check if geolocation is provided via environment variable
        if let Ok(env_value) = std::env::var("KEYLIME_AGENT_GEOLOCATION") {
            let trimmed = env_value.trim();
            if !trimmed.is_empty() && !trimmed.eq_ignore_ascii_case("none") {
                geolocation_data = Some(trimmed.to_string());
            }
        }
        // If no geolocation data available, set to "none"
        if geolocation_data.is_none() {
            geolocation_data = Some("none".to_string());
        }
    }
    // Check for environment variable override (no sensor detected)
    else if let Ok(env_value) = std::env::var("KEYLIME_AGENT_GEOLOCATION") {
        let trimmed = env_value.trim();
        if !trimmed.is_empty() {
            geolocation_data = Some(trimmed.to_string());
        }
    }

    // Format the geolocation string
    let result = if let (Some(sensor), Some(id)) = (sensor_type, sensor_id) {
        // Sensor detected - format with sensor info
        if let Some(geo) = geolocation_data {
            let formatted = format!("{}:{}:{}", sensor, id, geo);
            info!("Unified-Identity - Phase 3: Detected {} sensor (ID: {}), geolocation: {}", sensor, id, geo);
            formatted
        } else {
            // Should not happen, but handle gracefully
            info!("Unified-Identity - Phase 3: Sensor detected but no geolocation data");
            format!("{}:{}:none", sensor, id)
        }
    } else if let Some(geo) = geolocation_data {
        // No sensor, but environment variable provided
        info!("Unified-Identity - Phase 3: Using geolocation from environment: {}", geo);
        geo
    } else {
        // No sensor and no environment variable
        info!("Unified-Identity - Phase 3: No geolocation sensor detected or data unavailable");
        "none".to_string()
    };

    result
}

/// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
/// Hash geolocation data with nonce and timestamp for TPM PCR extension
/// This creates a composite hash that binds location, nonce, and time together
fn hash_geolocation_data(geolocation: &str, nonce: &[u8], timestamp: u64) -> Vec<u8> {
    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Create composite data: geolocation + nonce + timestamp
    // This ensures the location claim is fresh and bound to the specific attestation request
    let mut hasher = Sha256::new();
    hasher.update(b"Unified-Identity-Geolocation:");
    hasher.update(geolocation.as_bytes());
    hasher.update(b":nonce:");
    hasher.update(nonce);
    hasher.update(b":timestamp:");
    hasher.update(timestamp.to_be_bytes());
    hasher.finalize().to_vec()
}

/// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
/// Extend geolocation data into PCR 17 for TPM-bound attestation
/// This function:
/// 1. Gets current geolocation (hardcoded for now)
/// 2. Hashes it with the nonce and timestamp
/// 3. Extends the hash into PCR 17
/// 4. Returns the geolocation data for inclusion in the response
pub fn extend_geolocation_into_pcr(
    tpm_context: &mut TpmContext<'_>,
    nonce: &[u8],
    hash_alg: HashAlgorithm,
) -> Result<String, TpmError> {
    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Step 1: Get current geolocation
    let geolocation = get_current_geolocation();
    
    // Step 2: Get current timestamp
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| TpmError::Other(format!("Failed to get timestamp: {}", e)))?
        .as_secs();
    
    // Step 3: Hash geolocation data with nonce and timestamp
    let location_hash = hash_geolocation_data(&geolocation, nonce, timestamp);
    
    // Step 4: Convert hash to DigestValues for TPM
    let hash_alg_tss = match hash_alg {
        HashAlgorithm::Sha256 => HashingAlgorithm::Sha256,
        HashAlgorithm::Sha384 => HashingAlgorithm::Sha384,
        HashAlgorithm::Sha512 => HashingAlgorithm::Sha512,
        _ => {
            warn!("Unified-Identity - Phase 3: Unsupported hash algorithm for geolocation PCR extension, using SHA256");
            HashingAlgorithm::Sha256
        }
    };

    let digest = TpmDigest::try_from(location_hash.as_slice())
        .map_err(|e| TpmError::Other(format!("Failed to convert geolocation hash to digest: {e}")))?;
    let mut digest_values = DigestValues::new();
    digest_values.set(hash_alg_tss, digest);
    
    // Step 5: Extend into PCR 17 (reset + extend handled by Context helper)
    tpm_context
        .reset_and_extend_pcr(PcrHandle::Pcr17, digest_values.clone())
        .map_err(|e| TpmError::Other(format!("Failed to extend geolocation into PCR 17: {e}")))?;
    
    info!(
        "Unified-Identity - Phase 3: Extended geolocation into PCR {} (location: {}, timestamp: {})",
        GEOLOCATION_PCR_INDEX, geolocation, timestamp
    );
    
    Ok(geolocation)
}

/// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
/// Check if Unified-Identity feature flag is enabled
pub fn is_unified_identity_enabled() -> bool {
    std::env::var("UNIFIED_IDENTITY_ENABLED")
        .unwrap_or_else(|_| "false".to_string())
        .to_lowercase()
        == "true"
        || std::env::var("UNIFIED_IDENTITY_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .to_lowercase()
            == "1"
        || std::env::var("UNIFIED_IDENTITY_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .to_lowercase()
            == "yes"
}

