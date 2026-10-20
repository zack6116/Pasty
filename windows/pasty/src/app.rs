#![cfg(windows)]

use crate::clipboard_monitor::{ClipboardMonitor, MonitorHandle};
use crate::fonts;
use crate::hotkey::{HotkeyError, HotkeyHandle, HotkeyService};
use crate::install_reporter::InstallReporter;
use crate::panel::{self, PanelActions};
use crate::paths;
use crate::settings::{HotkeyConfig, Settings};
use crate::tray::{TrayCommand, TrayService};
use chrono::Utc;
use eframe::egui;
use pasty_core::{ClipboardStore, HistoryModel, HistoryShelf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub fn run() -> Result<(), String> {
    let data_dir = paths::pasty_data_dir();
    std::fs::create_dir_all(&data_dir).map_err(|e| e.to_string())?;

    InstallReporter::send();

    let settings_path = paths::settings_json();
    let settings = Arc::new(Mutex::new(Settings::load(&settings_path)));

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

    let initial_config = settings.lock().unwrap().hotkey.clone();
    let (hotkey_service, hotkey_rx) = HotkeyService::start(&initial_config)
        .map_err(|e| e.to_string())?;
    let hotkey_handle = HotkeyHandle::new(hotkey_service);
    
    let (tray, tray_rx) = TrayService::start()?;

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([720.0, 280.0])
            .with_decorations(false)
            .with_transparent(true)
            .with_always_on_top()
            .with_visible(false),
        ..Default::default()
    };

    let app_state = PastyApp {
        store,
        model,
        settings,
        settings_path,
        monitor: monitor_handle,
        hotkey_rx,
        hotkey_handle,
        tray_rx,
        panel_visible: false,
        settings_visible: false,
        pending_hotkey: None,
        hotkey_error: None,
        _tray: tray,
        fonts_configured: false,
    };

    eframe::run_native(
        "Pasty",
        options,
        Box::new(|_cc| Ok(Box::new(app_state))),
    )
    .map_err(|e| e.to_string())
}

struct PastyApp {
    store: Arc<Mutex<ClipboardStore>>,
    model: Arc<Mutex<HistoryModel>>,
    settings: Arc<Mutex<Settings>>,
    settings_path: std::path::PathBuf,
    monitor: MonitorHandle,
    hotkey_rx: std::sync::mpsc::Receiver<()>,
    hotkey_handle: HotkeyHandle,
    tray_rx: std::sync::mpsc::Receiver<TrayCommand>,
    panel_visible: bool,
    settings_visible: bool,
    pending_hotkey: Option<HotkeyConfig>,
    hotkey_error: Option<HotkeyError>,
    _tray: TrayService,
    fonts_configured: bool,
}

impl eframe::App for PastyApp {
    fn clear_color(&self, _visuals: &egui::Visuals) -> [f32; 4] {
        egui::Rgba::TRANSPARENT.to_array()
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if !self.fonts_configured {
            fonts::configure_cjk_fonts(ctx);
            self.fonts_configured = true;
        }

        while self.hotkey_rx.try_recv().is_ok() {
            if self.settings_visible {
                continue;
            }
            self.show_panel(ctx);
        }
        while let Ok(cmd) = self.tray_rx.try_recv() {
            match cmd {
                TrayCommand::ShowHistory => {
                    if !self.settings_visible {
                        self.show_panel(ctx);
                    }
                }
                TrayCommand::ShowSettings => {
                    self.show_settings(ctx);
                }
                TrayCommand::Quit => {
                    ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                }
            }
        }

        if !self.panel_visible && !self.settings_visible {
            ctx.request_repaint_after(Duration::from_millis(200));
            return;
        }

        if self.settings_visible {
            egui::CentralPanel::default()
                .frame(egui::Frame::none())
                .show(ctx, |ui| {
                    self.draw_settings_panel(ui, ctx);
                });
        } else if self.panel_visible {
            egui::CentralPanel::default()
                .frame(egui::Frame::none())
                .show(ctx, |ui| {
                    let mut model = self.model.lock().unwrap();
                    let actions = panel::draw_history_panel(ui, &mut model);
                    drop(model);
                    self.apply_actions(ctx, actions);
                });
        }

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

    fn show_settings(&mut self, ctx: &egui::Context) {
        self.panel_visible = false;
        self.settings_visible = true;
        self.pending_hotkey = Some(self.hotkey_handle.current_config());
        self.hotkey_error = None;
        ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
        ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
    }

    fn hide_settings(&mut self, ctx: &egui::Context) {
        self.settings_visible = false;
        self.pending_hotkey = None;
        self.hotkey_error = None;
        ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
    }

    fn draw_settings_panel(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        use crate::panel::palette;
        use crate::settings::AVAILABLE_KEYS;
        use egui::{RichText, Rounding};

        let rect = ui.max_rect();
        ui.painter()
            .rect_filled(rect, Rounding::same(16.0), palette::paper());

        ui.vertical(|ui| {
            ui.add_space(12.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("设置")
                        .strong()
                        .color(palette::copper())
                        .size(15.0),
                );
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.add_space(12.0);
                    if ui
                        .button(RichText::new("关闭").color(palette::muted()))
                        .clicked()
                    {
                        self.hide_settings(ctx);
                    }
                });
            });

            ui.add_space(16.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("全局快捷键")
                        .strong()
                        .color(palette::ink())
                        .size(14.0),
                );
            });

            ui.add_space(8.0);
            
            let pending = self.pending_hotkey.get_or_insert_with(|| {
                self.hotkey_handle.current_config()
            });

            ui.horizontal(|ui| {
                ui.add_space(16.0);
                
                let mut ctrl = pending.ctrl;
                if ui.checkbox(&mut ctrl, "Ctrl").changed() {
                    pending.ctrl = ctrl;
                }
                
                let mut shift = pending.shift;
                if ui.checkbox(&mut shift, "Shift").changed() {
                    pending.shift = shift;
                }
                
                let mut alt = pending.alt;
                if ui.checkbox(&mut alt, "Alt").changed() {
                    pending.alt = alt;
                }
                
                ui.add_space(8.0);
                ui.label("+");
                ui.add_space(8.0);
                
                let current_key = pending.key.clone();
                let mut new_key = None;
                egui::ComboBox::from_id_salt("key_selector")
                    .selected_text(&current_key)
                    .width(80.0)
                    .show_ui(ui, |ui| {
                        for key in AVAILABLE_KEYS {
                            let selected = *key == current_key.as_str();
                            if ui.selectable_label(selected, *key).clicked() {
                                new_key = Some(key.to_string());
                            }
                        }
                    });
                if let Some(k) = new_key {
                    pending.key = k;
                }
            });

            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                let preview = pending.display_string();
                ui.label(
                    RichText::new(format!("当前设置: {}", preview))
                        .color(palette::muted())
                        .size(12.0),
                );
            });

            if let Some(error) = &self.hotkey_error {
                ui.add_space(8.0);
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new(error.to_string())
                            .color(egui::Color32::from_rgb(200, 50, 50))
                            .size(12.0),
                    );
                });
            }

            ui.add_space(16.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                
                let mut should_hide = false;
                if ui.button(RichText::new("保存").color(palette::ink())).clicked() {
                    if let Some(new_config) = &self.pending_hotkey {
                        if !new_config.is_valid() {
                            self.hotkey_error = Some(HotkeyError::InvalidHotkey);
                        } else {
                            match self.hotkey_handle.update_hotkey(new_config) {
                                Ok(()) => {
                                    {
                                        let mut settings = self.settings.lock().unwrap();
                                        settings.hotkey = new_config.clone();
                                        if let Err(e) = settings.save(&self.settings_path) {
                                            self.hotkey_error = Some(HotkeyError::RegistrationFailed(
                                                format!("保存设置失败: {}", e)
                                            ));
                                        } else {
                                            self.hotkey_error = None;
                                            should_hide = true;
                                        }
                                    }
                                }
                                Err(e) => {
                                    self.hotkey_error = Some(e);
                                }
                            }
                        }
                    }
                }
                if should_hide {
                    self.hide_settings(ctx);
                }
                
                ui.add_space(8.0);
                
                if ui.button(RichText::new("重置默认").color(palette::muted())).clicked() {
                    self.pending_hotkey = Some(HotkeyConfig::default());
                    self.hotkey_error = None;
                }
            });

            ui.add_space(16.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("提示: 修改后需要点击「保存」才能生效")
                        .small()
                        .color(palette::muted()),
                );
            });
            
            ui.add_space(12.0);
        });

        if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
            self.hide_settings(ctx);
        }
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
    }
}

enum CopyPayload {
    Text(String),
    Image(Vec<u8>),
}
