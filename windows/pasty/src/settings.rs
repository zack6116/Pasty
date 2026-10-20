#![cfg(windows)]

use crate::paths;
use global_hotkey::hotkey::{Code, Modifiers};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HotkeyConfig {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub win: bool,
    pub key: String,
}

impl Default for HotkeyConfig {
    fn default() -> Self {
        Self {
            ctrl: true,
            alt: false,
            shift: true,
            win: false,
            key: "V".to_string(),
        }
    }
}

impl HotkeyConfig {
    pub fn to_modifiers(&self) -> Modifiers {
        let mut mods = Modifiers::empty();
        if self.ctrl {
            mods |= Modifiers::CONTROL;
        }
        if self.alt {
            mods |= Modifiers::ALT;
        }
        if self.shift {
            mods |= Modifiers::SHIFT;
        }
        if self.win {
            mods |= Modifiers::META;
        }
        mods
    }

    pub fn to_code(&self) -> Option<Code> {
        match self.key.to_uppercase().as_str() {
            "A" => Some(Code::KeyA),
            "B" => Some(Code::KeyB),
            "C" => Some(Code::KeyC),
            "D" => Some(Code::KeyD),
            "E" => Some(Code::KeyE),
            "F" => Some(Code::KeyF),
            "G" => Some(Code::KeyG),
            "H" => Some(Code::KeyH),
            "I" => Some(Code::KeyI),
            "J" => Some(Code::KeyJ),
            "K" => Some(Code::KeyK),
            "L" => Some(Code::KeyL),
            "M" => Some(Code::KeyM),
            "N" => Some(Code::KeyN),
            "O" => Some(Code::KeyO),
            "P" => Some(Code::KeyP),
            "Q" => Some(Code::KeyQ),
            "R" => Some(Code::KeyR),
            "S" => Some(Code::KeyS),
            "T" => Some(Code::KeyT),
            "U" => Some(Code::KeyU),
            "V" => Some(Code::KeyV),
            "W" => Some(Code::KeyW),
            "X" => Some(Code::KeyX),
            "Y" => Some(Code::KeyY),
            "Z" => Some(Code::KeyZ),
            "0" => Some(Code::Digit0),
            "1" => Some(Code::Digit1),
            "2" => Some(Code::Digit2),
            "3" => Some(Code::Digit3),
            "4" => Some(Code::Digit4),
            "5" => Some(Code::Digit5),
            "6" => Some(Code::Digit6),
            "7" => Some(Code::Digit7),
            "8" => Some(Code::Digit8),
            "9" => Some(Code::Digit9),
            "F1" => Some(Code::F1),
            "F2" => Some(Code::F2),
            "F3" => Some(Code::F3),
            "F4" => Some(Code::F4),
            "F5" => Some(Code::F5),
            "F6" => Some(Code::F6),
            "F7" => Some(Code::F7),
            "F8" => Some(Code::F8),
            "F9" => Some(Code::F9),
            "F10" => Some(Code::F10),
            "F11" => Some(Code::F11),
            "F12" => Some(Code::F12),
            "SPACE" => Some(Code::Space),
            "TAB" => Some(Code::Tab),
            "BACKQUOTE" | "`" => Some(Code::Backquote),
            _ => None,
        }
    }

    pub fn display_string(&self) -> String {
        let mut parts = Vec::new();
        if self.ctrl {
            parts.push("Ctrl");
        }
        if self.alt {
            parts.push("Alt");
        }
        if self.shift {
            parts.push("Shift");
        }
        if self.win {
            parts.push("Win");
        }
        parts.push(&self.key);
        parts.join("+")
    }

    pub fn has_modifiers(&self) -> bool {
        self.ctrl || self.alt || self.shift || self.win
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub hotkey: HotkeyConfig,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            hotkey: HotkeyConfig::default(),
        }
    }
}

fn settings_path() -> PathBuf {
    paths::pasty_data_dir().join("settings.json")
}

pub fn load_settings() -> Settings {
    let path = settings_path();
    if let Ok(contents) = fs::read_to_string(&path) {
        if let Ok(settings) = serde_json::from_str(&contents) {
            return settings;
        }
    }
    Settings::default()
}

pub fn save_settings(settings: &Settings) -> Result<(), String> {
    let path = settings_path();
    let contents = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    fs::write(path, contents).map_err(|e| format!("无法保存设置: {}", e))
}
