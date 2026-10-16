#![cfg(windows)]

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
        }
    }
}

/// Horizontal card strip for clipboard history (scaffold UI).
pub fn draw_history_panel(ui: &mut egui::Ui, model: &mut HistoryModel) -> PanelActions {
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
            });
        });

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
            ui.label(
                RichText::new("Ctrl+Shift+V · 双击复制")
                    .small()
                    .color(palette::muted()),
            );
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
        Stroke::new(2.0, palette::moss())
    } else {
        Stroke::new(1.0, palette::line())
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
