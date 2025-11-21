// SPDX-License-Identifier: Apache-2.0
// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
// Copyright 2024 Keylime Authors

use crate::{tpm, Error as KeylimeError, QuoteData};
use actix_web::{http, web, HttpRequest, HttpResponse, Responder};
use base64::{engine::general_purpose, Engine as _};
use keylime::json_wrapper::JsonWrapper;
use log::*;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use tss_esapi::{
    handles::KeyHandle,
    structures::{Attest, Data, Signature},
    traits::Marshall,
};

#[derive(Deserialize, Debug)]
pub struct CertifyAppKeyRequest {
    #[serde(rename = "api_version")]
    pub api_version: Option<String>,
    pub command: Option<String>,
    #[serde(rename = "app_key_public")]
    pub app_key_public: String,
    #[serde(rename = "app_key_context_path")]
    pub app_key_context_path: String,
    #[serde(rename = "challenge_nonce")]
    pub challenge_nonce: Option<String>,
}

#[derive(Serialize, Debug)]
pub struct CertifyAppKeyResponse {
    pub result: String,
    #[serde(
        rename = "app_key_certificate",
        skip_serializing_if = "Option::is_none"
    )]
    pub app_key_certificate: Option<String>,
    #[serde(rename = "agent_uuid", skip_serializing_if = "Option::is_none")]
    pub agent_uuid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Unified-Identity - Phase 3: Delegated Certification Endpoint
///
/// This endpoint allows the SPIRE TPM Plugin to request a certificate for an App Key
/// that was generated in the TPM. The certificate is created by using TPM2_Certify to
/// sign the App Key's public key with the agent's Attestation Key (AK).
///
/// The certificate format is a JSON object containing:
/// - certify_data: The attestation structure (base64 encoded)
/// - signature: The signature over the attestation (base64 encoded)
async fn certify_app_key(
    req: HttpRequest,
    body: web::Json<CertifyAppKeyRequest>,
    data: web::Data<QuoteData<'_>>,
) -> impl Responder {
    info!(
        "Unified-Identity - Phase 3: Delegated certification request from {:?}",
        req.connection_info().peer_addr()
    );

    let request = body.into_inner();

    // Validate required fields
    if request.app_key_public.is_empty() {
        warn!("Delegated certification request missing app_key_public");
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            "Missing required field: app_key_public".to_string(),
        ));
    }

    if request.app_key_context_path.is_empty() {
        warn!("Delegated certification request missing app_key_context_path");
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            "Missing required field: app_key_context_path".to_string(),
        ));
    }

    let challenge_nonce = match request.challenge_nonce.as_ref() {
        Some(nonce) if !nonce.is_empty() => nonce.clone(),
        _ => {
            warn!("Delegated certification request missing challenge_nonce");
            return HttpResponse::BadRequest().json(JsonWrapper::error(
                400,
                "Missing required field: challenge_nonce".to_string(),
            ));
        }
    };

    // Validate that the context file exists
    let context_path = Path::new(&request.app_key_context_path);
    if !context_path.exists() {
        warn!(
            "App Key context file not found: {}",
            request.app_key_context_path
        );
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            format!(
                "App Key context file not found: {}",
                request.app_key_context_path
            ),
        ));
    }

    // Get TPM context first (we'll need it for loading the App Key)
    let mut context = data.tpmcontext.lock().unwrap(); //#[allow_ci]

    // Load the App Key from the context file using tpm::Context method
    let app_key_handle = match context.load_key_from_context_file(&request.app_key_context_path) {
        Ok(handle) => handle,
        Err(e) => {
            error!("Failed to load App Key from context file: {:?}", e);
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                format!("Failed to load App Key from context file: {}", e),
            ));
        }
    };

    // Parse the App Key public key (PEM format)
    let app_key_public_pem = match request.app_key_public.strip_prefix("-----BEGIN") {
        Some(_) => request.app_key_public.clone(),
        None => {
            // Try to decode as base64 if not already PEM
            match general_purpose::STANDARD.decode(&request.app_key_public) {
                Ok(bytes) => match String::from_utf8(bytes) {
                    Ok(s) => s,
                    Err(e) => {
                        error!("Failed to decode app_key_public as UTF-8: {}", e);
                        return HttpResponse::BadRequest().json(JsonWrapper::error(
                            400,
                            "Invalid app_key_public format".to_string(),
                        ));
                    }
                },
                Err(_) => {
                    // Assume it's already PEM format
                    request.app_key_public.clone()
                }
            }
        }
    };

    // Convert PEM public key to TPM digest for qualifying data
    // The qualifying data should be the hash of the App Key public key
    let qualifying_data = match create_qualifying_data(&app_key_public_pem, &challenge_nonce) {
        Ok(data) => data,
        Err(e) => {
            error!(
                "Failed to create qualifying data from App Key public key: {}",
                e
            );
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                format!("Failed to process App Key public key: {}", e),
            ));
        }
    };

    // Use the AK to certify the App Key (context is already locked above)
    let (attest, signature) =
        match context.certify_credential(qualifying_data, app_key_handle, data.ak_handle) {
            Ok((attest, sig)) => (attest, sig),
            Err(e) => {
                error!("TPM2_Certify failed: {:?}", e);
                return HttpResponse::InternalServerError().json(JsonWrapper::error(
                    500,
                    format!("TPM2_Certify failed: {}", e),
                ));
            }
        };

    // Serialize attestation and signature to base64
    let attest_bytes = match attest.marshall() {
        Ok(bytes) => bytes,
        Err(e) => {
            error!("Failed to serialize attestation: {:?}", e);
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                "Failed to serialize attestation".to_string(),
            ));
        }
    };

    let sig_bytes = match signature.marshall() {
        Ok(bytes) => bytes,
        Err(e) => {
            error!("Failed to serialize signature: {:?}", e);
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                "Failed to serialize signature".to_string(),
            ));
        }
    };

    // Create certificate JSON structure (matching Keylime Verifier expectations)
    let certificate = serde_json::json!({
        "certify_data": general_purpose::STANDARD.encode(&attest_bytes),
        "signature": general_purpose::STANDARD.encode(&sig_bytes),
        "challenge_nonce": challenge_nonce,
    });

    let certificate_b64 = general_purpose::STANDARD.encode(certificate.to_string().as_bytes());

    let response = CertifyAppKeyResponse {
        result: "SUCCESS".to_string(),
        app_key_certificate: Some(certificate_b64),
        agent_uuid: Some(data.agent_uuid.clone()),
        error: None,
    };

    info!(
        "Unified-Identity - Phase 3: Delegated certification successful for agent {}",
        data.agent_uuid
    );

    HttpResponse::Ok().json(response)
}

/// Create qualifying data (hash) from PEM public key and challenge nonce
fn create_qualifying_data(pem: &str, challenge_nonce: &str) -> Result<Data, String> {
    use openssl::hash::{Hasher, MessageDigest};
    use openssl::pkey::PKey;

    // Parse PEM public key
    let pkey = PKey::public_key_from_pem(pem.as_bytes())
        .map_err(|e| format!("Failed to parse PEM public key: {}", e))?;

    // Get public key bytes
    let pubkey_bytes = pkey
        .public_key_to_pem()
        .map_err(|e| format!("Failed to serialize public key: {}", e))?;

    // Hash the public key using SHA-256
    let mut hasher = Hasher::new(MessageDigest::sha256())
        .map_err(|e| format!("Failed to create hasher: {}", e))?;
    hasher
        .update(&pubkey_bytes)
        .map_err(|e| format!("Failed to hash public key: {}", e))?;
    let pubkey_hash = hasher
        .finish()
        .map_err(|e| format!("Failed to finish hash: {}", e))?;

    // Combine public key hash with challenge nonce and hash again
    let mut combined_hasher = Hasher::new(MessageDigest::sha256())
        .map_err(|e| format!("Failed to create combined hasher: {}", e))?;
    combined_hasher
        .update(pubkey_hash.as_ref())
        .map_err(|e| format!("Failed to hash public key digest: {}", e))?;
    combined_hasher
        .update(challenge_nonce.as_bytes())
        .map_err(|e| format!("Failed to hash challenge nonce: {}", e))?;
    let combined_hash = combined_hasher
        .finish()
        .map_err(|e| format!("Failed to finish combined hash: {}", e))?;

    Data::try_from(combined_hash.as_ref())
        .map_err(|e| format!("Failed to create TPM Data from combined hash: {}", e))
}

/// Configure the endpoints for the /delegated_certification scope
pub(crate) fn configure_delegated_certification_endpoints(cfg: &mut web::ServiceConfig) {
    _ = cfg
        .service(web::resource("/certify_app_key").route(web::post().to(certify_app_key)))
        .default_service(web::to(delegated_certification_default));
}

/// Default handler for /delegated_certification scope
async fn delegated_certification_default(req: HttpRequest) -> impl Responder {
    let error;
    let response;
    let message;

    match req.head().method {
        http::Method::POST => {
            error = 400;
            message = "URI not supported, only /certify_app_key is supported for POST in /delegated_certification interface";
            response = HttpResponse::BadRequest().json(JsonWrapper::error(error, message));
        }
        _ => {
            error = 405;
            message = "Method is not supported in /delegated_certification interface";
            response = HttpResponse::MethodNotAllowed()
                .insert_header(http::header::Allow(vec![http::Method::POST]))
                .json(JsonWrapper::error(error, message));
        }
    };

    warn!(
        "{} returning {} response. {}",
        req.head().method,
        error,
        message
    );

    response
}
