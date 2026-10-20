#![cfg(windows)]

use eframe::egui::{self, FontData, FontDefinitions, FontFamily};
use std::path::PathBuf;

fn windows_fonts_dir() -> PathBuf {
    std::env::var("WINDIR")
        .map(|w| PathBuf::from(w).join("Fonts"))
        .unwrap_or_else(|_| PathBuf::from("C:\\Windows\\Fonts"))
}

fn try_load_font(path: &PathBuf) -> Option<Vec<u8>> {
    std::fs::read(path).ok()
}

pub fn configure_cjk_fonts(ctx: &egui::Context) {
    let fonts_dir = windows_fonts_dir();
    
    let cjk_font_candidates = [
        "msyh.ttc",      // Microsoft YaHei (微软雅黑) - most common
        "msyhbd.ttc",    // Microsoft YaHei Bold
        "simhei.ttf",    // SimHei (黑体) - fallback
        "simsun.ttc",    // SimSun (宋体) - fallback
        "msjh.ttc",      // Microsoft JhengHei (微軟正黑體)
        "mingliu.ttc",   // MingLiU (細明體)
    ];

    let mut font_data: Option<Vec<u8>> = None;
    let mut font_name = String::new();
    
    for candidate in &cjk_font_candidates {
        let path = fonts_dir.join(candidate);
        if let Some(data) = try_load_font(&path) {
            font_name = candidate.to_string();
            font_data = Some(data);
            break;
        }
    }

    let Some(data) = font_data else {
        return;
    };

    let mut fonts = FontDefinitions::default();
    
    fonts.font_data.insert(
        "cjk_font".to_owned(),
        FontData::from_owned(data)
            .tweak(egui::FontTweak {
                scale: 1.0,
                y_offset_factor: 0.0,
                y_offset: 0.0,
                baseline_offset_factor: 0.0,
            }),
    );

    if let Some(family) = fonts.families.get_mut(&FontFamily::Proportional) {
        family.push("cjk_font".to_owned());
    }
    
    if let Some(family) = fonts.families.get_mut(&FontFamily::Monospace) {
        family.push("cjk_font".to_owned());
    }

    ctx.set_fonts(fonts);
    
    #[cfg(debug_assertions)]
    eprintln!("Loaded CJK font: {}", font_name);
}
