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
    // One window per remote session instead of tabs, to work on several
    // customers side by side.
    config::DEFAULT_LOCAL_SETTINGS.write().unwrap().insert(
        keys::OPTION_ENABLE_OPEN_NEW_CONNECTIONS_IN_TABS.to_owned(),
        "N".to_owned(),
    );

    if let Some(conn_type) = CONN_TYPE.filter(|v| matches!(*v, "incoming" | "outgoing")) {
        config::HARD_SETTINGS
            .write()
            .unwrap()
            .insert("conn-type".to_owned(), conn_type.to_owned());
    }
}
