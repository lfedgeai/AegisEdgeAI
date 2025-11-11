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
/// Get current geolocation data (hardcoded for now, can be made dynamic in the future)
/// Returns a structured geolocation string that can be hashed and extended into PCR
fn get_current_geolocation() -> String {
    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Hardcoded geolocation - can be made dynamic in the future
    // Format: "country:state:city:latitude:longitude" or similar
    // For now, using a simple format that can be parsed later
    let default_geo = std::env::var("KEYLIME_AGENT_GEOLOCATION")
        .unwrap_or_else(|_| "US:California:San Francisco:37.7749:-122.4194".to_string());
    
    info!("Unified-Identity - Phase 3: Using geolocation: {}", default_geo);
    default_geo
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

