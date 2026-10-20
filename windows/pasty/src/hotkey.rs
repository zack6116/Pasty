#![cfg(windows)]

use crate::settings::HotkeyConfig;
use global_hotkey::hotkey::HotKey;
use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;

#[derive(Debug, Clone)]
pub enum HotkeyError {
    ManagerInit(String),
    RegisterFailed(String),
    InvalidKey(String),
    NoModifiers,
}

impl HotkeyError {
    pub fn to_chinese(&self) -> String {
        match self {
            HotkeyError::ManagerInit(e) => format!("无法初始化快捷键服务: {}", e),
            HotkeyError::RegisterFailed(e) => {
                if e.contains("already") || e.contains("occupied") || e.contains("conflict") {
                    "快捷键已被其他程序占用，请换一个组合".to_string()
                } else {
                    format!("注册快捷键失败: {}", e)
                }
            }
            HotkeyError::InvalidKey(k) => format!("无效的按键: {}", k),
            HotkeyError::NoModifiers => "请至少选择一个修饰键（Ctrl、Alt、Shift 或 Win）".to_string(),
        }
    }
}

pub struct HotkeyService {
    manager: Arc<Mutex<GlobalHotKeyManager>>,
    current_hotkey: Arc<Mutex<Option<HotKey>>>,
    tx: Sender<()>,
}

impl HotkeyService {
    pub fn start(config: &HotkeyConfig) -> Result<(Self, Receiver<()>), HotkeyError> {
        let manager = GlobalHotKeyManager::new().map_err(|e| HotkeyError::ManagerInit(e.to_string()))?;

        let hotkey = Self::build_hotkey(config)?;
        manager
            .register(hotkey)
            .map_err(|e| HotkeyError::RegisterFailed(e.to_string()))?;

        let (tx, rx) = mpsc::channel();
        let tx_clone = tx.clone();
        let hotkey_id = hotkey.id();

        thread::spawn(move || {
            let events = GlobalHotKeyEvent::receiver();
            while let Ok(event) = events.recv() {
                if event.state == HotKeyState::Pressed && event.id == hotkey_id {
                    let _ = tx_clone.send(());
                }
            }
        });

        Ok((
            Self {
                manager: Arc::new(Mutex::new(manager)),
                current_hotkey: Arc::new(Mutex::new(Some(hotkey))),
                tx,
            },
            rx,
        ))
    }

    fn build_hotkey(config: &HotkeyConfig) -> Result<HotKey, HotkeyError> {
        if !config.has_modifiers() {
            return Err(HotkeyError::NoModifiers);
        }

        let code = config
            .to_code()
            .ok_or_else(|| HotkeyError::InvalidKey(config.key.clone()))?;

        let mods = config.to_modifiers();
        Ok(HotKey::new(Some(mods), code))
    }

    pub fn update_hotkey(&self, config: &HotkeyConfig) -> Result<(), HotkeyError> {
        let new_hotkey = Self::build_hotkey(config)?;

        let manager = self.manager.lock().unwrap();
        let mut current = self.current_hotkey.lock().unwrap();

        if let Some(old) = current.take() {
            let _ = manager.unregister(old);
        }

        manager
            .register(new_hotkey)
            .map_err(|e| HotkeyError::RegisterFailed(e.to_string()))?;

        *current = Some(new_hotkey);
        Ok(())
    }

    pub fn try_hotkey(config: &HotkeyConfig) -> Result<(), HotkeyError> {
        let hotkey = Self::build_hotkey(config)?;
        let test_manager =
            GlobalHotKeyManager::new().map_err(|e| HotkeyError::ManagerInit(e.to_string()))?;
        test_manager
            .register(hotkey)
            .map_err(|e| HotkeyError::RegisterFailed(e.to_string()))?;
        let _ = test_manager.unregister(hotkey);
        Ok(())
    }
}
