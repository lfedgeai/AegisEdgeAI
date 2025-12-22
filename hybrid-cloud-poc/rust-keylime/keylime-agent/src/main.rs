// SPDX-License-Identifier: Apache-2.0
// Copyright 2021 Keylime Authors

#![deny(
    nonstandard_style,
    dead_code,
    improper_ctypes,
    non_shorthand_field_patterns,
    no_mangle_generic_items,
    overflowing_literals,
    path_statements,
    patterns_in_fns_without_body,
    unconditional_recursion,
    unused,
    while_true,
    missing_copy_implementations,
    missing_debug_implementations,
    missing_docs,
    trivial_casts,
    trivial_numeric_casts,
    unused_allocation,
    unused_comparisons,
    unused_parens,
    unused_extern_crates,
    unused_import_braces,
    unused_qualifications,
    unused_results
)]
// Temporarily allow these until they can be fixed
//  unused: there is a lot of code that's for now unused because this codebase is still in development
//  missing_docs: there is many functions missing documentations for now
#![allow(unused, missing_docs)]

mod agent_handler;
mod api;
mod delegated_certification_handler;
mod errors_handler;
mod geolocation_handler; // Unified-Identity: Task 2 - Geolocation API endpoint
mod keys_handler;
mod notifications_handler;
mod payloads;
mod quotes_handler;
mod revocation;

use actix_web::{dev::Service, http, middleware, rt, web, App, HttpServer};
use base64::{engine::general_purpose, Engine as _};
use clap::{Arg, Command as ClapApp};
use futures::{
    future::{ok, TryFutureExt},
    try_join,
};
use keylime::{
    agent_data::AgentData,
    agent_registration::{AgentRegistration, AgentRegistrationConfig},
    config,
    crypto::{self, x509::CertificateBuilder},
    device_id::{DeviceID, DeviceIDBuilder},
    error::{Error, Result},
    hash_ek,
    ima::MeasurementList,
    list_parser::parse_list,
    permissions,
    registrar_client::RegistrarClientBuilder,
    secure_mount, serialization,
    tpm::{self, IAKResult, IDevIDResult},
};
use log::*;
use openssl::{
    pkey::{PKey, Private, Public},
    x509::X509,
};
use std::{
    convert::TryFrom,
    fs,
    io::{BufReader, Read, Write},
    net::IpAddr,
    path::{Path, PathBuf},
    str::FromStr,
    sync::Mutex,
    time::{Duration, Instant},
};
use tokio::{
    signal::unix::{signal, SignalKind},
    sync::{mpsc, oneshot},
};
use tss_esapi::{
    handles::KeyHandle,
    interface_types::algorithm::{AsymmetricAlgorithm, HashingAlgorithm},
    interface_types::resource_handles::Hierarchy,
    structures::{Auth, Data, Digest, MaxBuffer, PublicBuffer},
    traits::Marshall,
    Context,
};
use uuid::Uuid;

#[macro_use]
extern crate static_assertions;

static NOTFOUND: &[u8] = b"Not Found";

// This data is passed in to the actix httpserver threads that
// handle quotes.
#[derive(Debug)]
pub struct QuoteData<'a> {
    agent_uuid: String,
    ak_handle: KeyHandle,
    allow_payload_revocation_actions: bool,
    api_versions: Vec<String>,
    enc_alg: keylime::algorithms::EncryptionAlgorithm,
    hash_alg: keylime::algorithms::HashAlgorithm,
    ima_ml: Mutex<MeasurementList>,
    ima_ml_file: Option<Mutex<fs::File>>,
    keys_tx: mpsc::Sender<(
        keys_handler::KeyMessage,
        Option<oneshot::Sender<keys_handler::SymmKeyMessage>>,
    )>,
    measuredboot_ml_file: Option<Mutex<fs::File>>,
    payload_tx: mpsc::Sender<payloads::PayloadMessage>,
    payload_priv_key: PKey<Private>,
    payload_pub_key: PKey<Public>,
    priv_key: PKey<Private>,
    pub_key: PKey<Public>,
    revocation_tx: mpsc::Sender<revocation::RevocationMessage>,
    secure_mount: PathBuf,
    secure_size: String,
    sign_alg: keylime::algorithms::SignAlgorithm,
    tpmcontext: Mutex<tpm::Context<'a>>,
    work_dir: PathBuf,
    // Unified-Identity: Feature flag for unified identity support
    unified_identity_enabled: bool,
    // Unified-Identity: Delegated certification config
    pub(crate) delegated_cert_enabled: bool,
    pub(crate) delegated_cert_allowed_ips: Vec<String>,
    pub(crate) delegated_cert_rate_limit: u32,
}

#[actix_web::main]
async fn main() -> Result<()> {
    // Print --help information
    let matches = ClapApp::new("keylime_agent")
        .about("A Rust implementation of the Keylime agent")
        .override_usage("sudo RUST_LOG=keylime_agent=trace ./target/debug/keylime_agent")
        .get_matches();

    pretty_env_logger::init();

    // Load config
    let mut config = config::AgentConfig::new()?;

    // load path for IMA logfile
    #[cfg(test)]
    fn ima_ml_path_get(_: &String) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("test-data")
            .join("ima")
            .join("ascii_runtime_measurements")
    }

    #[cfg(not(test))]
    fn ima_ml_path_get(s: &String) -> PathBuf {
        Path::new(&s).to_path_buf()
    }

    let ima_ml_path = ima_ml_path_get(&config.ima_ml_path);

    // check whether anyone has overridden the default
    if ima_ml_path.as_os_str() != config::DEFAULT_IMA_ML_PATH {
        warn!(
            "IMA measurement list location override: {}",
            ima_ml_path.display()
        );
    }

    // check IMA logfile exists & accessible
    let ima_ml_file = if ima_ml_path.exists() {
        match fs::File::open(&ima_ml_path) {
            Ok(file) => Some(Mutex::new(file)),
            Err(e) => {
                warn!(
                    "IMA measurement list not accessible: {}",
                    ima_ml_path.display()
                );
                None
            }
        }
    } else {
        warn!(
            "IMA measurement list not available: {}",
            ima_ml_path.display()
        );
        None
    };

    // load path for MBA logfile
    let mut measuredboot_ml_path = Path::new(&config.measuredboot_ml_path);
    let env_mb_path: String;
    #[cfg(feature = "testing")]
    if let Ok(v) = std::env::var("TPM_BINARY_MEASUREMENTS") {
        env_mb_path = v;
        measuredboot_ml_path = Path::new(&env_mb_path);
    }

    // check whether anyone has overridden the default MBA logfile
    if measuredboot_ml_path.as_os_str() != config::DEFAULT_MEASUREDBOOT_ML_PATH {
        warn!(
            "Measured boot measurement list location override: {}",
            measuredboot_ml_path.display()
        );
    }

    // check MBA logfile exists & accessible
    let measuredboot_ml_file = if measuredboot_ml_path.exists() {
        match fs::File::open(measuredboot_ml_path) {
            Ok(file) => Some(Mutex::new(file)),
            Err(e) => {
                warn!(
                    "Measured boot measurement list not accessible: {}",
                    measuredboot_ml_path.display()
                );
                None
            }
        }
    } else {
        warn!(
            "Measured boot measurement list not available: {}",
            measuredboot_ml_path.display()
        );
        None
    };

    // The agent cannot run when a payload script is defined, but mTLS is disabled and insecure
    // payloads are not explicitly enabled
    if !config.enable_agent_mtls
        && !config.enable_insecure_payload
        && !config.payload_script.is_empty()
    {
        let message = "The agent mTLS is disabled and 'payload_script' is not empty. To allow the agent to run, 'enable_insecure_payload' has to be set to 'True'".to_string();

        error!("Configuration error: {}", &message);
        return Err(Error::Configuration(config::KeylimeConfigError::Generic(
            message,
        )));
    }

    let secure_size = config.secure_size.clone();
    let work_dir = PathBuf::from(&config.keylime_dir);
    let mount = secure_mount::mount(&work_dir, &config.secure_size)?;

    let run_as = if permissions::get_euid() == 0 {
        if (config.run_as).is_empty() {
            warn!("Cannot drop privileges since 'run_as' is empty in 'agent' section of 'keylime-agent.conf'.");
            None
        } else {
            Some(&config.run_as)
        }
    } else {
        if !(config.run_as).is_empty() {
            warn!("Ignoring 'run_as' option because Keylime agent has not been started as root.");
        }
        None
    };

    // Drop privileges
    if let Some(user_group) = run_as {
        permissions::chown(user_group, &mount)?;
        if let Err(e) = permissions::run_as(user_group) {
            let message = "The user running the Keylime agent should be set in keylime-agent.conf, using the parameter `run_as`, with the format `user:group`".to_string();

            error!("Configuration error: {}", &message);
            return Err(Error::Configuration(config::KeylimeConfigError::Generic(
                message,
            )));
        }
        info!("Running the service as {user_group}...");
    }

    // Parse the configured API versions
    let api_versions = parse_list(&config.api_versions)?
        .iter()
        .map(|s| s.to_string())
        .collect::<Vec<_>>();

    info!(
        "Starting server with API versions: {}",
        &config.api_versions
    );

    let mut ctx = tpm::Context::new()?;

    cfg_if::cfg_if! {
        if #[cfg(feature = "legacy-python-actions")] {
            warn!("The support for legacy python revocation actions is deprecated and will be removed on next major release");

            let actions_dir = &config.revocation_actions_dir;
            // Verify if the python shim is installed in the expected location
            let python_shim = Path::new(&actions_dir).join("shim.py");
            if !python_shim.exists() {
                error!("Could not find python shim at {}", python_shim.display());
                return Err(Error::Configuration(
                    config::KeylimeConfigError::Generic(format!(
                    "Could not find python shim at {}",
                    python_shim.display()
                ))));
            }
        }
    }

    // When the tpm_ownerpassword is given, set auth for the Endorsement hierarchy.
    // Note in the Python implementation, tpm_ownerpassword option is also used for claiming
    // ownership of TPM access, which will not be implemented here.
    let tpm_ownerpassword = &config.tpm_ownerpassword;
    if !tpm_ownerpassword.is_empty() {
        let auth = if let Some(hex_ownerpassword) = tpm_ownerpassword.strip_prefix("hex:") {
            let decoded_ownerpassword = hex::decode(hex_ownerpassword).map_err(Error::from)?;
            Auth::try_from(decoded_ownerpassword)?
        } else {
            Auth::try_from(tpm_ownerpassword.as_bytes())?
        };
        ctx.tr_set_auth(Hierarchy::Endorsement.into(), auth)
            .map_err(|e| {
                Error::Configuration(config::KeylimeConfigError::Generic(format!(
                    "Failed to set TPM context password for Endorsement Hierarchy: {e}"
                )))
            })?;
    };

    let tpm_encryption_alg =
        keylime::algorithms::EncryptionAlgorithm::try_from(config.tpm_encryption_alg.as_ref())?;
    let tpm_hash_alg = keylime::algorithms::HashAlgorithm::try_from(config.tpm_hash_alg.as_ref())?;
    let tpm_signing_alg =
        keylime::algorithms::SignAlgorithm::try_from(config.tpm_signing_alg.as_ref())?;

    // Gather EK values and certs
    // If USE_TPM2_QUOTE_DIRECT is set, create EK using tpm2 createek for persistence
    let (ek_result, ek_persistent_handle) =
        if std::env::var("USE_TPM2_QUOTE_DIRECT").is_ok() && config.ek_handle.is_empty() {
            use std::fs;
            use std::path::PathBuf;
            use std::process::Command;

            // Create EK context file path in agent data directory
            let agent_data_dir = match config.agent_data_path.as_ref() {
                "" => PathBuf::from("/tmp/keylime-agent"),
                path => PathBuf::from(path)
                    .parent()
                    .unwrap_or(PathBuf::from("/tmp/keylime-agent").as_path())
                    .to_path_buf(),
            };
            fs::create_dir_all(&agent_data_dir).map_err(|e| {
                Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                    "Failed to create agent data directory: {}",
                    e
                )))
            })?;

            let ek_context_path = agent_data_dir.join("ek.ctx");
            let ek_context_str = ek_context_path.to_str().ok_or_else(|| {
                Error::Tpm(tpm::TpmError::HexDecodeError(
                    "Invalid EK context file path".to_string(),
                ))
            })?;

            let ek_pub_path = agent_data_dir.join("ek.pub");
            let ek_pub_str = ek_pub_path.to_str().ok_or_else(|| {
                Error::Tpm(tpm::TpmError::HexDecodeError(
                    "Invalid EK pub file path".to_string(),
                ))
            })?;

            let tcti = std::env::var("TCTI").unwrap_or_else(|_| "device:/dev/tpmrm0".to_string());
            let ek_persistent_handle_val = 0x81010001;

            info!("Creating EK using tpm2 createek for tpm2_quote direct mode");

            // Flush any existing transient handles first
            let _ = Command::new("tpm2")
                .arg("flushcontext")
                .arg("-t")
                .env("TCTI", &tcti)
                .output();

            // Create EK using tpm2 createek
            let createek_output = Command::new("tpm2")
                .arg("createek")
                .env("TCTI", &tcti)
                .arg("-G")
                .arg("rsa")
                .arg("-c")
                .arg(ek_context_str)
                .arg("-u")
                .arg(ek_pub_str)
                .output()
                .map_err(|e| {
                    Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                        "Failed to execute tpm2 createek: {}",
                        e
                    )))
                })?;

            if !createek_output.status.success() {
                let stderr = String::from_utf8_lossy(&createek_output.stderr);
                warn!(
                    "tpm2 createek failed: {}. Falling back to TSS library create_ek.",
                    stderr
                );
                // Fall back to TSS library method
                let ek_result = ctx.create_ek(tpm_encryption_alg, None)?;
                (ek_result, None)
            } else {
                info!(
                    "EK created successfully with context file: {}",
                    ek_context_str
                );

                // Persist EK to persistent handle
                let evict_output = Command::new("tpm2")
                    .arg("evictcontrol")
                    .env("TCTI", &tcti)
                    .arg("-C")
                    .arg("o")
                    .arg("-c")
                    .arg(ek_context_str)
                    .arg(&format!("{:#x}", ek_persistent_handle_val))
                    .output()
                    .map_err(|e| {
                        Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                            "Failed to execute tpm2 evictcontrol for EK: {}",
                            e
                        )))
                    })?;

                if !evict_output.status.success() {
                    let stderr = String::from_utf8_lossy(&evict_output.stderr);
                    warn!(
                        "Failed to persist EK: {}. Falling back to TSS library.",
                        stderr
                    );
                    let ek_result = ctx.create_ek(tpm_encryption_alg, None)?;
                    (ek_result, None)
                } else {
                    info!("EK persisted to handle {:#x}", ek_persistent_handle_val);

                    // Read EK public key to create EKResult
                    // We need to parse the public key file or use tpm2 readpublic
                    let readpub_output = Command::new("tpm2")
                        .arg("readpublic")
                        .env("TCTI", &tcti)
                        .arg("-c")
                        .arg(ek_context_str)
                        .arg("-f")
                        .arg("pem")
                        .output()
                        .map_err(|e| {
                            Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                                "Failed to read EK public key: {}",
                                e
                            )))
                        })?;

                    if !readpub_output.status.success() {
                        let stderr = String::from_utf8_lossy(&readpub_output.stderr);
                        warn!(
                            "Failed to read EK public key: {}. Falling back to TSS library.",
                            stderr
                        );
                        let ek_result = ctx.create_ek(tpm_encryption_alg, None)?;
                        (ek_result, None)
                    } else {
                        // Load the persistent EK handle
                        let ek_persistent_handle_tpm =
                            ctx.load_persistent_handle(ek_persistent_handle_val)?;

                        // Read public key from persistent handle using TSS library
                        let (ek_public, _, _) = ctx
                            .read_public_from_handle(ek_persistent_handle_tpm)
                            .map_err(|e| Error::Tpm(e))?;

                        // Create EKResult from the public key
                        // EKResult has public, key_handle, ek_cert, and ek_chain fields
                        let ek_result = tpm::EKResult {
                            public: ek_public,
                            key_handle: ek_persistent_handle_tpm,
                            ek_cert: None,  // EK cert not available from tpm2 createek
                            ek_chain: None, // EK chain not available from tpm2 createek
                        };

                        (ek_result, Some(ek_persistent_handle_val))
                    }
                }
            }
        } else {
            // Use TSS library method (standard)
            let ek_result = match config.ek_handle.as_ref() {
                "" => ctx.create_ek(tpm_encryption_alg, None)?,
                s => ctx.create_ek(tpm_encryption_alg, Some(s))?,
            };
            (ek_result, None)
        };

    // Calculate the SHA-256 hash of the public key in PEM format
    let ek_hash = hash_ek::hash_ek_pubkey(ek_result.public.clone())?;

    // Replace the uuid with the actual EK hash if the option was set.
    // We cannot do that when the configuration is loaded initially,
    // because only have later access to the the TPM.
    config.uuid = match config.uuid.as_ref() {
        "hash_ek" => ek_hash.clone(),
        s => s.to_string(),
    };

    let agent_uuid = config.uuid.clone();

    // Try to load persistent Agent data
    let old_ak = match config.agent_data_path.as_ref() {
        "" => {
            info!("Agent Data path not set in the configuration file");
            None
        }
        path => {
            let path = Path::new(&path);
            if path.exists() {
                match AgentData::load(path) {
                    Ok(data) => {
                        match data.valid(tpm_hash_alg, tpm_signing_alg, ek_hash.as_bytes()) {
                            true => {
                                let ak_result = data.get_ak()?;
                                match ctx.load_ak(ek_result.key_handle, &ak_result) {
                                    Ok(ak_handle) => {
                                        info!("Loaded old AK key from {}", path.display());
                                        Some((ak_handle, ak_result))
                                    }
                                    Err(e) => {
                                        warn!(
                                            "Loading old AK key from {} failed: {}",
                                            path.display(),
                                            e
                                        );
                                        None
                                    }
                                }
                            }
                            false => {
                                warn!(
                                    "Not using old {} because it is not valid with current configuration",
                                    path.display()
                                );
                                None
                            }
                        }
                    }
                    Err(e) => {
                        warn!("Could not load agent data: {e:?}");
                        None
                    }
                }
            } else {
                info!("Agent Data not found in: {}", path.display());
                None
            }
        }
    };

    // Use old AK or generate a new one and update the AgentData
    let (ak_handle, ak, persistent_handle) = match old_ak {
        Some((ak_handle, ak)) => {
            // Check if we have a persistent handle stored
            let old_data = match config.agent_data_path.as_ref() {
                "" => None,
                path => match AgentData::load(Path::new(&path)) {
                    Ok(data) => Some(data),
                    Err(_) => None,
                },
            };
            let persistent = old_data.and_then(|d| d.ak_persistent_handle);
            // If we have a persistent handle, use it instead of the transient one
            (
                if let Some(ph) = persistent {
                    ctx.load_persistent_handle(ph)?
                } else {
                    ak_handle
                },
                ak,
                persistent,
            )
        }
        None => {
            // If USE_TPM2_QUOTE_DIRECT is set and we have a persistent EK, create AK using tpm2 createak
            let (ak_handle, new_ak, persistent_handle) = if std::env::var("USE_TPM2_QUOTE_DIRECT")
                .is_ok()
                && ek_persistent_handle.is_some()
            {
                use std::fs;
                use std::path::PathBuf;
                use std::process::Command;

                let ek_persistent_handle_val = ek_persistent_handle.unwrap();

                // Create AK context file path in agent data directory
                let agent_data_dir = match config.agent_data_path.as_ref() {
                    "" => PathBuf::from("/tmp/keylime-agent"),
                    path => PathBuf::from(path)
                        .parent()
                        .unwrap_or(PathBuf::from("/tmp/keylime-agent").as_path())
                        .to_path_buf(),
                };
                fs::create_dir_all(&agent_data_dir).map_err(|e| {
                    Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                        "Failed to create agent data directory: {}",
                        e
                    )))
                })?;

                let ak_context_path = agent_data_dir.join("ak.ctx");
                let ak_context_str = ak_context_path.to_str().ok_or_else(|| {
                    Error::Tpm(tpm::TpmError::HexDecodeError(
                        "Invalid AK context file path".to_string(),
                    ))
                })?;

                let tcti =
                    std::env::var("TCTI").unwrap_or_else(|_| "device:/dev/tpmrm0".to_string());

                let hash_alg_str = match tpm_hash_alg {
                    keylime::algorithms::HashAlgorithm::Sha256 => "sha256",
                    keylime::algorithms::HashAlgorithm::Sha1 => "sha1",
                    keylime::algorithms::HashAlgorithm::Sha384 => "sha384",
                    keylime::algorithms::HashAlgorithm::Sha512 => "sha512",
                    _ => "sha256",
                };

                let sign_alg_str = match tpm_signing_alg {
                    keylime::algorithms::SignAlgorithm::RsaSsa => "rsassa",
                    keylime::algorithms::SignAlgorithm::RsaPss => "rsapss",
                    _ => "rsassa",
                };

                info!(
                    "Creating AK using tpm2 createak with persistent EK handle {:#x}",
                    ek_persistent_handle_val
                );

                // Flush transient handles first
                let _ = Command::new("tpm2")
                    .arg("flushcontext")
                    .arg("-t")
                    .env("TCTI", &tcti)
                    .output();

                // Create AK using tpm2 createak with persistent EK handle
                let createak_output = Command::new("tpm2")
                    .arg("createak")
                    .env("TCTI", &tcti)
                    .arg("-C")
                    .arg(&format!("{:#x}", ek_persistent_handle_val))
                    .arg("-c")
                    .arg(ak_context_str)
                    .arg("--hash-alg")
                    .arg(hash_alg_str)
                    .arg("--signing-alg")
                    .arg(sign_alg_str)
                    .arg("--key-alg")
                    .arg("rsa")
                    .output()
                    .map_err(|e| {
                        Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                            "Failed to execute tpm2 createak: {}",
                            e
                        )))
                    })?;

                if !createak_output.status.success() {
                    let stderr = String::from_utf8_lossy(&createak_output.stderr);
                    warn!(
                        "tpm2 createak failed: {}. Falling back to TSS library create_ak.",
                        stderr
                    );
                    // Fall back to TSS library method
                    let new_ak = ctx.create_ak(
                        ek_result.key_handle,
                        tpm_hash_alg,
                        tpm_encryption_alg,
                        tpm_signing_alg,
                    )?;
                    let ak_handle = ctx.load_ak(ek_result.key_handle, &new_ak)?;
                    (ak_handle, new_ak, None)
                } else {
                    info!(
                        "AK created successfully with context file: {}",
                        ak_context_str
                    );

                    // Persist AK to persistent handle
                    let persistent_handle_val = 0x8101000A;
                    let evict_output = Command::new("tpm2")
                        .arg("evictcontrol")
                        .env("TCTI", &tcti)
                        .arg("-C")
                        .arg("o")
                        .arg("-c")
                        .arg(ak_context_str)
                        .arg(&format!("{:#x}", persistent_handle_val))
                        .output()
                        .map_err(|e| {
                            Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                                "Failed to execute tpm2 evictcontrol for AK: {}",
                                e
                            )))
                        })?;

                    if !evict_output.status.success() {
                        let stderr = String::from_utf8_lossy(&evict_output.stderr);
                        warn!(
                            "Failed to persist AK: {}. Falling back to TSS library.",
                            stderr
                        );
                        let new_ak = ctx.create_ak(
                            ek_result.key_handle,
                            tpm_hash_alg,
                            tpm_encryption_alg,
                            tpm_signing_alg,
                        )?;
                        let ak_handle = ctx.load_ak(ek_result.key_handle, &new_ak)?;
                        (ak_handle, new_ak, None)
                    } else {
                        info!("AK persisted to handle {:#x}", persistent_handle_val);

                        // Set environment variable with AK context file path for quote function
                        std::env::set_var("KEYLIME_AGENT_AK_CONTEXT", ak_context_str);
                        info!("Set KEYLIME_AGENT_AK_CONTEXT={}", ak_context_str);

                        // Load the persistent AK handle (for AgentData, but quote will use context file)
                        let ak_persistent_handle_tpm =
                            ctx.load_persistent_handle(persistent_handle_val)?;

                        // Read public key from persistent handle to create AKResult
                        let (ak_public, _, _) = ctx
                            .read_public_from_handle(ak_persistent_handle_tpm)
                            .map_err(|e| Error::Tpm(e))?;

                        // Create AKResult from the public key
                        // The private key is in the context file, but we need a minimal one for AgentData
                        use tss_esapi::structures::Private;
                        let ak_private = Private::try_from(vec![0u8; 1]).unwrap(); // Dummy private key - real one is in ak.ctx

                        let new_ak = tpm::AKResult {
                            public: ak_public,
                            private: ak_private,
                        };

                        (
                            ak_persistent_handle_tpm,
                            new_ak,
                            Some(persistent_handle_val),
                        )
                    }
                }
            } else {
                // Use TSS library method (standard)
                let new_ak = ctx.create_ak(
                    ek_result.key_handle,
                    tpm_hash_alg,
                    tpm_encryption_alg,
                    tpm_signing_alg,
                )?;
                let ak_handle = ctx.load_ak(ek_result.key_handle, &new_ak)?;

                // If USE_TPM2_QUOTE_DIRECT is set but EK is not persistent, try to save the AK context and persist it
                let persistent_handle = if std::env::var("USE_TPM2_QUOTE_DIRECT").is_ok() {
                    use std::fs;
                    use std::path::PathBuf;
                    use std::process::Command;

                    // Create AK context file path in agent data directory
                    let agent_data_dir = match config.agent_data_path.as_ref() {
                        "" => PathBuf::from("/tmp/keylime-agent"),
                        path => PathBuf::from(path)
                            .parent()
                            .unwrap_or(PathBuf::from("/tmp/keylime-agent").as_path())
                            .to_path_buf(),
                    };
                    fs::create_dir_all(&agent_data_dir).map_err(|e| {
                        Error::Tpm(tpm::TpmError::HexDecodeError(format!(
                            "Failed to create agent data directory: {}",
                            e
                        )))
                    })?;

                    let ak_context_path = agent_data_dir.join("ak.ctx");
                    let ak_context_str = ak_context_path.to_str().ok_or_else(|| {
                        Error::Tpm(tpm::TpmError::HexDecodeError(
                            "Invalid context file path".to_string(),
                        ))
                    })?;

                    let tcti =
                        std::env::var("TCTI").unwrap_or_else(|_| "device:/dev/tpmrm0".to_string());
                    let ak_handle_str = format!("{:#x}", u32::from(ak_handle));

                    info!(
                        "Attempting to save AK context for tpm2_quote direct mode (handle: {})",
                        ak_handle_str
                    );

                    // Try to save the context using TSS library's context_save, then serialize it
                    // The context needs to be in TPM2B_CONTEXT format for tpm2-tools
                    match ctx.save_ak_context_to_file(ak_handle, ak_context_str) {
                        Ok(_) => {
                            info!("Saved AK context to file: {}", ak_context_str);

                            // Now try to persist it using the context file
                            let persistent_handle_val = 0x8101000A;
                            match ctx
                                .persist_ak_from_context_file(ak_context_str, persistent_handle_val)
                            {
                                Ok(_) => {
                                    info!(
                                        "AK persisted to handle {:#x} using saved context file",
                                        persistent_handle_val
                                    );
                                    Some(persistent_handle_val)
                                }
                                Err(e) => {
                                    warn!("Failed to persist AK from context file: {}. Will use transient handle.", e);
                                    None
                                }
                            }
                        }
                        Err(e) => {
                            warn!(
                                "Failed to save AK context: {}. Cannot use tpm2_quote direct mode.",
                                e
                            );
                            None
                        }
                    }
                } else {
                    None
                };

                (
                    if let Some(ph) = persistent_handle {
                        // Use persistent handle if available
                        ctx.load_persistent_handle(ph)?
                    } else {
                        ak_handle
                    },
                    new_ak,
                    persistent_handle,
                )
            };

            (ak_handle, new_ak, persistent_handle)
        }
    };

    // Store new AgentData with persistent handle
    let mut agent_data_new =
        AgentData::create(tpm_hash_alg, tpm_signing_alg, &ak, ek_hash.as_bytes())?;
    agent_data_new.ak_persistent_handle = persistent_handle;

    match config.agent_data_path.as_ref() {
        "" => info!("Agent Data not stored"),
        path => agent_data_new.store(Path::new(&path))?,
    }

    info!("Agent UUID: {agent_uuid}");

    // If using IAK/IDevID is enabled, obtain IAK/IDevID and respective certificates
    let mut device_id = if config.enable_iak_idevid {
        let mut builder = DeviceIDBuilder::new()
            .iak_handle(&config.iak_handle)
            .iak_password(&config.iak_password)
            .iak_default_template(config::DEFAULT_IAK_IDEVID_TEMPLATE)
            .iak_template(&config.iak_idevid_template)
            .iak_asym_alg(&config.iak_idevid_asymmetric_alg)
            .iak_hash_alg(&config.iak_idevid_name_alg)
            .idevid_handle(&config.idevid_handle)
            .idevid_cert_path(&config.idevid_cert)
            .idevid_password(&config.idevid_password)
            .idevid_default_template(config::DEFAULT_IAK_IDEVID_TEMPLATE)
            .idevid_template(&config.iak_idevid_template)
            .idevid_asym_alg(&config.iak_idevid_asymmetric_alg)
            .idevid_hash_alg(&config.iak_idevid_name_alg);

        if !&config.iak_cert.is_empty() {
            builder = builder.iak_cert_path(&config.iak_cert);
        }

        if !&config.idevid_cert.is_empty() {
            builder = builder.idevid_cert_path(&config.idevid_cert);
        }

        Some(builder.build(&mut ctx)?)
    } else {
        None
    };

    let (attest, signature) = if let Some(dev_id) = &mut device_id {
        let qualifying_data = Data::try_from(agent_uuid.as_bytes())?;
        let (attest, signature) = dev_id.certify(qualifying_data, ak_handle, &mut ctx)?;

        info!("AK certified with IAK.");

        // // For debugging certify(), the following checks the generated signature
        // let max_b = MaxBuffer::try_from(attest.clone().marshall()?)?;
        // let (hashed_attest, _) = ctx.inner.hash(max_b, HashingAlgorithm::Sha256, Hierarchy::Endorsement,)?;
        // println!("{:?}", hashed_attest);
        // println!("{:?}", signature);
        // println!("{:?}", ctx.inner.verify_signature(iak.as_ref().unwrap().handle, hashed_attest, signature.clone())?); //#[allow_ci]
        (Some(attest), Some(signature))
    } else {
        (None, None)
    };

    // Load or generate RSA key pair for secure transmission of u, v keys.
    // The u, v keys are two halves of the key used to decrypt the workload after
    // the Identity and Integrity Quotes sent by the agent are validated
    // by the Tenant and Cloud Verifier, respectively.
    // The payload key is always persistent, stored at the configured path.
    let key_path = Path::new(&config.payload_key);
    let (payload_pub_key, payload_priv_key) = crypto::load_or_generate_key(
        key_path,
        Some(config.payload_key_password.as_ref()),
        keylime::algorithms::EncryptionAlgorithm::Rsa2048,
        true, // Validate that loaded keys are RSA 2048
    )
    .map_err(|e| {
        error!(
            "Failed to load or generate payload key from {}: {e}",
            key_path.display()
        );
        Error::Configuration(config::KeylimeConfigError::Generic(format!(
            "Failed to load or generate payload key from {}: {e}",
            key_path.display()
        )))
    })?;

    if config.startup_quote_test {
        match run_startup_quote_self_test(
            &mut ctx,
            tpm_hash_alg,
            tpm_signing_alg,
            ak_handle,
            &payload_pub_key,
        ) {
            Ok(_) => info!("Startup TPM quote self-test completed successfully"),
            Err(e) => {
                warn!("Startup TPM quote self-test failed (continuing): {e}")
            }
        }
    }

    // Load or generate mTLS key pair (separate from payload keys)
    // The mTLS key is always persistent, stored at the configured path.
    let key_path = Path::new(&config.server_key);
    let (mtls_pub, mtls_priv) = crypto::load_or_generate_key(
        key_path,
        Some(config.server_key_password.as_ref()),
        keylime::algorithms::EncryptionAlgorithm::Rsa2048,
        false, // Don't validate algorithm for mTLS keys (for backward compatibility)
    )?;

    let cert: X509;
    let mtls_cert;
    let ssl_context;
    if config.enable_agent_mtls {
        let contact_ips = vec![config.contact_ip.as_str()];
        cert = match config.server_cert.as_ref() {
            "" => {
                debug!("The server_cert option was not set in the configuration file");

                crypto::x509::CertificateBuilder::new()
                    .private_key(&mtls_priv)
                    .common_name(&agent_uuid)
                    .add_ips(contact_ips)
                    .build()?
            }
            path => {
                let cert_path = Path::new(&path);
                if cert_path.exists() {
                    debug!(
                        "Loading existing mTLS certificate from {}",
                        cert_path.display()
                    );
                    crypto::load_x509_pem(cert_path)?
                } else {
                    debug!("Generating new mTLS certificate");
                    let cert = crypto::x509::CertificateBuilder::new()
                        .private_key(&mtls_priv)
                        .common_name(&agent_uuid)
                        .add_ips(contact_ips)
                        .build()?;
                    // Write the generated certificate
                    crypto::write_x509(&cert, cert_path)?;
                    cert
                }
            }
        };

        let trusted_client_ca = match config.trusted_client_ca.as_ref() {
            "" => {
                error!("Agent mTLS is enabled, but trusted_client_ca option was not provided");
                return Err(Error::Configuration(config::KeylimeConfigError::Generic(
                    "Agent mTLS is enabled, but trusted_client_ca option was not provided"
                        .to_string(),
                )));
            }
            l => l,
        };

        // The trusted_client_ca config option is a list, parse to obtain a vector
        let certs_list = parse_list(trusted_client_ca)?;
        if certs_list.is_empty() {
            error!("Trusted client CA certificate list is empty: could not load any certificate");
            return Err(Error::Configuration(config::KeylimeConfigError::Generic(
                "Trusted client CA certificate list is empty: could not load any certificate"
                    .to_string(),
            )));
        }

        let keylime_ca_certs =
            match crypto::load_x509_cert_list(certs_list.iter().map(Path::new).collect()) {
                Ok(t) => Ok(t),
                Err(e) => {
                    error!("Failed to load trusted CA certificates: {e:?}");
                    Err(e)
                }
            }?;

        mtls_cert = Some(cert.clone());
        ssl_context = Some(crypto::generate_tls_context(
            &cert,
            &mtls_priv,
            keylime_ca_certs,
        )?);
    } else {
        mtls_cert = None;
        ssl_context = None;
        warn!("mTLS disabled, Tenant and Verifier will reach out to agent via HTTP");
    }

    let ac = AgentRegistrationConfig {
        contact_ip: config.contact_ip.clone(),
        contact_port: config.contact_port,
        registrar_ip: config.registrar_ip.clone(),
        registrar_port: config.registrar_port,
        enable_iak_idevid: config.enable_iak_idevid,
        ek_handle: config.ek_handle.clone(),
    };

    let aa = AgentRegistration {
        ak,
        ek_result,
        api_versions: api_versions.clone(),
        agent_registration_config: ac,
        agent_uuid: agent_uuid.clone(),
        mtls_cert,
        device_id,
        attest,
        signature,
        ak_handle,
        retry_config: None,
    };
    match keylime::agent_registration::register_agent(aa, &mut ctx).await {
        Ok(()) => (),
        Err(e) => {
            error!("Failed to register agent: {e:?}");
        }
    }

    let (mut payload_tx, mut payload_rx) = mpsc::channel::<payloads::PayloadMessage>(1);
    let (mut keys_tx, mut keys_rx) = mpsc::channel::<(
        keys_handler::KeyMessage,
        Option<oneshot::Sender<keys_handler::SymmKeyMessage>>,
    )>(1);
    let (mut revocation_tx, mut revocation_rx) = mpsc::channel::<revocation::RevocationMessage>(1);

    #[cfg(feature = "with-zmq")]
    let (mut zmq_tx, mut zmq_rx) = mpsc::channel::<revocation::ZmqMessage>(1);

    let revocation_cert = match config.revocation_cert.as_ref() {
        "" => {
            error!("No revocation certificate set in 'revocation_cert' option");
            return Err(Error::Configuration(config::KeylimeConfigError::Generic(
                "No revocation certificate set in 'revocation_cert' option".to_string(),
            )));
        }
        s => PathBuf::from(s),
    };

    let revocation_actions_dir = config.revocation_actions_dir.clone();

    let revocation_actions = match config.revocation_actions.as_ref() {
        "" => None,
        s => Some(s.to_string()),
    };

    let allow_payload_revocation_actions = config.allow_payload_revocation_actions;

    let revocation_task = rt::spawn(revocation::worker(
        revocation_rx,
        revocation_cert,
        revocation_actions_dir,
        revocation_actions,
        allow_payload_revocation_actions,
        work_dir.clone(),
        mount.clone(),
    ))
    .map_err(Error::from);

    let quotedata = web::Data::new(QuoteData {
        agent_uuid: agent_uuid.clone(),
        ak_handle,
        allow_payload_revocation_actions,
        api_versions: api_versions.clone(),
        enc_alg: tpm_encryption_alg,
        hash_alg: tpm_hash_alg,
        ima_ml: Mutex::new(MeasurementList::new()),
        ima_ml_file,
        keys_tx: keys_tx.clone(),
        measuredboot_ml_file,
        payload_tx: payload_tx.clone(),
        payload_priv_key,
        payload_pub_key,
        priv_key: mtls_priv,
        pub_key: mtls_pub,
        revocation_tx: revocation_tx.clone(),
        secure_mount: PathBuf::from(&mount),
        secure_size,
        sign_alg: tpm_signing_alg,
        tpmcontext: Mutex::new(ctx),
        work_dir,
        unified_identity_enabled: config.unified_identity_enabled,
        delegated_cert_enabled: config.delegated_cert_enabled,
        delegated_cert_allowed_ips: config.delegated_cert_allowed_ips.clone(),
        delegated_cert_rate_limit: config.delegated_cert_rate_limit,
    });

    let actix_server = HttpServer::new(move || {
        let mut app = App::new()
            .wrap(
                middleware::ErrorHandlers::new()
                    .handler(http::StatusCode::NOT_FOUND, errors_handler::wrap_404),
            )
            .wrap(middleware::Logger::new("%r from %a result %s (took %D ms)"))
            .wrap_fn(|req, srv| {
                info!(
                    "{} invoked from {:?} with uri {}",
                    req.head().method,
                    req.connection_info().peer_addr().unwrap(), //#[allow_ci]
                    req.uri()
                );
                srv.call(req)
            })
            .app_data(quotedata.clone())
            .app_data(web::JsonConfig::default().error_handler(errors_handler::json_parser_error))
            .app_data(web::QueryConfig::default().error_handler(errors_handler::query_parser_error))
            .app_data(web::PathConfig::default().error_handler(errors_handler::path_parser_error));

        for version in &api_versions {
            // This should never fail, thus unwrap should never panic
            let scope = api::get_api_scope(version, config.unified_identity_enabled).unwrap(); //#[allow_ci]
            app = app.service(scope);
        }

        app.service(web::resource("/version").route(web::get().to(api::version)))
            .service(
                web::resource(r"/v{major:\d+}.{minor:\d+}{tail}*")
                    .to(errors_handler::version_not_supported),
            )
            .default_service(web::to(errors_handler::app_default))
    })
    // Disable default signal handlers.  See:
    // https://github.com/actix/actix-web/issues/2739
    // for details.
    .disable_signals();

    let server;

    // Try to parse as an IP address
    let ip = match config.ip.parse::<IpAddr>() {
        Ok(ip_addr) => {
            // Add bracket if IPv6, otherwise use as it is
            if ip_addr.is_ipv6() {
                format!("[{ip_addr}]")
            } else {
                ip_addr.to_string()
            }
        }
        Err(_) => {
            // If the address was not an IP address, treat as a hostname
            config.ip.to_string()
        }
    };

    let port = config.port;

    // Unified-Identity: Support UDS socket for delegated certification
    // Note: Actix-web 4.x doesn't natively support Unix domain sockets.
    // For now, we'll use HTTP over localhost. UDS support can be added later
    // using a custom server implementation or by upgrading to a version that supports it.
    // The endpoint will be accessible via HTTP at http://127.0.0.1:{port}/v2.2/delegated_certification/certify_app_key

    // Unified-Identity: Enable mTLS for verifier communication (Gap #2 fix)
    // Use HTTPS with mTLS when enabled, fall back to HTTP only if mTLS is disabled
    if config.enable_agent_mtls && ssl_context.is_some() {
        server = actix_server
            .bind_openssl(
                format!("{ip}:{port}"),
                ssl_context.unwrap(), //#[allow_ci]
            )?
            .run();
        info!("Listening on https://{ip}:{port}");
        info!("Unified-Identity: Delegated certification endpoint available at https://{ip}:{port}/v2.2/delegated_certification/certify_app_key");
    } else {
        warn!("mTLS disabled or SSL context unavailable, using HTTP (insecure)");
        server = actix_server.bind(format!("{ip}:{port}"))?.run();
        info!("Listening on http://{ip}:{port}");
        info!("Unified-Identity: Delegated certification endpoint available at http://{ip}:{port}/v2.2/delegated_certification/certify_app_key");
    }

    let server_handle = server.handle();
    let server_task = rt::spawn(server).map_err(Error::from);

    // Only run payload scripts if mTLS is enabled or 'enable_insecure_payload' option is set
    let run_payload = config.enable_agent_mtls || config.enable_insecure_payload;

    let payload_task = rt::spawn(payloads::worker(
        config.clone(),
        PathBuf::from(&mount),
        payload_rx,
        revocation_tx.clone(),
        #[cfg(feature = "with-zmq")]
        zmq_tx.clone(),
    ))
    .map_err(Error::from);

    let key_task = rt::spawn(keys_handler::worker(
        run_payload,
        agent_uuid,
        keys_rx,
        payload_tx.clone(),
    ))
    .map_err(Error::from);

    // If with-zmq feature is enabled, run the service listening for ZeroMQ messages
    #[cfg(feature = "with-zmq")]
    let zmq_task = if config.enable_revocation_notifications {
        warn!("The support for ZeroMQ revocation notifications is deprecated and will be removed on next major release");

        let zmq_ip = config.revocation_notification_ip;
        let zmq_port = config.revocation_notification_port;

        rt::spawn(revocation::zmq_worker(
            zmq_rx,
            revocation_tx.clone(),
            zmq_ip,
            zmq_port,
        ))
        .map_err(Error::from)
    } else {
        rt::spawn(ok(())).map_err(Error::from)
    };

    let shutdown_task = rt::spawn(async move {
        let mut sigint = signal(SignalKind::interrupt()).unwrap(); //#[allow_ci]
        let mut sigterm = signal(SignalKind::terminate()).unwrap(); //#[allow_ci]

        tokio::select! {
            _ = sigint.recv() => {
                debug!("Received SIGINT signal");
            },
            _ = sigterm.recv() => {
                debug!("Received SIGTERM signal");
            },
        }

        info!("Shutting down keylime agent");

        // Shutdown tasks
        let server_stop = server_handle.stop(true);
        payload_tx.send(payloads::PayloadMessage::Shutdown);
        keys_tx.send((keys_handler::KeyMessage::Shutdown, None));

        #[cfg(feature = "with-zmq")]
        zmq_tx.send(revocation::ZmqMessage::Shutdown);

        revocation_tx.send(revocation::RevocationMessage::Shutdown);

        // Await tasks shutdown
        server_stop.await;
    })
    .map_err(Error::from);

    // If with-zmq feature is enabled, wait for the service listening for ZeroMQ messages
    #[cfg(feature = "with-zmq")]
    try_join!(zmq_task)?;

    let result = try_join!(
        server_task,
        payload_task,
        key_task,
        revocation_task,
        shutdown_task,
    );
    result.map(|_| ())
}

/*
 * Input: file path
 * Output: file content
 *
 * Helper function to help the keylime agent read file and get the file
 * content. It is not from the original python version. Because rust needs
 * to handle error in result, it is good to keep this function separate from
 * the main function.
 */
fn read_in_file(path: String) -> std::io::Result<String> {
    let file = fs::File::open(path)?;
    let mut buf_reader = BufReader::new(file);
    let mut contents = String::new();
    let _ = buf_reader.read_to_string(&mut contents)?;
    Ok(contents)
}

fn run_startup_quote_self_test(
    ctx: &mut tpm::Context<'_>,
    hash_alg: keylime::algorithms::HashAlgorithm,
    sign_alg: keylime::algorithms::SignAlgorithm,
    ak_handle: KeyHandle,
    payload_pub_key: &PKey<Public>,
) -> Result<()> {
    let nonce_bytes = Uuid::new_v4().as_bytes().to_vec();
    let nonce_hex = hex::encode(&nonce_bytes);
    info!(
        "Performing startup TPM quote self-test with nonce {}",
        nonce_hex
    );
    let start = Instant::now();
    let quote = ctx.quote(
        &nonce_bytes,
        0,
        payload_pub_key.as_ref(),
        ak_handle,
        hash_alg,
        sign_alg,
    )?;
    let elapsed = start.elapsed();
    info!(
        "Startup TPM quote self-test succeeded in {:?} ({} bytes)",
        elapsed,
        quote.len()
    );
    debug!(
        "Startup quote sample: {}...",
        &quote.chars().take(32).collect::<String>()
    );
    Ok(())
}

#[cfg(feature = "testing")]
#[cfg(test)]
mod testing {
    use super::*;
    use keylime::{
        config::{get_testing_config, AgentConfig},
        crypto::CryptoError,
        tpm::testing::lock_tests,
    };
    use std::sync::{Arc, Mutex, OnceLock};
    use thiserror::Error;
    use tokio::sync::{Mutex as AsyncMutex, MutexGuard as AsyncMutexGuard};

    #[derive(Error, Debug)]
    pub(crate) enum MainTestError {
        /// Algorithm error
        #[error("AlgorithmError")]
        Error(#[from] keylime::algorithms::AlgorithmError),

        /// Crypto error
        #[error("CryptoError")]
        CryptoError(#[from] CryptoError),

        /// CryptoTest error
        #[error("CryptoTestError")]
        CryptoTestError(#[from] crypto::testing::CryptoTestError),

        /// IO error
        #[error("IOError")]
        IoError(#[from] std::io::Error),

        /// OpenSSL error
        #[error("IOError")]
        OpenSSLError(#[from] openssl::error::ErrorStack),

        /// TPM error
        #[error("TPMError")]
        TPMError(#[from] tpm::TpmError),

        /// TSS esapi error
        #[error("TSSError")]
        TSSError(#[from] tss_esapi::Error),
    }

    impl Drop for QuoteData<'_> {
        /// Flush the created AK when dropping
        fn drop(&mut self) {
            self.tpmcontext
                .lock()
                .unwrap() //#[allow_ci]
                .flush_context(self.ak_handle.into());
        }
    }

    impl QuoteData<'_> {
        pub(crate) async fn fixture(
        ) -> std::result::Result<(Self, AsyncMutexGuard<'static, ()>), MainTestError> {
            let mutex = lock_tests().await;
            let work_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");

            let test_config = get_testing_config(&work_dir, None);
            let mut ctx = tpm::Context::new()?;

            let tpm_encryption_alg = keylime::algorithms::EncryptionAlgorithm::try_from(
                test_config.tpm_encryption_alg.as_str(),
            )?;

            let tpm_hash_alg =
                keylime::algorithms::HashAlgorithm::try_from(test_config.tpm_hash_alg.as_str())?;

            let tpm_signing_alg =
                keylime::algorithms::SignAlgorithm::try_from(test_config.tpm_signing_alg.as_str())?;

            // Gather EK and AK key values and certs
            let ek_result = ctx.create_ek(tpm_encryption_alg, None).unwrap(); //#[allow_ci]
            let ak_result = ctx
                .create_ak(
                    ek_result.key_handle,
                    tpm_hash_alg,
                    tpm_encryption_alg,
                    tpm_signing_alg,
                )
                .unwrap(); //#[allow_ci]
            let ak_handle = ctx.load_ak(ek_result.key_handle, &ak_result).unwrap(); //#[allow_ci]

            ctx.flush_context(ek_result.key_handle.into()).unwrap(); //#[allow_ci]

            let rsa_key_path = Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("test-data")
                .join("test-rsa.pem");

            let (mtls_pub, mtls_priv) = crypto::testing::rsa_import_pair(rsa_key_path.clone())?;

            // Generate ephemeral payload keys for testing
            debug!("Generating ephemeral RSA key pair for payload mechanism");
            let (payload_pub_key, payload_priv_key) = crypto::rsa_generate_pair(2048)?;

            let (mut payload_tx, mut payload_rx) = mpsc::channel::<payloads::PayloadMessage>(1);

            let (mut keys_tx, mut keys_rx) = mpsc::channel::<(
                keys_handler::KeyMessage,
                Option<oneshot::Sender<keys_handler::SymmKeyMessage>>,
            )>(1);

            let (mut revocation_tx, mut revocation_rx) =
                mpsc::channel::<revocation::RevocationMessage>(1);

            let revocation_cert = PathBuf::from(test_config.revocation_cert);

            let actions_dir = Some(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/actions/"));

            let secure_mount = work_dir.join("tmpfs-dev");

            let ima_ml_path = Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("test-data/ima/ascii_runtime_measurements");
            let ima_ml_file = match fs::File::open(ima_ml_path) {
                Ok(file) => Some(Mutex::new(file)),
                Err(err) => None,
            };

            // Allow setting the binary bios measurements log path when testing
            let mut measuredboot_ml_path = Path::new(&test_config.measuredboot_ml_path);
            let env_mb_path: String;
            #[cfg(feature = "testing")]
            if let Ok(v) = std::env::var("TPM_BINARY_MEASUREMENTS") {
                env_mb_path = v;
                measuredboot_ml_path = Path::new(&env_mb_path);
            }

            let measuredboot_ml_file = match fs::File::open(measuredboot_ml_path) {
                Ok(file) => Some(Mutex::new(file)),
                Err(err) => None,
            };

            let api_versions = config::SUPPORTED_API_VERSIONS
                .iter()
                .map(|&s| s.to_string())
                .collect::<Vec<String>>();

            Ok((
                QuoteData {
                    api_versions,
                    tpmcontext: Mutex::new(ctx),
                    payload_priv_key,
                    payload_pub_key,
                    priv_key: mtls_priv,
                    pub_key: mtls_pub,
                    ak_handle,
                    keys_tx,
                    payload_tx,
                    revocation_tx,
                    hash_alg: keylime::algorithms::HashAlgorithm::Sha256,
                    enc_alg: keylime::algorithms::EncryptionAlgorithm::Rsa2048,
                    sign_alg: keylime::algorithms::SignAlgorithm::RsaSsa,
                    agent_uuid: test_config.uuid,
                    allow_payload_revocation_actions: test_config.allow_payload_revocation_actions,
                    secure_size: test_config.secure_size,
                    work_dir,
                    ima_ml_file,
                    measuredboot_ml_file,
                    ima_ml: Mutex::new(MeasurementList::new()),
                    secure_mount,
                    unified_identity_enabled: test_config.unified_identity_enabled,
                },
                mutex,
            ))
        }
    }
}

// Unit Testing
#[cfg(test)]
mod tests {
    use super::*;

    fn init_logger() {
        pretty_env_logger::init();
        info!("Initialized logger for testing suite.");
    }

    #[test]
    fn test_read_in_file() {
        assert_eq!(
            read_in_file("test-data/test_input.txt".to_string()).expect("File doesn't exist"),
            String::from("Hello World!\n")
        );
    }
}
