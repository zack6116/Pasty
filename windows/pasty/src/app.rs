#![cfg(windows)]

use crate::clipboard_monitor::{ClipboardMonitor, MonitorHandle};
use crate::hotkey::HotkeyService;
use crate::install_reporter::InstallReporter;
use crate::panel::{self, PanelActions, SettingsState};
use crate::paths;
use crate::settings::{self, Settings};
use crate::tray::{TrayCommand, TrayService};
use chrono::Utc;
use eframe::egui::{self, FontData, FontDefinitions, FontFamily};
use pasty_core::{ClipboardStore, HistoryModel, HistoryShelf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

fn load_cjk_fonts(ctx: &egui::Context) {
    let mut fonts = FontDefinitions::default();

    let font_paths = [
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
        r"C:\Windows\Fonts\simsun.ttc",
        r"C:\Windows\Fonts\mingliu.ttc",
    ];

    for path in font_paths {
        if let Ok(data) = std::fs::read(path) {
            fonts.font_data.insert(
                "cjk_fallback".to_owned(),
                FontData::from_owned(data).into(),
            );
            fonts
                .families
                .entry(FontFamily::Proportional)
                .or_default()
                .push("cjk_fallback".to_owned());
            fonts
                .families
                .entry(FontFamily::Monospace)
                .or_default()
                .push("cjk_fallback".to_owned());
            break;
        }
    }

    ctx.set_fonts(fonts);
}

pub fn run() -> Result<(), String> {
    let data_dir = paths::pasty_data_dir();
    std::fs::create_dir_all(&data_dir).map_err(|e| e.to_string())?;

    InstallReporter::send();

    let settings = settings::load_settings();

    let store = Arc::new(Mutex::new(ClipboardStore::new(paths::history_json())));
    let model = Arc::new(Mutex::new(HistoryModel::new()));

    let monitor = ClipboardMonitor::new(Duration::from_millis(400));
    let monitor_handle = monitor.start(
        {
            let store = Arc::clone(&store);
            let model = Arc::clone(&model);
            move |text| {
                let mut store = store.lock().unwrap();
                if store.add(&text, Utc::now()) {
                    let mut model = model.lock().unwrap();
                    model.reload(store.items().to_vec(), Some(store.boards().to_vec()));
                }
            }
        },
        {
            let store = Arc::clone(&store);
            let model = Arc::clone(&model);
            move |png| {
                let mut store = store.lock().unwrap();
                if store.add_image(&png, Utc::now()) {
                    let mut model = model.lock().unwrap();
                    model.reload(store.items().to_vec(), Some(store.boards().to_vec()));
                }
            }
        },
    );

    let (hotkey, hotkey_rx) = HotkeyService::start(&settings.hotkey).map_err(|e| e.to_chinese())?;
    let (tray, tray_rx) = TrayService::start()?;

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([720.0, 320.0])
            .with_decorations(false)
            .with_transparent(true)
            .with_always_on_top()
            .with_visible(false),
        ..Default::default()
    };

    let app_state = PastyApp {
        store,
        model,
        monitor: monitor_handle,
        hotkey_rx,
        tray_rx,
        panel_visible: false,
        hotkey,
        settings,
        settings_state: SettingsState::default(),
        _tray: tray,
    };

    eframe::run_native(
        "Pasty",
        options,
        Box::new(|cc| {
            load_cjk_fonts(&cc.egui_ctx);
            Ok(Box::new(app_state))
        }),
    )
    .map_err(|e| e.to_string())
}

struct PastyApp {
    store: Arc<Mutex<ClipboardStore>>,
    model: Arc<Mutex<HistoryModel>>,
    monitor: MonitorHandle,
    hotkey_rx: std::sync::mpsc::Receiver<()>,
    tray_rx: std::sync::mpsc::Receiver<TrayCommand>,
    panel_visible: bool,
    hotkey: HotkeyService,
    settings: Settings,
    settings_state: SettingsState,
    _tray: TrayService,
}

impl eframe::App for PastyApp {
    fn clear_color(&self, _visuals: &egui::Visuals) -> [f32; 4] {
        egui::Rgba::TRANSPARENT.to_array()
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        while self.hotkey_rx.try_recv().is_ok() {
            self.show_panel(ctx);
        }
        while let Ok(cmd) = self.tray_rx.try_recv() {
            match cmd {
                TrayCommand::ShowHistory => self.show_panel(ctx),
                TrayCommand::Quit => {
                    ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                }
            }
        }

        if !self.panel_visible {
            ctx.request_repaint_after(Duration::from_millis(200));
            return;
        }

        egui::CentralPanel::default()
            .frame(egui::Frame::none())
            .show(ctx, |ui| {
                let mut model = self.model.lock().unwrap();
                let actions = panel::draw_history_panel(
                    ui,
                    &mut model,
                    &self.settings,
                    &mut self.settings_state,
                );
                drop(model);
                self.apply_actions(ctx, actions);
            });

        ctx.request_repaint_after(Duration::from_millis(100));
    }
}

impl PastyApp {
    fn show_panel(&mut self, ctx: &egui::Context) {
        {
            let store = self.store.lock().unwrap();
            let mut model = self.model.lock().unwrap();
            model.prepare(
                store.items().to_vec(),
                store.boards().to_vec(),
                HistoryShelf::Recent,
            );
            model.request_focus();
        }
        self.panel_visible = true;
        ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
        ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
    }

    fn hide_panel(&mut self, ctx: &egui::Context) {
        self.panel_visible = false;
        ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
    }

    fn apply_actions(&mut self, ctx: &egui::Context, actions: PanelActions) {
        if actions.close {
            self.hide_panel(ctx);
            return;
        }
        if actions.show_recent {
            self.model.lock().unwrap().show_recent();
        }
        if let Some(id) = actions.show_board {
            self.model.lock().unwrap().show_board(id);
        }
        if let Some(id) = actions.copy_id {
            let payload = {
                let store = self.store.lock().unwrap();
                store.items().iter().find(|i| i.id == id).and_then(|item| {
                    if item.is_image() {
                        store.image_data(item).map(CopyPayload::Image)
                    } else {
                        Some(CopyPayload::Text(item.text.clone()))
                    }
                })
            };
            match payload {
                Some(CopyPayload::Text(text)) => {
                    if self.monitor.write_text(&text) {
                        self.hide_panel(ctx);
                    }
                }
                Some(CopyPayload::Image(png)) => {
                    if self.monitor.write_image_png(&png) {
                        self.hide_panel(ctx);
                    }
                }
                None => {}
            }
        }
        if let Some(id) = actions.delete_id {
            let mut store = self.store.lock().unwrap();
            store.delete(id);
            let mut model = self.model.lock().unwrap();
            model.remove(id);
            model.reload(store.items().to_vec(), Some(store.boards().to_vec()));
        }
        if let Some(id) = actions.pin_id {
            let mut store = self.store.lock().unwrap();
            store.set_pinned(id, true);
            let mut model = self.model.lock().unwrap();
            model.reload(store.items().to_vec(), Some(store.boards().to_vec()));
            model.apply_pin(id, true);
        }
        if let Some(id) = actions.unpin_id {
            let mut store = self.store.lock().unwrap();
            store.set_pinned(id, false);
            let mut model = self.model.lock().unwrap();
            model.reload(store.items().to_vec(), Some(store.boards().to_vec()));
            model.apply_pin(id, false);
        }
        if let Some(new_hotkey) = actions.update_hotkey {
            match self.hotkey.update_hotkey(&new_hotkey) {
                Ok(()) => {
                    self.settings.hotkey = new_hotkey;
                    if let Err(e) = settings::save_settings(&self.settings) {
                        self.settings_state.error_message = Some(e);
                    } else {
                        self.settings_state.success_message = Some("快捷键已更新".to_string());
                    }
                }
                Err(e) => {
                    self.settings_state.error_message = Some(e.to_chinese());
                }
            }
        }
    }
}

enum CopyPayload {
    Text(String),
    Image(Vec<u8>),
}
