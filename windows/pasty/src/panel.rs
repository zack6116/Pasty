#![cfg(windows)]

use crate::settings::{HotkeyConfig, Settings};
use egui::{Color32, RichText, Rounding, Sense, Stroke, Vec2};
use pasty_core::{ClipItem, HistoryModel, HistoryShelf};
use uuid::Uuid;

/// Cream / copper palette mirrored from Mac `PastePalette`.
pub mod palette {
    use egui::Color32;

    pub fn paper() -> Color32 {
        Color32::from_rgb(246, 240, 229)
    }
    pub fn paper_deep() -> Color32 {
        Color32::from_rgb(236, 226, 210)
    }
    pub fn card() -> Color32 {
        Color32::from_rgb(255, 252, 248)
    }
    pub fn ink() -> Color32 {
        Color32::from_rgb(28, 24, 20)
    }
    pub fn muted() -> Color32 {
        Color32::from_rgb(138, 129, 117)
    }
    pub fn line() -> Color32 {
        Color32::from_rgb(224, 210, 190)
    }
    pub fn copper() -> Color32 {
        Color32::from_rgb(196, 81, 44)
    }
    pub fn moss() -> Color32 {
        Color32::from_rgb(31, 107, 74)
    }
}

pub struct PanelActions {
    pub copy_id: Option<Uuid>,
    pub delete_id: Option<Uuid>,
    pub pin_id: Option<Uuid>,
    pub unpin_id: Option<Uuid>,
    pub show_board: Option<Uuid>,
    pub show_recent: bool,
    pub close: bool,
    pub update_hotkey: Option<HotkeyConfig>,
    pub share_id: Option<Uuid>,
}

impl Default for PanelActions {
    fn default() -> Self {
        Self {
            copy_id: None,
            delete_id: None,
            pin_id: None,
            unpin_id: None,
            show_board: None,
            show_recent: false,
            close: false,
            update_hotkey: None,
            share_id: None,
        }
    }
}

#[derive(Default)]
pub struct SettingsState {
    pub show_settings: bool,
    pub recording: bool,
    pub pending_hotkey: Option<HotkeyConfig>,
    pub error_message: Option<String>,
    pub success_message: Option<String>,
    pub share_status: Option<String>,
}

/// Horizontal card strip for clipboard history (scaffold UI).
pub fn draw_history_panel(
    ui: &mut egui::Ui,
    model: &mut HistoryModel,
    settings: &Settings,
    settings_state: &mut SettingsState,
) -> PanelActions {
    let mut actions = PanelActions::default();

    let rect = ui.max_rect();
    ui.painter()
        .rect_filled(rect, Rounding::same(16.0), palette::paper());

    ui.vertical(|ui| {
        ui.add_space(12.0);
        ui.horizontal(|ui| {
            ui.add_space(16.0);
            ui.label(
                RichText::new("剪贴板")
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
                    actions.close = true;
                }
                ui.add_space(8.0);
                if ui
                    .button(RichText::new("设置").color(palette::muted()))
                    .clicked()
                {
                    settings_state.show_settings = !settings_state.show_settings;
                    settings_state.recording = false;
                    settings_state.pending_hotkey = None;
                    settings_state.error_message = None;
                    settings_state.success_message = None;
                }
            });
        });

        if settings_state.show_settings {
            draw_settings_panel(ui, settings, settings_state, &mut actions);
        }

        ui.add_space(8.0);
        ui.horizontal(|ui| {
            ui.add_space(16.0);
            let recent_selected = matches!(model.shelf(), HistoryShelf::Recent);
            if shelf_chip(ui, "最近", recent_selected).clicked() {
                actions.show_recent = true;
            }
            for board in model.boards.clone() {
                let selected = matches!(model.shelf(), HistoryShelf::Board(id) if id == board.id);
                if shelf_chip(ui, &board.name, selected).clicked() {
                    actions.show_board = Some(board.id);
                }
            }
        });

        ui.add_space(8.0);
        ui.horizontal(|ui| {
            ui.add_space(16.0);
            let mut query = model.query.clone();
            let response = ui.add(
                egui::TextEdit::singleline(&mut query)
                    .hint_text("搜索…")
                    .desired_width(ui.available_width() - 32.0),
            );
            if response.changed() {
                model.set_query(query);
            }
        });

        ui.add_space(10.0);
        egui::ScrollArea::horizontal()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.add_space(12.0);
                    let filtered: Vec<ClipItem> =
                        model.filtered().into_iter().cloned().collect();
                    let selected = model.selected_id();
                    for item in &filtered {
                        let is_selected = selected == Some(item.id);
                        let card = draw_card(ui, item, is_selected);
                        if card.clicked() {
                            model.select(item.id);
                        }
                        if card.double_clicked() {
                            actions.copy_id = Some(item.id);
                        }
                        card.context_menu(|ui| {
                            if ui.button("复制").clicked() {
                                actions.copy_id = Some(item.id);
                                ui.close_menu();
                            }
                            if !item.is_image() {
                                if ui.button("分享").clicked() {
                                    actions.share_id = Some(item.id);
                                    ui.close_menu();
                                }
                            }
                            if item.pinned {
                                if ui.button("取消固定").clicked() {
                                    actions.unpin_id = Some(item.id);
                                    ui.close_menu();
                                }
                            } else if ui.button("固定").clicked() {
                                actions.pin_id = Some(item.id);
                                ui.close_menu();
                            }
                            if ui.button("删除").clicked() {
                                actions.delete_id = Some(item.id);
                                ui.close_menu();
                            }
                        });
                        ui.add_space(8.0);
                    }
                    if filtered.is_empty() {
                        ui.add_space(24.0);
                        ui.label(RichText::new("暂无记录").color(palette::muted()));
                    }
                    ui.add_space(12.0);
                });
            });

        ui.add_space(10.0);
        ui.horizontal(|ui| {
            ui.add_space(16.0);
            if let Some(ref status) = settings_state.share_status {
                ui.label(RichText::new(status).small().color(palette::copper()));
            } else {
                let hotkey_display = settings.hotkey.display_string();
                ui.label(
                    RichText::new(format!("{} · 双击复制 · 右键分享", hotkey_display))
                        .small()
                        .color(palette::muted()),
                );
            }
        });
        ui.add_space(12.0);
    });

    if ui.input(|i| i.key_pressed(egui::Key::ArrowLeft) || i.key_pressed(egui::Key::ArrowUp)) {
        model.move_selection(-1);
    }
    if ui.input(|i| i.key_pressed(egui::Key::ArrowRight) || i.key_pressed(egui::Key::ArrowDown)) {
        model.move_selection(1);
    }
    if ui.input(|i| i.key_pressed(egui::Key::Enter)) {
        if let Some(item) = model.selected_item() {
            actions.copy_id = Some(item.id);
        }
    }
    if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
        actions.close = true;
    }

    let mut scroll_acc = 0.0f64;
    let scroll = ui.input(|i| i.smooth_scroll_delta.y);
    if scroll != 0.0 {
        let steps = pasty_core::ScrollSelection::consume(scroll as f64, true, &mut scroll_acc);
        if steps != 0 {
            model.move_selection(steps);
        }
    }

    actions
}

fn shelf_chip(ui: &mut egui::Ui, label: &str, selected: bool) -> egui::Response {
    let text = if selected {
        RichText::new(label).color(Color32::WHITE).strong()
    } else {
        RichText::new(label).color(palette::ink())
    };
    let button = egui::Button::new(text).fill(if selected {
        palette::ink()
    } else {
        Color32::from_white_alpha(90)
    });
    ui.add(button)
}

fn draw_card(ui: &mut egui::Ui, item: &ClipItem, selected: bool) -> egui::Response {
    let size = Vec2::new(160.0, 120.0);
    let (rect, response) = ui.allocate_exact_size(size, Sense::click());
    let painter = ui.painter();
    let fill = if selected {
        palette::moss()
    } else {
        palette::card()
    };
    let stroke = if selected {
        Stroke::new(2.0_f32, palette::moss())
    } else {
        Stroke::new(1.0_f32, palette::line())
    };
    painter.rect_filled(rect, Rounding::same(12.0), fill);
    painter.rect_stroke(rect, Rounding::same(12.0), stroke);

    let text_color = if selected {
        Color32::WHITE
    } else {
        palette::ink()
    };
    let preview = card_preview(&item.text);
    painter.text(
        rect.left_top() + egui::vec2(12.0, 14.0),
        egui::Align2::LEFT_TOP,
        preview,
        egui::FontId::proportional(13.0),
        text_color,
    );

    if item.pinned {
        painter.circle_filled(
            rect.right_top() + egui::vec2(-14.0, 14.0),
            4.0,
            if selected {
                Color32::WHITE
            } else {
                palette::copper()
            },
        );
    }

    response
}

fn card_preview(text: &str) -> String {
    let flat: String = text.chars().take(48).collect();
    if text.chars().count() > 48 {
        format!("{flat}…")
    } else {
        flat
    }
}

fn draw_settings_panel(
    ui: &mut egui::Ui,
    settings: &Settings,
    state: &mut SettingsState,
    actions: &mut PanelActions,
) {
    ui.add_space(8.0);
    ui.horizontal(|ui| {
        ui.add_space(16.0);
        ui.group(|ui| {
            ui.set_min_width(ui.available_width() - 32.0);
            ui.vertical(|ui| {
                ui.add_space(8.0);
                ui.horizontal(|ui| {
                    ui.label(RichText::new("快捷键设置").strong().color(palette::ink()));
                });
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.label("当前快捷键：");
                    let display = if state.recording {
                        if let Some(ref pending) = state.pending_hotkey {
                            pending.display_string()
                        } else {
                            "按下新快捷键…".to_string()
                        }
                    } else {
                        settings.hotkey.display_string()
                    };
                    ui.label(
                        RichText::new(&display)
                            .strong()
                            .color(if state.recording {
                                palette::copper()
                            } else {
                                palette::ink()
                            }),
                    );
                });

                ui.add_space(4.0);
                ui.horizontal(|ui| {
                    if state.recording {
                        if ui.button("取消").clicked() {
                            state.recording = false;
                            state.pending_hotkey = None;
                            state.error_message = None;
                        }
                        if state.pending_hotkey.is_some() {
                            if ui.button("确认").clicked() {
                                if let Some(hotkey) = state.pending_hotkey.take() {
                                    actions.update_hotkey = Some(hotkey);
                                    state.recording = false;
                                }
                            }
                        }
                    } else if ui.button("修改快捷键").clicked() {
                        state.recording = true;
                        state.pending_hotkey = None;
                        state.error_message = None;
                        state.success_message = None;
                    }
                });

                if let Some(ref err) = state.error_message {
                    ui.add_space(4.0);
                    ui.label(RichText::new(err).color(Color32::from_rgb(200, 60, 60)));
                }
                if let Some(ref msg) = state.success_message {
                    ui.add_space(4.0);
                    ui.label(RichText::new(msg).color(palette::moss()));
                }

                ui.add_space(4.0);
                ui.label(
                    RichText::new("提示：需要至少一个修饰键（Ctrl、Alt、Shift 或 Win）")
                        .small()
                        .color(palette::muted()),
                );
                ui.add_space(8.0);
            });
        });
        ui.add_space(16.0);
    });

    if state.recording {
        let new_hotkey = capture_hotkey_input(ui);
        if let Some(hotkey) = new_hotkey {
            if hotkey.has_modifiers() {
                state.pending_hotkey = Some(hotkey);
                state.error_message = None;
            } else if !hotkey.key.is_empty() {
                state.error_message =
                    Some("请至少选择一个修饰键（Ctrl、Alt、Shift 或 Win）".to_string());
            }
        }
    }
}

fn capture_hotkey_input(ui: &mut egui::Ui) -> Option<HotkeyConfig> {
    let input = ui.input(|i| {
        let ctrl = i.modifiers.ctrl;
        let alt = i.modifiers.alt;
        let shift = i.modifiers.shift;
        let command = i.modifiers.command;

        for key in &i.keys_down {
            if let Some(key_str) = egui_key_to_string(*key) {
                return Some(HotkeyConfig {
                    ctrl,
                    alt,
                    shift,
                    win: command && !ctrl,
                    key: key_str,
                });
            }
        }
        None
    });
    input
}

fn egui_key_to_string(key: egui::Key) -> Option<String> {
    use egui::Key;
    match key {
        Key::A => Some("A".to_string()),
        Key::B => Some("B".to_string()),
        Key::C => Some("C".to_string()),
        Key::D => Some("D".to_string()),
        Key::E => Some("E".to_string()),
        Key::F => Some("F".to_string()),
        Key::G => Some("G".to_string()),
        Key::H => Some("H".to_string()),
        Key::I => Some("I".to_string()),
        Key::J => Some("J".to_string()),
        Key::K => Some("K".to_string()),
        Key::L => Some("L".to_string()),
        Key::M => Some("M".to_string()),
        Key::N => Some("N".to_string()),
        Key::O => Some("O".to_string()),
        Key::P => Some("P".to_string()),
        Key::Q => Some("Q".to_string()),
        Key::R => Some("R".to_string()),
        Key::S => Some("S".to_string()),
        Key::T => Some("T".to_string()),
        Key::U => Some("U".to_string()),
        Key::V => Some("V".to_string()),
        Key::W => Some("W".to_string()),
        Key::X => Some("X".to_string()),
        Key::Y => Some("Y".to_string()),
        Key::Z => Some("Z".to_string()),
        Key::Num0 => Some("0".to_string()),
        Key::Num1 => Some("1".to_string()),
        Key::Num2 => Some("2".to_string()),
        Key::Num3 => Some("3".to_string()),
        Key::Num4 => Some("4".to_string()),
        Key::Num5 => Some("5".to_string()),
        Key::Num6 => Some("6".to_string()),
        Key::Num7 => Some("7".to_string()),
        Key::Num8 => Some("8".to_string()),
        Key::Num9 => Some("9".to_string()),
        Key::F1 => Some("F1".to_string()),
        Key::F2 => Some("F2".to_string()),
        Key::F3 => Some("F3".to_string()),
        Key::F4 => Some("F4".to_string()),
        Key::F5 => Some("F5".to_string()),
        Key::F6 => Some("F6".to_string()),
        Key::F7 => Some("F7".to_string()),
        Key::F8 => Some("F8".to_string()),
        Key::F9 => Some("F9".to_string()),
        Key::F10 => Some("F10".to_string()),
        Key::F11 => Some("F11".to_string()),
        Key::F12 => Some("F12".to_string()),
        Key::Space => Some("SPACE".to_string()),
        Key::Tab => Some("TAB".to_string()),
        Key::Backtick => Some("BACKQUOTE".to_string()),
        _ => None,
    }
}
