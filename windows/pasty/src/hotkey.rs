#![cfg(windows)]

use global_hotkey::hotkey::{Code, HotKey, Modifiers};
use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState};
use std::sync::mpsc::{self, Receiver};
use std::thread;

/// Ctrl+Shift+V — mirrors the Mac global paste history hotkey.
pub struct HotkeyService {
    _manager: GlobalHotKeyManager,
}

impl HotkeyService {
    pub fn start() -> Result<(Self, Receiver<()>), String> {
        let manager = GlobalHotKeyManager::new().map_err(|e| e.to_string())?;
        let hotkey = HotKey::new(Some(Modifiers::CONTROL | Modifiers::SHIFT), Code::KeyV);
        manager.register(hotkey).map_err(|e| e.to_string())?;

        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let events = GlobalHotKeyEvent::receiver();
            while let Ok(event) = events.recv() {
                if event.state == HotKeyState::Pressed {
                    let _ = tx.send(());
                }
            }
        });

        Ok((Self { _manager: manager }, rx))
    }
}
