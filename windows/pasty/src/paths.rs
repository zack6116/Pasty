use std::path::PathBuf;

/// Application data root.
/// Windows: `%LOCALAPPDATA%\Pasty`
/// Other platforms (tests / stub builds): temp-adjacent fallback under home or cwd.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn pasty_data_dir() -> PathBuf {
    #[cfg(windows)]
    {
        if let Ok(local) = std::env::var("LOCALAPPDATA") {
            return PathBuf::from(local).join("Pasty");
        }
    }

    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home).join(".local").join("share").join("Pasty");
    }
    PathBuf::from("Pasty")
}

#[cfg_attr(not(windows), allow(dead_code))]
pub fn history_json() -> PathBuf {
    pasty_data_dir().join("history.json")
}

#[cfg_attr(not(windows), allow(dead_code))]
pub fn install_id_path() -> PathBuf {
    pasty_data_dir().join("install_id")
}

#[cfg_attr(not(windows), allow(dead_code))]
pub fn images_dir() -> PathBuf {
    pasty_data_dir().join("images")
}
