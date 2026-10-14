//! Opening DigUp when the person signs in, as the Mac app's login item does. On Windows that's a value under
//! HKCU\Software\Microsoft\Windows\CurrentVersion\Run naming this program (the installer's uninstall hook removes it,
//! shell/src-tauri/windows/hooks.nsh). Not offered on Linux yet.

#[cfg(windows)]
const RUN: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
#[cfg(windows)]
const NAME: &str = "DigUp";

/// Whether this system can open DigUp at sign-in (setup and the tray offer it only then).
pub fn is_supported() -> bool {
    cfg!(windows)
}

/// Whether DigUp opens at sign-in now.
#[cfg(windows)]
pub fn is_on() -> bool {
    use winreg::{enums::HKEY_CURRENT_USER, RegKey};
    RegKey::predef(HKEY_CURRENT_USER).open_subkey(RUN).and_then(|key| key.get_value::<String, _>(NAME)).is_ok()
}

/// Turns opening at sign-in on (for this copy of DigUp, where it's installed) or off.
#[cfg(windows)]
pub fn set(on: bool) -> Result<(), String> {
    use winreg::{enums::HKEY_CURRENT_USER, RegKey};
    let (key, _) = RegKey::predef(HKEY_CURRENT_USER).create_subkey(RUN).map_err(|error| error.to_string())?;
    if on {
        let program = std::env::current_exe().map_err(|error| error.to_string())?;
        return key.set_value(NAME, &format!("\"{}\"", program.display())).map_err(|error| error.to_string());
    }
    match key.delete_value(NAME) {
        Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(error.to_string()),
        _ => Ok(()),
    }
}

#[cfg(not(windows))]
pub fn is_on() -> bool {
    false
}

#[cfg(not(windows))]
pub fn set(_on: bool) -> Result<(), String> {
    Err("opening at sign-in isn't available on this system yet".into())
}
