#![cfg(windows)]

use std::sync::mpsc::{self, Receiver};
use tray_icon::menu::{Menu, MenuEvent, MenuItem};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};

#[derive(Debug, Clone, Copy)]
pub enum TrayCommand {
    ShowHistory,
    ShowSettings,
    Quit,
}

pub struct TrayService {
    _tray: TrayIcon,
}

impl TrayService {
    pub fn start() -> Result<(Self, Receiver<TrayCommand>), String> {
        let menu = Menu::new();
        let show = MenuItem::new("显示历史", true, None);
        let settings = MenuItem::new("设置", true, None);
        let quit = MenuItem::new("退出", true, None);
        menu.append(&show).map_err(|e| e.to_string())?;
        menu.append(&settings).map_err(|e| e.to_string())?;
        menu.append(&quit).map_err(|e| e.to_string())?;

        let show_id = show.id().clone();
        let settings_id = settings.id().clone();
        let quit_id = quit.id().clone();

        let icon = default_icon()?;
        let tray = TrayIconBuilder::new()
            .with_menu(Box::new(menu))
            .with_tooltip("Pasty")
            .with_icon(icon)
            .build()
            .map_err(|e| e.to_string())?;

        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let menu_channel = MenuEvent::receiver();
            while let Ok(event) = menu_channel.recv() {
                if event.id == show_id {
                    let _ = tx.send(TrayCommand::ShowHistory);
                } else if event.id == settings_id {
                    let _ = tx.send(TrayCommand::ShowSettings);
                } else if event.id == quit_id {
                    let _ = tx.send(TrayCommand::Quit);
                }
            }
        });

        Ok((Self { _tray: tray }, rx))
    }
}

fn default_icon() -> Result<Icon, String> {
    // 16×16 solid copper-ish RGBA
    let size = 16u32;
    let mut rgba = Vec::with_capacity((size * size * 4) as usize);
    for _ in 0..(size * size) {
        rgba.extend_from_slice(&[196, 81, 44, 255]);
    }
    Icon::from_rgba(rgba, size, size).map_err(|e| e.to_string())
}
