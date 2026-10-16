use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallReport {
    pub product: String,
    pub install_id: String,
    pub app_version: String,
    pub os_version: String,
    pub model: String,
    pub arch: String,
    pub locale: String,
}

impl InstallReport {
    pub fn new(
        product: impl Into<String>,
        install_id: impl Into<String>,
        app_version: impl Into<String>,
        os_version: impl Into<String>,
        model: impl Into<String>,
        arch: impl Into<String>,
        locale: impl Into<String>,
    ) -> Self {
        Self {
            product: product.into(),
            install_id: install_id.into(),
            app_version: app_version.into(),
            os_version: os_version.into(),
            model: model.into(),
            arch: arch.into(),
            locale: locale.into(),
        }
    }
}

pub struct InstallIdentity;

impl InstallIdentity {
    pub const DEFAULTS_KEY: &'static str = "installID";

    /// Stable install id persisted as a single-line UUID file (Windows substitute for UserDefaults).
    pub fn install_id(store_path: &Path) -> String {
        if let Ok(existing) = fs::read_to_string(store_path) {
            let trimmed = existing.trim();
            if Uuid::parse_str(trimmed).is_ok() {
                return trimmed.to_lowercase();
            }
        }
        let created = Uuid::new_v4().to_string().to_lowercase();
        if let Some(parent) = store_path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::write(store_path, &created);
        created
    }
}
