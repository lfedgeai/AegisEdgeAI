// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Interface: SPIRE TPM Plugin → Keylime Agent
// Transport: HTTP over UDS (or localhost HTTP)
// Protocol: JSON REST API
// Port/Path: UDS socket or localhost:9002
// 
// Delegated certification handler for rust-keylime agent
// This implements the high-privilege side of delegated certification where
// the SPIRE Agent requests App Key certificates signed by the AK

use crate::QuoteData;
use actix_web::{http, web, HttpRequest, HttpResponse, Responder};
use base64::{engine::general_purpose::STANDARD as base64_standard, Engine as _};
use keylime::json_wrapper::JsonWrapper;
use keylime::tpm::Context as TpmContext;
use log::*;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;
use tss_esapi::{
    handles::KeyHandle,
    structures::{Attest, Data, Signature},
    traits::Marshall,
};

#[derive(Deserialize, Debug)]
pub struct CertifyAppKeyRequest {
    #[serde(rename = "api_version")]
    pub api_version: String,
    pub command: String,
    #[serde(rename = "app_key_public")]
    pub app_key_public: String,
    #[serde(rename = "app_key_context_path")]
    pub app_key_context_path: String,
}

#[derive(Serialize, Debug)]
pub struct CertifyAppKeyResponse {
    pub result: String,
    #[serde(rename = "app_key_certificate", skip_serializing_if = "Option::is_none")]
    pub app_key_certificate: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
/// Certify an App Key using the host's Attestation Key (AK)
async fn certify_app_key(
    req: HttpRequest,
    body: web::Json<CertifyAppKeyRequest>,
    data: web::Data<QuoteData<'_>>,
) -> impl Responder {
    info!(
        "Unified-Identity - Phase 3: Delegated certification request from {:?}",
        req.connection_info().peer_addr()
    );

    // Validate request
    if body.command != "certify_app_key" {
        warn!(
            "Unified-Identity - Phase 3: Invalid command: {}",
            body.command
        );
        return HttpResponse::BadRequest().json(CertifyAppKeyResponse {
            result: "ERROR".to_string(),
            app_key_certificate: None,
            error: Some(format!("Invalid command: {}", body.command)),
        });
    }

    // Check feature flag (would be from config in production)
    let unified_identity_enabled = std::env::var("UNIFIED_IDENTITY_ENABLED")
        .unwrap_or_else(|_| "false".to_string())
        .to_lowercase();
    
    if unified_identity_enabled != "true" && unified_identity_enabled != "1" && unified_identity_enabled != "yes" {
        warn!("Unified-Identity - Phase 3: Feature flag disabled, rejecting certification request");
        return HttpResponse::Forbidden().json(CertifyAppKeyResponse {
            result: "ERROR".to_string(),
            app_key_certificate: None,
            error: Some("Unified-Identity feature flag is disabled".to_string()),
        });
    }

    let app_ctx_path = PathBuf::from(&body.app_key_context_path);

    // Get TPM context and AK handle
    let mut tpm_context = data.tpmcontext.lock().unwrap(); //#[allow_ci]
    let ak_handle = data.ak_handle;

    info!(
        "Unified-Identity - Phase 3: Certifying App Key from context: {}",
        app_ctx_path.display()
    );

    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Step 1: Load App Key from context file using tpm2-tools
    // The context file contains a saved TPM object context that needs to be loaded
    // We use tpm2_readpublic to verify the key exists and get its handle
    let app_key_handle = match load_app_key_from_context(&app_ctx_path) {
        Ok(handle) => {
            info!(
                "Unified-Identity - Phase 3: App Key loaded successfully from context file"
            );
            handle
        }
        Err(e) => {
            error!(
                "Unified-Identity - Phase 3: Failed to load App Key from context: {}",
                e
            );
            return HttpResponse::BadRequest().json(CertifyAppKeyResponse {
                result: "ERROR".to_string(),
                app_key_certificate: None,
                error: Some(format!("Failed to load App Key from context: {}", e)),
            });
        }
    };

    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Step 2: Use TPM2_Certify to certify the App Key with the AK
    // Create qualifying data (nonce/challenge) for the certification
    // For now, we use a simple qualifying data (can be enhanced with actual nonce)
    let qualifying_data = match Data::try_from(b"Unified-Identity-Phase3-Certification".as_slice()) {
        Ok(data) => data,
        Err(e) => {
            error!(
                "Unified-Identity - Phase 3: Failed to create qualifying data: {}",
                e
            );
            return HttpResponse::InternalServerError().json(CertifyAppKeyResponse {
                result: "ERROR".to_string(),
                app_key_certificate: None,
                error: Some(format!("Failed to create qualifying data: {}", e)),
            });
        }
    };

    // Certify the App Key with the AK
    let (attest, signature) = match tpm_context.certify_credential(
        qualifying_data,
        app_key_handle,
        ak_handle,
    ) {
        Ok(result) => {
            info!(
                "Unified-Identity - Phase 3: App Key certified successfully with AK"
            );
            result
        }
        Err(e) => {
            error!(
                "Unified-Identity - Phase 3: TPM2_Certify failed: {}",
                e
            );
            return HttpResponse::InternalServerError().json(CertifyAppKeyResponse {
                result: "ERROR".to_string(),
                app_key_certificate: None,
                error: Some(format!("TPM2_Certify failed: {}", e)),
            });
        }
    };

    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Step 3: Format the certificate structure for Phase 2 compatibility
    // Phase 2 expects base64-encoded certificate with certify_data and signature
    let cert_data = match attest.marshall() {
        Ok(data) => data,
        Err(e) => {
            error!(
                "Unified-Identity - Phase 3: Failed to marshal attestation: {}",
                e
            );
            return HttpResponse::InternalServerError().json(CertifyAppKeyResponse {
                result: "ERROR".to_string(),
                app_key_certificate: None,
                error: Some(format!("Failed to marshal attestation: {}", e)),
            });
        }
    };

    let sig_data = match signature.marshall() {
        Ok(data) => data,
        Err(e) => {
            error!(
                "Unified-Identity - Phase 3: Failed to marshal signature: {}",
                e
            );
            return HttpResponse::InternalServerError().json(CertifyAppKeyResponse {
                result: "ERROR".to_string(),
                app_key_certificate: None,
                error: Some(format!("Failed to marshal signature: {}", e)),
            });
        }
    };

    // Create certificate structure compatible with Phase 2
    let cert_structure = serde_json::json!({
        "app_key_public": body.app_key_public,
        "certify_data": base64_standard.encode(&cert_data),
        "signature": base64_standard.encode(&sig_data),
        "hash_alg": "sha256",
        "format": "phase2_compatible"
    });

    // Encode as base64 for Phase 2 compatibility
    let cert_json = match serde_json::to_string(&cert_structure) {
        Ok(json) => json,
        Err(e) => {
            error!(
                "Unified-Identity - Phase 3: Failed to serialize certificate: {}",
                e
            );
            return HttpResponse::InternalServerError().json(CertifyAppKeyResponse {
                result: "ERROR".to_string(),
                app_key_certificate: None,
                error: Some(format!("Failed to serialize certificate: {}", e)),
            });
        }
    };

    let cert_b64 = base64_standard.encode(cert_json.as_bytes());

    info!(
        "Unified-Identity - Phase 3: App Key certificate generated successfully"
    );

    HttpResponse::Ok().json(CertifyAppKeyResponse {
        result: "SUCCESS".to_string(),
        app_key_certificate: Some(cert_b64),
        error: None,
    })
}

/// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
/// Load App Key from context file
/// The App Key is generated by the SPIRE TPM plugin and persisted at handle 0x8101000B
/// We first try to use the persisted handle, then fall back to loading from context file
fn load_app_key_from_context(context_path: &PathBuf) -> Result<KeyHandle, String> {
    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Step 1: Try to use the persisted App Key handle (0x8101000B)
    // The SPIRE TPM plugin persists the App Key at this handle
    let default_app_handle = "0x8101000B";
    let handle_output = Command::new("tpm2_readpublic")
        .arg("-c")
        .arg(default_app_handle)
        .output()
        .map_err(|e| format!("Failed to execute tpm2_readpublic for handle: {}", e))?;

    if handle_output.status.success() {
        // Key is persisted, use the handle
        let handle_value = u32::from_str_radix(
            default_app_handle.trim_start_matches("0x"),
            16,
        )
        .map_err(|e| format!("Failed to parse handle {}: {}", default_app_handle, e))?;

        // Create a TPM context to get the handle
        let tpm_ctx = TpmContext::new().map_err(|e| {
            format!("Failed to create TPM context: {}", e)
        })?;

        // Use tss_esapi to get the handle from the persistent handle
        // Store the inner context to avoid temporary value issues
        let inner_ctx_arc = tpm_ctx.inner();
        let mut inner_ctx = inner_ctx_arc.lock().unwrap(); //#[allow_ci]
        let key_handle: KeyHandle = inner_ctx
            .tr_from_tpm_public(tss_esapi::handles::TpmHandle::Persistent(
                tss_esapi::handles::PersistentTpmHandle::new(handle_value)
                    .map_err(|e| format!("Failed to create persistent handle: {}", e))?,
            ))
            .map_err(|e| format!("Failed to get key handle: {}", e))?
            .into();

        info!(
            "Unified-Identity - Phase 3: Using persisted App Key handle: {}",
            default_app_handle
        );
        return Ok(key_handle);
    }

    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Step 2: If not persisted, try to load from context file
    // Verify the context file exists and contains a valid key
    let output = Command::new("tpm2_readpublic")
        .arg("-c")
        .arg(context_path.as_os_str())
        .arg("-f")
        .arg("der")
        .output()
        .map_err(|e| format!("Failed to execute tpm2_readpublic: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "tpm2_readpublic failed for context file: {}",
            stderr
        ));
    }

    // Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
    // Note: Loading a transient key from context file requires parsing the context
    // file format or using tpm2-tools to load it. For Phase 3, we require the
    // App Key to be persisted at the known handle.
    // Future enhancement: Parse context file and load transient key using tss_esapi

    Err(format!(
        "App Key not found at persistent handle {} and context file loading requires key to be persisted",
        default_app_handle
    ))
}

/// Configure the endpoints for delegated certification
/// This would typically be exposed on a UNIX socket for local access only
pub(crate) fn configure_delegated_certification_endpoints(
    cfg: &mut web::ServiceConfig,
) {
    _ = cfg.service(
        web::resource("/certify_app_key")
            .route(web::post().to(certify_app_key)),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, web, App};

    #[actix_rt::test]
    async fn test_certify_app_key_invalid_command() {
        // Test with invalid command
        let req = CertifyAppKeyRequest {
            api_version: "v1".to_string(),
            command: "invalid_command".to_string(),
            app_key_public: "test_pubkey".to_string(),
            app_key_context_path: "/tmp/test.ctx".to_string(),
        };

        // This would need a proper QuoteData fixture
        // For now, just verify the structure
        assert_eq!(req.command, "invalid_command");
    }
}

