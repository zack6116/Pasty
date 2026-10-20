#![cfg(windows)]

use crate::settings::HotkeyConfig;
use global_hotkey::hotkey::HotKey;
use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;

#[derive(Debug, Clone)]
pub enum HotkeyError {
    ManagerCreationFailed(String),
    RegistrationFailed(String),
    InvalidHotkey,
}

impl std::fmt::Display for HotkeyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HotkeyError::ManagerCreationFailed(msg) => {
                write!(f, "热键管理器创建失败: {}", msg)
            }
            HotkeyError::RegistrationFailed(msg) => {
                write!(f, "热键注册失败: {} (可能与其他程序冲突)", msg)
            }
            HotkeyError::InvalidHotkey => {
                write!(f, "无效的热键配置")
            }
        }
    }
}

pub struct HotkeyService {
    manager: GlobalHotKeyManager,
    current_hotkey: Option<HotKey>,
    current_config: HotkeyConfig,
}

impl HotkeyService {
    pub fn start(config: &HotkeyConfig) -> Result<(Self, Receiver<()>), HotkeyError> {
        let manager =
            GlobalHotKeyManager::new().map_err(|e| HotkeyError::ManagerCreationFailed(e.to_string()))?;

        let (tx, rx) = mpsc::channel();
        
        let mut service = Self {
            manager,
            current_hotkey: None,
            current_config: config.clone(),
        };
        
        service.register_hotkey(config)?;
        
        Self::start_event_listener(tx);

        Ok((service, rx))
    }

    fn start_event_listener(tx: Sender<()>) {
        thread::spawn(move || {
            let events = GlobalHotKeyEvent::receiver();
            while let Ok(event) = events.recv() {
                if event.state == HotKeyState::Pressed {
                    let _ = tx.send(());
                }
            }
        });
    }

    fn register_hotkey(&mut self, config: &HotkeyConfig) -> Result<(), HotkeyError> {
        let code = config.code().ok_or(HotkeyError::InvalidHotkey)?;
        let modifiers = config.modifiers();
        
        if modifiers.is_empty() {
            return Err(HotkeyError::InvalidHotkey);
        }

        let hotkey = HotKey::new(Some(modifiers), code);
        self.manager
            .register(hotkey)
            .map_err(|e| HotkeyError::RegistrationFailed(e.to_string()))?;
        
        self.current_hotkey = Some(hotkey);
        self.current_config = config.clone();
        
        Ok(())
    }

    fn unregister_current(&mut self) {
        if let Some(hotkey) = self.current_hotkey.take() {
            let _ = self.manager.unregister(hotkey);
        }
    }

    pub fn update_hotkey(&mut self, config: &HotkeyConfig) -> Result<(), HotkeyError> {
        if *config == self.current_config && self.current_hotkey.is_some() {
            return Ok(());
        }

        self.unregister_current();
        self.register_hotkey(config)
    }

    pub fn current_config(&self) -> &HotkeyConfig {
        &self.current_config
    }
}

pub struct HotkeyHandle {
    service: Arc<Mutex<HotkeyService>>,
}

impl HotkeyHandle {
    pub fn new(service: HotkeyService) -> Self {
        Self {
            service: Arc::new(Mutex::new(service)),
        }
    }

    pub fn update_hotkey(&self, config: &HotkeyConfig) -> Result<(), HotkeyError> {
        let mut service = self.service.lock().unwrap();
        service.update_hotkey(config)
    }

    pub fn current_config(&self) -> HotkeyConfig {
        let service = self.service.lock().unwrap();
        service.current_config().clone()
    }
}
