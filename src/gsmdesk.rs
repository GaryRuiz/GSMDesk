//! GSMDesk branding and built-in server settings.
//!
//! Applied through the same settings maps that RustDesk's custom-client
//! config (`custom.txt`) fills, so the rest of the code base stays untouched
//! and upstream updates merge cleanly. Setting the app name to something other
//! than "RustDesk" also switches on upstream's custom-client behavior: UI texts
//! say "GSMDesk", the install dir and Windows service are named "GSMDesk", and
//! update checks against rustdesk.com are disabled.
//!
//! Server settings are read from environment variables at *build* time:
//! - `GSMDESK_SERVER`: ID/rendezvous server (hbbs), e.g. `remote.example.com`
//! - `GSMDESK_KEY`: public key of that server (content of `id_ed25519.pub`)
//! - `GSMDESK_RELAY`: relay server (hbbr), optional, defaults to the ID server
//! - `GSMDESK_API`: API server, optional (only used with RustDesk Server Pro)
//! - `GSMDESK_CONN_TYPE`: `incoming` (customer build, can only be controlled),
//!   `outgoing` (technician build, can only control) or unset for both
//!
//! Without `GSMDESK_SERVER` the client falls back to RustDesk's public
//! servers, which is only meant for development.

use hbb_common::config::{self, keys};
#[cfg(windows)]
use hbb_common::log;

pub const APP_NAME: &str = "GSMDesk";
#[cfg(target_os = "macos")]
const ORG: &str = "com.gsmdesk";

const SERVER: Option<&str> = option_env!("GSMDESK_SERVER");
const KEY: Option<&str> = option_env!("GSMDESK_KEY");
const RELAY: Option<&str> = option_env!("GSMDESK_RELAY");
const API: Option<&str> = option_env!("GSMDESK_API");
const CONN_TYPE: Option<&str> = option_env!("GSMDESK_CONN_TYPE");

/// Must run before anything reads the config, i.e. at the very start of
/// every entry point. It is idempotent, so calling it more than once is fine.
pub fn apply() {
    *config::APP_NAME.write().unwrap() = APP_NAME.to_owned();
    // `ORG` only exists on macOS, where it forms the bundle identifier.
    #[cfg(target_os = "macos")]
    {
        *config::ORG.write().unwrap() = ORG.to_owned();
    }

    // Override settings win over both the user's config and the defaults,
    // and the UI shows them as locked, so customers cannot point GSMDesk
    // at another server by mistake.
    let mut overwrite = config::OVERWRITE_SETTINGS.write().unwrap();
    for (key, value) in [
        (keys::OPTION_CUSTOM_RENDEZVOUS_SERVER, SERVER),
        (keys::OPTION_KEY, KEY),
        (keys::OPTION_RELAY_SERVER, RELAY),
        (keys::OPTION_API_SERVER, API),
    ] {
        if let Some(value) = value.map(str::trim).filter(|v| !v.is_empty()) {
            overwrite.insert(key.to_owned(), value.to_owned());
        }
    }
    drop(overwrite);

    // Access model: incoming connections must be accepted with a click, unless
    // the user has set a permanent password, which then lets a technician in
    // without approval. No one-time password: it changed after every session,
    // which made "remember password" useless on the technician's side.
    let mut settings = config::DEFAULT_SETTINGS.write().unwrap();
    settings.insert(keys::OPTION_APPROVE_MODE.to_owned(), "password-click".to_owned());
    settings.insert(
        keys::OPTION_VERIFICATION_METHOD.to_owned(),
        "use-permanent-password".to_owned(),
    );
    drop(settings);

    // Defaults for the technician; each one can still be changed in the UI.
    let mut display = config::DEFAULT_DISPLAY_SETTINGS.write().unwrap();
    // Fit the remote screen to the window, centered. Upstream's default is 1:1
    // with auto-scroll, which pans the view whenever the mouse nears an edge.
    display.insert(keys::OPTION_VIEW_STYLE.to_owned(), "adaptive".to_owned());
    display.insert(keys::OPTION_SCROLL_STYLE.to_owned(), "scrollbar".to_owned());
    drop(display);
    let mut local = config::DEFAULT_LOCAL_SETTINGS.write().unwrap();
    // One window per remote session instead of tabs, to work on several
    // customers side by side.
    local.insert(
        keys::OPTION_ENABLE_OPEN_NEW_CONNECTIONS_IN_TABS.to_owned(),
        "N".to_owned(),
    );
    // Direct (P2P) connections through UDP hole punching and IPv6. Upstream
    // turns them off for self-hosted servers because stock rustdesk-server
    // does not forward the fields they need; ours is patched to do so (see
    // gsmdesk/server/p2p.patch). Without the patch they fall back to relay.
    local.insert(keys::OPTION_ENABLE_UDP_PUNCH.to_owned(), "Y".to_owned());
    local.insert(keys::OPTION_ENABLE_IPV6_PUNCH.to_owned(), "Y".to_owned());
    drop(local);

    if let Some(conn_type) = CONN_TYPE.filter(|v| matches!(*v, "incoming" | "outgoing")) {
        config::HARD_SETTINGS
            .write()
            .unwrap()
            .insert("conn-type".to_owned(), conn_type.to_owned());
    }
}

/// Hardware ID used by the technician licence, computed exactly like GSM
/// Redirector's `HardwareId.Get()` so the same licence key (bound to one PC on
/// mundogsm.net) works in both programs: first 16 hex chars (upper case) of
/// SHA-256("<board serial>|<cpu id>"), falling back to the first disk serial.
/// Empty if it cannot be determined.
#[cfg(windows)]
pub fn hardware_id() -> String {
    static ID: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    ID.get_or_init(compute_hardware_id).clone()
}

#[cfg(not(windows))]
pub fn hardware_id() -> String {
    String::new()
}

/// Licence key saved by GSM Redirector's technician app for this Windows user,
/// so GSMDesk can activate itself without asking for it. Empty if not found.
///
/// GSM Redirector (ConfigStore.cs) keeps a JSON dictionary with `license_key`,
/// protected with DPAPI (CurrentUser scope, fixed entropy) and base64-encoded:
/// newer versions in %APPDATA%\GSMRedirectorTechnician\config.dat, v2.2 in
/// gsmredirector.dat next to GSMRedirectorTechnician.exe, which is looked for
/// next to a running copy, behind shortcuts and in the usual folders.
#[cfg(windows)]
pub fn redirector_license_key() -> String {
    const SCRIPT: &str = r##"$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Security
$entropy = [Text.Encoding]::UTF8.GetBytes('GSMRedirectorTechnician.ConfigStore')
$files = @()
$files += Get-Item "$env:APPDATA\GSMRedirectorTechnician\config.dat"
$dirs = @()
$dirs += Get-CimInstance Win32_Process -Filter "Name='GSMRedirectorTechnician.exe'" | ForEach-Object { Split-Path $_.ExecutablePath }
$shell = New-Object -ComObject WScript.Shell
$lnkRoots = @([Environment]::GetFolderPath('Desktop'), "$env:PUBLIC\Desktop", "$env:APPDATA\Microsoft\Windows\Start Menu", "$env:ProgramData\Microsoft\Windows\Start Menu")
Get-ChildItem $lnkRoots -Filter *.lnk -Recurse -Depth 3 | ForEach-Object {
  $t = $shell.CreateShortcut($_.FullName).TargetPath
  if ($t -like '*GSMRedirectorTechnician*.exe') { $dirs += Split-Path $t }
}
$files += $dirs | Where-Object { $_ } | ForEach-Object { Get-Item (Join-Path $_ 'gsmredirector.dat') }
$searchRoots = @([Environment]::GetFolderPath('Desktop'), "$env:USERPROFILE\Downloads", [Environment]::GetFolderPath('MyDocuments'), "$env:ProgramFiles\GSM Redirector")
$files += Get-ChildItem $searchRoots -Filter gsmredirector.dat -File -Recurse -Depth 3
foreach ($f in ($files | Where-Object { $_ } | Sort-Object LastWriteTime -Descending)) {
  $b = [Convert]::FromBase64String((Get-Content -LiteralPath $f.FullName -Raw).Trim())
  $d = [Security.Cryptography.ProtectedData]::Unprotect($b, $entropy, 'CurrentUser')
  if (-not $d) { continue }
  $j = [Text.Encoding]::UTF8.GetString($d) | ConvertFrom-Json
  if ($j.license_key) { 'K=' + $j.license_key; break }
}
"##;
    use hbb_common::base64::{engine::general_purpose::STANDARD, Engine as _};
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    // -EncodedCommand (UTF-16LE, base64) avoids any quoting problem.
    let utf16: Vec<u8> = SCRIPT.encode_utf16().flat_map(|u| u.to_le_bytes()).collect();
    let output = match std::process::Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-EncodedCommand",
            &STANDARD.encode(utf16),
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        Ok(output) => output,
        Err(err) => {
            log::error!("Failed to look for the GSM Redirector licence: {err}");
            return String::new();
        }
    };
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .find_map(|l| l.trim().strip_prefix("K="))
        .map(|k| k.trim().to_owned())
        .unwrap_or_default()
}

#[cfg(not(windows))]
pub fn redirector_license_key() -> String {
    String::new()
}

#[cfg(windows)]
fn compute_hardware_id() -> String {
    use hbb_common::sha2::{Digest, Sha256};
    use std::os::windows::process::CommandExt;

    // One PowerShell run for the three WMI values; each line is "<tag>=<value>"
    // with the first non-empty value, like the WmiQuery helper in C#.
    const SCRIPT: &str = "$ErrorActionPreference='SilentlyContinue';\
        function q($c,$p){ Get-WmiObject $c | ForEach-Object { \"$($_.$p)\".Trim() } \
        | Where-Object { $_ } | Select-Object -First 1 };\
        'B=' + (q Win32_BaseBoard SerialNumber);\
        'C=' + (q Win32_Processor ProcessorId);\
        'D=' + (q Win32_DiskDrive SerialNumber)";
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let output = match std::process::Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", SCRIPT])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        Ok(output) => output,
        Err(err) => {
            log::error!("Failed to query the hardware ID: {err}");
            return String::new();
        }
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let value = |tag: &str| {
        text.lines()
            .find_map(|l| l.trim().strip_prefix(tag))
            .map(|v| v.trim().to_owned())
            .unwrap_or_default()
    };

    let mut parts = Vec::new();
    let board = value("B=");
    if !board.is_empty()
        && !board.eq_ignore_ascii_case("To be filled by O.E.M.")
        && !board.eq_ignore_ascii_case("Default string")
    {
        parts.push(board);
    }
    let cpu = value("C=");
    if !cpu.is_empty() {
        parts.push(cpu);
    }
    if parts.is_empty() {
        let disk = value("D=");
        if !disk.is_empty() {
            parts.push(disk);
        }
    }
    if parts.is_empty() {
        log::error!("Could not determine the hardware ID");
        return String::new();
    }
    let digest = Sha256::digest(parts.join("|").as_bytes());
    digest.iter().take(8).map(|b| format!("{b:02X}")).collect()
}
