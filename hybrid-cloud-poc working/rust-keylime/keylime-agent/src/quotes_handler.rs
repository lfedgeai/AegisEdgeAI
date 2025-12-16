// SPDX-License-Identifier: Apache-2.0
// Copyright 2021 Keylime Authors

use crate::crypto;
use crate::serialization::serialize_maybe_base64;
use crate::{tpm, Error as KeylimeError, QuoteData};
use actix_web::{http, web, HttpRequest, HttpResponse, Responder};
use base64::{engine::general_purpose, Engine as _};
use hex;
use keylime::{
    json_wrapper::JsonWrapper,
    quote::{Geolocation, Integ, KeylimeQuote},
};
use log::*;
use serde::{Deserialize, Serialize};
use std::{
    fs::{read, read_to_string},
    io::{Read, Seek},
    process::Command,
};
use tss_esapi::structures::PcrSlot;

#[derive(Deserialize)]
pub struct Ident {
    nonce: String,
}

/// Unified-Identity: Detect geolocation sensor
/// Returns Geolocation struct with type, sensor_id, and optional value
/// - Mobile: Detects lsusb entries containing "mobile" (case-insensitive) or known IDs (e.g., 12d1:1433)
/// - GNSS: Detects lsusb entries containing "gnss", "gps", or "nmea" keywords, or known device paths
fn extract_usb_id(line: &str) -> String {
    if let Some(id_start) = line.find("ID ") {
        let id_part = &line[id_start + 3..];
        if let Some(id_end) = id_part.find(' ') {
            id_part[..id_end].to_string()
        } else {
            id_part.to_string()
        }
    } else {
        "unknown".to_string()
    }
}

/// Unified-Identity: Call get_imei_imsi_huawei.sh and parse IMEI/IMSI from output
/// Returns (imei, imsi) as Option<String> tuple
fn get_imei_imsi() -> (Option<String>, Option<String>) {
    // Try multiple possible script paths
    let script_paths = [
        "/home/mw/AegisEdgeAI/hybrid-cloud-poc/get_imei_imsi_huawei.sh",
        "./get_imei_imsi_huawei.sh",
        "get_imei_imsi_huawei.sh",
    ];

    for script_path in &script_paths {
        match Command::new("bash").arg(script_path).output() {
            Ok(output) => {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let stderr = String::from_utf8_lossy(&output.stderr);
                
                // Log script execution for debugging
                if !output.status.success() {
                    warn!("Unified-Identity: Script {} exited with non-zero status: {}", script_path, output.status);
                    if !stderr.is_empty() {
                        warn!("Unified-Identity: Script stderr: {}", stderr);
                    }
                }
                
                let mut imei = None;
                let mut imsi = None;

                // Parse output lines
                for line in stdout.lines() {
                    // Look for "Modem IMEI: <value>"
                    if line.contains("Modem IMEI:") {
                        if let Some(colon_pos) = line.find(':') {
                            let value = line[colon_pos + 1..].trim();
                            if !value.is_empty() && value != "Unknown" {
                                imei = Some(value.to_string());
                                debug!("Unified-Identity: Found IMEI in script output: {}", value);
                            }
                        }
                    }
                    // Look for "SIM IMSI:   <value>"
                    if line.contains("SIM IMSI:") {
                        if let Some(colon_pos) = line.find(':') {
                            let value = line[colon_pos + 1..].trim();
                            if !value.is_empty() && value != "Missing" && value != "Locked/Unreadable" {
                                imsi = Some(value.to_string());
                                debug!("Unified-Identity: Found IMSI in script output: {}", value);
                            }
                        }
                    }
                }

                if imei.is_some() || imsi.is_some() {
                    info!("Unified-Identity: Retrieved IMEI/IMSI from script {}: IMEI={:?}, IMSI={:?}", script_path, imei, imsi);
                    return (imei, imsi);
                } else {
                    debug!("Unified-Identity: Script {} ran successfully but no IMEI/IMSI found in output", script_path);
                    debug!("Unified-Identity: Script stdout (first 500 chars): {}", stdout.chars().take(500).collect::<String>());
                }
            }
            Err(e) => {
                warn!("Unified-Identity: Failed to run script {}: {}", script_path, e);
            }
        }
    }

    (None, None)
}

fn detect_geolocation_sensor() -> Option<Geolocation> {
    match Command::new("lsusb").output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                let line_lower = line.to_lowercase();

                if line_lower.contains("mobile") {
                    let sensor_id = extract_usb_id(line);
                    info!("Unified-Identity: Mobile geolocation sensor detected via lsusb: {}", sensor_id);
                    
                    // Unified-Identity: Get IMEI and IMSI from get_imei_imsi_huawei.sh
                    let (imei, imsi) = get_imei_imsi();
                    
                    return Some(Geolocation {
                        r#type: Some("mobile".to_string()),
                        sensor_id: Some(sensor_id),
                        value: None,
                        sensor_imei: imei,
                        sensor_imsi: imsi,
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
                    return Some(Geolocation {
                        r#type: Some("gnss".to_string()),
                        sensor_id: Some(sensor_id),
                        value: Some("".to_string()),
                        sensor_imei: None,
                        sensor_imsi: None,
                    });
                }
            }
        }
        Err(e) => {
            debug!("Unified-Identity: Failed to run lsusb: {}", e);
        }
    }

    let gnss_paths = ["/dev/ttyUSB0", "/dev/ttyACM0", "/dev/gps", "/dev/gps0"];

    for path in &gnss_paths {
        if std::path::Path::new(path).exists() {
            info!(
                "Unified-Identity: GNSS device detected at {}",
                path
            );
            return Some(Geolocation {
                r#type: Some("gnss".to_string()),
                sensor_id: Some(path.to_string()),
                value: Some("".to_string()),
                sensor_imei: None,
                sensor_imsi: None,
            });
        }
    }

    None
}

// This is a Quote request from the tenant, which does not check
// integrity measurement. It should return this data:
// { QuoteAIK(nonce, 16:H(payload_pub)), payload_pub }
async fn identity(
    req: HttpRequest,
    param: web::Query<Ident>,
    data: web::Data<QuoteData<'_>>,
) -> impl Responder {
    // nonce can only be in alphanumerical format
    if !param.nonce.chars().all(char::is_alphanumeric) {
        warn!(
            "Get quote returning 400 response. Parameters should be strictly alphanumeric: {}",
            param.nonce
        );
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            format!(
                "Parameters should be strictly alphanumeric: {}",
                param.nonce
            ),
        ));
    }

    // Note: param.nonce is a hex string, so its length in characters is 2x the byte length
    // We'll validate the decoded byte length after decoding
    // For now, check that hex string length is reasonable (max 64 hex chars = 32 bytes)
    if param.nonce.len() > tpm::MAX_NONCE_SIZE * 2 {
        warn!(
            "Get quote returning 400 response. Nonce hex string is too long (max {} hex chars for {} bytes): {}",
            tpm::MAX_NONCE_SIZE * 2,
            tpm::MAX_NONCE_SIZE,
            param.nonce.len()
        );
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            format!(
                "Nonce hex string is too long (max {} hex chars for {} bytes): {}",
                tpm::MAX_NONCE_SIZE * 2,
                tpm::MAX_NONCE_SIZE,
                param.nonce
            ),
        ));
    }

    debug!("Calling Identity Quote with nonce: {}", param.nonce);

    // Decode hex nonce string to bytes
    // The nonce comes from the HTTP query parameter as a hex string (e.g., "a1d071f5...")
    // We need to decode it to bytes, not treat it as ASCII
    let nonce_bytes = match hex::decode(&param.nonce) {
        Ok(bytes) => bytes,
        Err(e) => {
            warn!("Invalid hex nonce format: {} (error: {})", param.nonce, e);
            return HttpResponse::BadRequest().json(JsonWrapper::error(
                400,
                format!("Invalid hex nonce format: {}", e),
            ));
        }
    };

    // Validate nonce size (TPM supports up to 32 bytes for SHA-256)
    if nonce_bytes.len() > tpm::MAX_NONCE_SIZE {
        warn!(
            "Nonce too long after hex decode: {} bytes (max: {})",
            nonce_bytes.len(),
            tpm::MAX_NONCE_SIZE
        );
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            format!(
                "Nonce too long: {} bytes (max: {})",
                nonce_bytes.len(),
                tpm::MAX_NONCE_SIZE
            ),
        ));
    }

    // must unwrap here due to lock mechanism
    // https://github.com/rust-lang-nursery/failure/issues/192
    let mut context = data.tpmcontext.lock().unwrap(); //#[allow_ci]

    let tpm_quote = match context.quote(
        &nonce_bytes,
        0,
        &data.payload_pub_key,
        data.ak_handle,
        data.hash_alg,
        data.sign_alg,
    ) {
        Ok(quote) => quote,
        Err(e) => {
            debug!("Unable to retrieve quote: {e:?}");
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                "Unable to retrieve quote".to_string(),
            ));
        }
    };

    // Unified-Identity: Detect geolocation sensor (only if feature flag is enabled)
    let geolocation = if data.unified_identity_enabled {
        detect_geolocation_sensor()
    } else {
        None
    };

    let mut quote = KeylimeQuote {
        quote: tpm_quote,
        hash_alg: data.hash_alg.to_string(),
        enc_alg: data.enc_alg.to_string(),
        sign_alg: data.sign_alg.to_string(),
        geolocation,
        ..Default::default()
    };

    match crypto::pkey_pub_to_pem(&data.payload_pub_key) {
        Ok(pubkey) => quote.pubkey = Some(pubkey),
        Err(e) => {
            debug!("Unable to retrieve public key for quote: {e:?}");
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                "Unable to retrieve quote".to_string(),
            ));
        }
    }

    let response = JsonWrapper::success(quote);
    info!("GET identity quote returning 200 response");
    HttpResponse::Ok().json(response)
}

// This is a Quote request from the cloud verifier, which will check
// integrity measurement. The PCRs included in the Quote will be specified
// by the mask. It should return this data:
// { QuoteAIK(nonce, 16:H(payload_pub), xi:yi), payload_pub}
// where xi:yi are additional PCRs to be included in the quote.
async fn integrity(
    req: HttpRequest,
    param: web::Query<Integ>,
    data: web::Data<QuoteData<'_>>,
) -> impl Responder {
    // nonce, mask can only be in alphanumerical format
    if !param.nonce.chars().all(char::is_alphanumeric) {
        warn!(
            "Get quote returning 400 response. Parameters should be strictly alphanumeric: {}",
            param.nonce
        );
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            format!("nonce should be strictly alphanumeric: {}", param.nonce),
        ));
    }

    if !param.mask.chars().all(char::is_alphanumeric) {
        warn!(
            "Get quote returning 400 response. Parameters should be strictly alphanumeric: {}",
            param.mask
        );
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            format!("mask should be strictly alphanumeric: {}", param.mask),
        ));
    }

    let mask = match u32::from_str_radix(param.mask.trim_start_matches("0x"), 16) {
        Ok(mask) => mask,
        Err(e) => {
            return HttpResponse::BadRequest().json(JsonWrapper::error(
                400,
                format!(
                    "mask should be a hex encoded 32-bit integer: {}",
                    param.mask
                ),
            ));
        }
    };

    if param.nonce.len() > tpm::MAX_NONCE_SIZE {
        warn!(
            "Get quote returning 400 response. Nonce is too long (max size {}): {}",
            tpm::MAX_NONCE_SIZE,
            param.nonce.len()
        );
        return HttpResponse::BadRequest().json(JsonWrapper::error(
            400,
            format!(
                "Nonce is too long (max size: {}): {}",
                tpm::MAX_NONCE_SIZE,
                param.nonce.len()
            ),
        ));
    }

    // If partial="0", include the public key in the quote
    let pubkey = match &param.partial[..] {
        "0" => {
            let pubkey = match crypto::pkey_pub_to_pem(&data.payload_pub_key) {
                Ok(pubkey) => pubkey,
                Err(e) => {
                    debug!("Unable to retrieve public key: {e:?}");
                    return HttpResponse::InternalServerError().json(JsonWrapper::error(
                        500,
                        "Unable to retrieve public key".to_string(),
                    ));
                }
            };
            Some(pubkey)
        }
        "1" => None,
        _ => {
            warn!("Get quote returning 400 response. uri must contain key 'partial' and value '0' or '1'");
            return HttpResponse::BadRequest().json(JsonWrapper::error(
                400,
                "uri must contain key 'partial' and value '0' or '1'".to_string(),
            ));
        }
    };

    debug!(
        "Calling Integrity Quote with nonce: {}, mask: {}",
        param.nonce, param.mask
    );

    // If an index was provided, the request is for the entries starting from the given index
    // (iterative attestation). Otherwise the request is for the whole list.
    let nth_entry = match &param.ima_ml_entry {
        None => 0,
        Some(idx) => idx.parse::<u64>().unwrap_or(0),
    };

    // must unwrap here due to lock mechanism
    // https://github.com/rust-lang-nursery/failure/issues/192
    let mut context = data.tpmcontext.lock().unwrap(); //#[allow_ci]

    // Generate the ID quote.
    let tpm_quote = match context.quote(
        param.nonce.as_bytes(),
        mask,
        &data.payload_pub_key,
        data.ak_handle,
        data.hash_alg,
        data.sign_alg,
    ) {
        Ok(tpm_quote) => tpm_quote,
        Err(e) => {
            debug!("Unable to retrieve quote: {e:?}");
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                "Unable to retrieve quote".to_string(),
            ));
        }
    };

    let id_quote = KeylimeQuote {
        quote: tpm_quote,
        hash_alg: data.hash_alg.to_string(),
        enc_alg: data.enc_alg.to_string(),
        sign_alg: data.sign_alg.to_string(),
        ..Default::default()
    };

    // If PCR 0 is included in the mask, obtain the measured boot
    let mut mb_measurement_list = None;
    match tpm::check_mask(mask, &PcrSlot::Slot0) {
        Ok(true) => {
            if let Some(measuredboot_ml_file) = &data.measuredboot_ml_file {
                let mut ml = Vec::<u8>::new();
                let mut f = measuredboot_ml_file.lock().unwrap(); //#[allow_ci]
                if let Err(e) = f.rewind() {
                    debug!("Failed to rewind measured boot file: {e:?}");
                    return HttpResponse::InternalServerError().json(JsonWrapper::error(
                        500,
                        "Unable to retrieve quote".to_string(),
                    ));
                }
                mb_measurement_list = match f.read_to_end(&mut ml) {
                    Ok(_) => Some(general_purpose::STANDARD.encode(ml)),
                    Err(e) => {
                        warn!("Could not read TPM2 event log: {e:?}");
                        None
                    }
                };
            }
        }
        Err(e) => {
            debug!("Unable to check PCR mask: {e:?}");
            return HttpResponse::InternalServerError().json(JsonWrapper::error(
                500,
                "Unable to retrieve quote".to_string(),
            ));
        }
        _ => (),
    }

    // Generate the measurement list
    let (ima_measurement_list, ima_measurement_list_entry, num_entries) =
        if let Some(ima_file) = &data.ima_ml_file {
            let mut ima_ml = data.ima_ml.lock().unwrap(); //#[allow_ci]
            match ima_ml.read(
                &mut ima_file.lock().unwrap(), //#[allow_ci]
                nth_entry,
            ) {
                Ok(result) => (Some(result.0), Some(result.1), Some(result.2)),
                Err(e) => {
                    debug!("Unable to read measurement list: {e:?}");
                    return HttpResponse::InternalServerError().json(JsonWrapper::error(
                        500,
                        "Unable to retrieve quote".to_string(),
                    ));
                }
            }
        } else {
            (None, None, None)
        };

    // Generate the final quote based on the ID quote
    let quote = KeylimeQuote {
        pubkey,
        ima_measurement_list,
        mb_measurement_list,
        ima_measurement_list_entry,
        ..id_quote
    };

    let response = JsonWrapper::success(quote);
    info!("GET integrity quote returning 200 response");
    HttpResponse::Ok().json(response)
}

/// Handles the default case for the /quotes scope
async fn quotes_default(req: HttpRequest) -> impl Responder {
    let error;
    let response;
    let message;

    match req.head().method {
        http::Method::GET => {
            error = 400;
            message = "URI not supported, only /identity and /integrity are supported for GET in /quotes/ interface";
            response = HttpResponse::BadRequest().json(JsonWrapper::error(error, message));
        }
        _ => {
            error = 405;
            message = "Method is not supported in /quotes/ interface";
            response = HttpResponse::MethodNotAllowed()
                .insert_header(http::header::Allow(vec![http::Method::GET]))
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

/// Configure the endpoints for the /quotes scope
pub(crate) fn configure_quotes_endpoints(cfg: &mut web::ServiceConfig) {
    _ = cfg
        .service(web::resource("/identity").route(web::get().to(identity)))
        .service(web::resource("/integrity").route(web::get().to(integrity)))
        .default_service(web::to(quotes_default));
}

#[cfg(feature = "testing")]
#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, web, App};
    use keylime::{crypto::testing::pkey_pub_from_pem, tpm};
    use serde_json::{json, Value};

    #[actix_rt::test]
    async fn test_identity() {
        let (fixture, mutex) = QuoteData::fixture().await.unwrap(); //#[allow_ci]
        let quotedata = web::Data::new(fixture);
        let mut app = test::init_service(
            App::new()
                .app_data(quotedata.clone())
                .route("/vX.Y/quotes/identity", web::get().to(identity)),
        )
        .await;

        let req = test::TestRequest::get()
            .uri("/vX.Y/quotes/identity?nonce=1234567890ABCDEFHIJ")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let result: JsonWrapper<KeylimeQuote> = test::read_body_json(resp).await;
        assert_eq!(result.results.hash_alg.as_str(), "sha256");
        assert_eq!(result.results.enc_alg.as_str(), "rsa2048");
        assert_eq!(result.results.sign_alg.as_str(), "rsassa");
        assert!(
            pkey_pub_from_pem(&result.results.pubkey.unwrap()) //#[allow_ci]
                .unwrap() //#[allow_ci]
                .public_eq(&quotedata.payload_pub_key)
        );
        assert!(result.results.quote.starts_with('r'));

        let mut context = quotedata.tpmcontext.lock().unwrap(); //#[allow_ci]
        tpm::testing::check_quote(
            &mut context,
            quotedata.ak_handle,
            &result.results.quote,
            b"1234567890ABCDEFHIJ",
        )
        .expect("unable to verify quote");

        // Explicitly drop QuoteData to cleanup keys
        drop(context);
        drop(quotedata);
    }

    #[actix_rt::test]
    async fn test_integrity_pre() {
        let (fixture, mutex) = QuoteData::fixture().await.unwrap(); //#[allow_ci]
        let quotedata = web::Data::new(fixture);
        let mut app = test::init_service(
            App::new()
                .app_data(quotedata.clone())
                .route("vX.Y/quotes/integrity", web::get().to(integrity)),
        )
        .await;

        let req = test::TestRequest::get()
            .uri("/vX.Y/quotes/integrity?nonce=1234567890ABCDEFHIJ&mask=0x408000&partial=0")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let result: JsonWrapper<KeylimeQuote> = test::read_body_json(resp).await;
        assert_eq!(result.results.hash_alg.as_str(), "sha256");
        assert_eq!(result.results.enc_alg.as_str(), "rsa2048");
        assert_eq!(result.results.sign_alg.as_str(), "rsassa");
        assert!(
            pkey_pub_from_pem(&result.results.pubkey.unwrap()) //#[allow_ci]
                .unwrap() //#[allow_ci]
                .public_eq(&quotedata.payload_pub_key)
        );

        if let Some(ima_mutex) = &quotedata.ima_ml_file {
            let mut ima_ml_file = ima_mutex.lock().unwrap(); //#[allow_ci]
            ima_ml_file.rewind().unwrap(); //#[allow_ci]
            let mut ima_ml = String::new();
            match ima_ml_file.read_to_string(&mut ima_ml) {
                Ok(_) => {
                    assert_eq!(
                        result.results.ima_measurement_list.unwrap().as_str(), //#[allow_ci]
                        ima_ml
                    );
                    assert!(result.results.quote.starts_with('r'));

                    let mut context = quotedata.tpmcontext.lock().unwrap(); //#[allow_ci]
                    tpm::testing::check_quote(
                        &mut context,
                        quotedata.ak_handle,
                        &result.results.quote,
                        b"1234567890ABCDEFHIJ",
                    )
                    .expect("unable to verify quote");
                }
                Err(e) => panic!("Could not read IMA file: {e}"), //#[allow_ci]
            }
        } else {
            panic!("IMA file was None"); //#[allow_ci]
        }

        // Explicitly drop QuoteData to cleanup keys
        drop(quotedata);
    }

    #[actix_rt::test]
    async fn test_integrity_post() {
        let (fixture, mutex) = QuoteData::fixture().await.unwrap(); //#[allow_ci]
        let quotedata = web::Data::new(fixture);
        let mut app = test::init_service(
            App::new()
                .app_data(quotedata.clone())
                .route("/vX.Y/quotes/integrity", web::get().to(integrity)),
        )
        .await;

        let req = test::TestRequest::get()
            .uri("/vX.Y/quotes/integrity?nonce=1234567890ABCDEFHIJ&mask=0x408000&partial=1")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let result: JsonWrapper<KeylimeQuote> = test::read_body_json(resp).await;
        assert_eq!(result.results.hash_alg.as_str(), "sha256");
        assert_eq!(result.results.enc_alg.as_str(), "rsa2048");
        assert_eq!(result.results.sign_alg.as_str(), "rsassa");

        if let Some(ima_mutex) = &quotedata.ima_ml_file {
            let mut ima_ml_file = ima_mutex.lock().unwrap(); //#[allow_ci]
            ima_ml_file.rewind().unwrap(); //#[allow_ci]
            let mut ima_ml = String::new();
            match ima_ml_file.read_to_string(&mut ima_ml) {
                Ok(_) => {
                    assert_eq!(
                        result.results.ima_measurement_list.unwrap().as_str(), //#[allow_ci]
                        ima_ml
                    );
                    assert!(result.results.quote.starts_with('r'));
                }
                Err(e) => panic!("Could not read IMA file: {e}"), //#[allow_ci]
            }
        } else {
            panic!("IMA file was None"); //#[allow_ci]
        }

        let mut context = quotedata.tpmcontext.lock().unwrap(); //#[allow_ci]
        tpm::testing::check_quote(
            &mut context,
            quotedata.ak_handle,
            &result.results.quote,
            b"1234567890ABCDEFHIJ",
        )
        .expect("unable to verify quote");

        // Explicitly drop QuoteData to cleanup keys
        drop(context);
        drop(quotedata);
    }

    #[actix_rt::test]
    async fn test_missing_ima_file() {
        let (mut fixture, mutex) = QuoteData::fixture().await.unwrap(); //#[allow_ci]

        // Remove the IMA log file from the context
        fixture.ima_ml_file = None;
        let quotedata = web::Data::new(fixture);
        let mut app = test::init_service(
            App::new()
                .app_data(quotedata.clone())
                .route("/vX.Y/quotes/integrity", web::get().to(integrity)),
        )
        .await;

        let req = test::TestRequest::get()
            .uri("/vX.Y/quotes/integrity?nonce=1234567890ABCDEFHIJ&mask=0x408000&partial=0")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let result: JsonWrapper<KeylimeQuote> = test::read_body_json(resp).await;
        assert!(result.results.ima_measurement_list.is_none());
        assert!(result.results.ima_measurement_list_entry.is_none());

        // Explicitly drop QuoteData to cleanup keys
        drop(quotedata);
    }

    #[actix_rt::test]
    async fn test_keys_default() {
        let mut app =
            test::init_service(App::new().service(web::resource("/").to(quotes_default))).await;

        let req = test::TestRequest::get().uri("/").to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_client_error());

        let result: JsonWrapper<Value> = test::read_body_json(resp).await;

        assert_eq!(result.results, json!({}));
        assert_eq!(result.code, 400);

        let req = test::TestRequest::delete().uri("/").to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_client_error());

        let headers = resp.headers();

        assert!(headers.contains_key("allow"));
        assert_eq!(headers.get("allow").unwrap().to_str().unwrap(), "GET"); //#[allow_ci]

        let result: JsonWrapper<Value> = test::read_body_json(resp).await;

        assert_eq!(result.results, json!({}));
        assert_eq!(result.code, 405);
    }
}
