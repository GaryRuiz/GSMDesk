//! GSMDesk: finds, downloads and verifies new versions.
//!
//! Each release carries a manifest signed with a private key kept offline on the
//! publisher's PC (see gsmdesk/README.md). A file only reaches the installer if
//! its SHA-256 matches a correctly signed manifest, so whoever takes over the
//! download host still cannot push a fake program to the PCs running GSMDesk.

use crate::hbbs_http::create_http_client_with_url;
use hbb_common::{bail, log, sodiumoxide::crypto::sign, ResultType};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::Mutex,
    time::Duration,
};

/// Keep equal to the `+N` of `version` in flutter/pubspec.yaml.
pub const BUILD: u64 = 69;

const MANIFEST_URL: &str =
    "https://github.com/GaryRuiz/GSMDesk/releases/latest/download/gsmdesk-update.bin";
const PUBLIC_KEY: &str = "d+YNZe7mRgBV+3mCbflroQ2qIrMv6RxqJPq3YesoNX4=";
const CHECK_TIMEOUT: Duration = Duration::from_secs(30);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(30 * 60);

#[derive(Default)]
struct State {
    status: &'static str,
    version: String,
    notes: String,
    downloaded: u64,
    total: u64,
    file: Option<(PathBuf, String)>,
}

lazy_static::lazy_static! {
    static ref STATE: Mutex<State> = Default::default();
}

/// Checks for a new version and, if there is one, downloads it.
pub fn start() {
    {
        let mut state = STATE.lock().unwrap();
        if matches!(state.status, "checking" | "downloading" | "ready") {
            return;
        }
        state.status = "checking";
    }
    std::thread::spawn(|| {
        if let Err(e) = check_and_download() {
            log::warn!("GSMDesk update: {}", e);
            STATE.lock().unwrap().status = "error";
        }
    });
}

pub fn state_json() -> String {
    let state = STATE.lock().unwrap();
    serde_json::json!({
        "status": state.status,
        "version": state.version,
        "notes": state.notes,
        "downloaded": state.downloaded,
        "total": state.total,
    })
    .to_string()
}

/// The downloaded file, verified again right before it is used.
pub fn verified_file() -> ResultType<String> {
    let Some((path, sha256)) = STATE.lock().unwrap().file.clone() else {
        bail!("No update has been downloaded");
    };
    if sha256_of_file(&path)? != sha256 {
        STATE.lock().unwrap().status = "error";
        fs::remove_file(&path).ok();
        bail!("The downloaded update has changed");
    }
    match path.to_str() {
        Some(p) => Ok(p.to_owned()),
        None => bail!("Invalid update path"),
    }
}

#[cfg(target_os = "windows")]
pub fn install() -> ResultType<()> {
    crate::platform::update_to(&verified_file()?)
}

fn check_and_download() -> ResultType<()> {
    let client = create_http_client_with_url(MANIFEST_URL);
    let response = client.get(MANIFEST_URL).timeout(CHECK_TIMEOUT).send()?;
    if !response.status().is_success() {
        // Nothing has been published yet.
        STATE.lock().unwrap().status = "none";
        return Ok(());
    }
    let manifest = verify_manifest(&response.bytes()?)?;
    let build = manifest["build"].as_u64().unwrap_or(0);
    let Some(platform) = platform_key() else {
        STATE.lock().unwrap().status = "none";
        return Ok(());
    };
    if build <= BUILD {
        STATE.lock().unwrap().status = "none";
        return Ok(());
    }
    let entry = &manifest["files"][platform];
    let (Some(url), Some(sha256)) = (entry["url"].as_str(), entry["sha256"].as_str()) else {
        bail!("The manifest has no file for {}", platform);
    };
    let sha256 = sha256.to_lowercase();
    {
        let mut state = STATE.lock().unwrap();
        state.version = manifest["version"].as_str().unwrap_or_default().to_owned();
        state.notes = manifest["notes"].as_str().unwrap_or_default().to_owned();
        state.downloaded = 0;
        state.total = entry["size"].as_u64().unwrap_or(0);
        state.status = "downloading";
    }
    let path = update_file_path()?;
    if sha256_of_file(&path).ok().as_deref() != Some(sha256.as_str()) {
        download(url, &path, &sha256)?;
    }
    let mut state = STATE.lock().unwrap();
    state.file = Some((path, sha256));
    state.status = "ready";
    Ok(())
}

fn verify_manifest(signed: &[u8]) -> ResultType<serde_json::Value> {
    let Some(key) = crate::common::get_rs_pk(PUBLIC_KEY) else {
        bail!("Invalid update public key");
    };
    let Ok(manifest) = sign::verify(signed, &key) else {
        bail!("The update manifest has a wrong signature");
    };
    Ok(serde_json::from_slice(&manifest)?)
}

fn download(url: &str, path: &Path, sha256: &str) -> ResultType<()> {
    let client = create_http_client_with_url(url);
    let mut response = client.get(url).timeout(DOWNLOAD_TIMEOUT).send()?;
    if !response.status().is_success() {
        bail!("Failed to download the update: {}", response.status());
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let part = path.with_extension("part");
    let mut file = fs::File::create(&part)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 256 * 1024];
    loop {
        let n = response.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        file.write_all(&buffer[..n])?;
        hasher.update(&buffer[..n]);
        STATE.lock().unwrap().downloaded += n as u64;
    }
    file.flush()?;
    drop(file);
    if to_hex(&hasher.finalize()) != sha256 {
        fs::remove_file(&part).ok();
        bail!("The downloaded update does not match the signed manifest");
    }
    fs::rename(&part, path)?;
    Ok(())
}

fn sha256_of_file(path: &Path) -> ResultType<String> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 256 * 1024];
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
    }
    Ok(to_hex(&hasher.finalize()))
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn platform_key() -> Option<&'static str> {
    if cfg!(target_os = "windows") {
        Some("windows-x64")
    } else if cfg!(all(target_os = "android", target_arch = "aarch64")) {
        Some("android-arm64")
    } else if cfg!(all(target_os = "android", target_arch = "arm")) {
        Some("android-armv7")
    } else {
        None
    }
}

fn update_file_path() -> ResultType<PathBuf> {
    // The exe keeps its usual name: the portable launcher passes it on as the app name.
    #[cfg(target_os = "windows")]
    return Ok(std::env::temp_dir()
        .join("GSMDesk-update")
        .join("GSMDesk.exe"));
    #[cfg(target_os = "android")]
    return Ok(PathBuf::from(hbb_common::config::APP_DIR.read().unwrap().clone())
        .join("GSMDesk-update.apk"));
    #[cfg(not(any(target_os = "windows", target_os = "android")))]
    bail!("Updates are not supported on this platform");
}
