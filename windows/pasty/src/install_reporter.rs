#![cfg(windows)]

use crate::paths;
use pasty_core::{InstallIdentity, InstallReport};

const ENDPOINT: &str = "https://ops.coderfather.com/v1/report";
const APP_VERSION: &str = env!("CARGO_PKG_VERSION");

pub struct InstallReporter;

impl InstallReporter {
    pub fn send() {
        let report = make_report();
        let Ok(body) = serde_json::to_vec(&report) else {
            return;
        };
        let _ = ureq::post(ENDPOINT)
            .set("Content-Type", "application/json")
            .set("User-Agent", &format!("Pasty/{}", report.app_version))
            .timeout(std::time::Duration::from_secs(8))
            .send_bytes(&body);
    }
}

fn make_report() -> InstallReport {
    InstallReport::new(
        "pasty",
        InstallIdentity::install_id(&paths::install_id_path()),
        if APP_VERSION.is_empty() {
            "dev"
        } else {
            APP_VERSION
        },
        os_version(),
        model(),
        arch(),
        locale(),
    )
}

fn os_version() -> String {
    std::env::var("OS").unwrap_or_else(|_| "Windows".into())
}

fn model() -> String {
    "unknown".into()
}

fn arch() -> String {
    std::env::consts::ARCH.to_string()
}

fn locale() -> String {
    std::env::var("LANG")
        .or_else(|_| std::env::var("LC_ALL"))
        .unwrap_or_else(|_| "en_US".into())
}
