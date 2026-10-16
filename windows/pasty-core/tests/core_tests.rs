use chrono::{DateTime, TimeZone, Utc};
use pasty_core::{
    ClipboardStore, HistoryModel, HistoryShelf, ImagePNG, InstallIdentity, InstallReport,
    ScrollSelection,
};
use std::fs;
use tempfile::tempdir;
use uuid::Uuid;

fn ts(secs: i64) -> DateTime<Utc> {
    Utc.timestamp_opt(secs, 0).unwrap()
}

fn with_store(body: impl FnOnce(&mut ClipboardStore)) {
    let dir = tempdir().unwrap();
    let mut store = ClipboardStore::new(dir.path().join("history.json"));
    body(&mut store);
}

fn solid_png(width: u32, height: u32, red: u8) -> Vec<u8> {
    let mut img = image::RgbaImage::new(width, height);
    for pixel in img.pixels_mut() {
        *pixel = image::Rgba([red, 0, 0, 255]);
    }
    let mut out = Vec::new();
    let encoder = image::codecs::png::PngEncoder::new(&mut out);
    image::DynamicImage::ImageRgba8(img)
        .write_with_encoder(encoder)
        .unwrap();
    out
}

#[test]
fn blank_text_rejected_and_newest_first() {
    with_store(|store| {
        assert!(!store.add("   \n\t", ts(1_700_000_000)));
        assert!(store.items().is_empty());
        assert!(store.add("alpha", ts(1_700_000_000)));
        assert!(store.add("beta", ts(1_700_000_100)));
        assert_eq!(
            store.items().iter().map(|i| i.text.as_str()).collect::<Vec<_>>(),
            ["beta", "alpha"]
        );
        assert_eq!(
            store.items().iter().map(|i| i.copied_at).collect::<Vec<_>>(),
            [ts(1_700_000_100), ts(1_700_000_000)]
        );
    });
}

#[test]
fn duplicate_moves_front_keeps_id() {
    with_store(|store| {
        store.add("alpha", ts(1_700_000_000));
        store.add("beta", ts(1_700_000_100));
        store.add("gamma", ts(1_700_000_200));
        let original_id = store.items().iter().find(|i| i.text == "beta").unwrap().id;
        let reused_at = ts(1_700_000_300);
        assert!(store.add("beta", reused_at));
        assert_eq!(
            store.items().iter().map(|i| i.text.as_str()).collect::<Vec<_>>(),
            ["beta", "gamma", "alpha"]
        );
        assert_eq!(store.items()[0].id, original_id);
        assert_eq!(store.items()[0].copied_at, reused_at);
        assert_eq!(store.items().len(), 3);
    });
}

#[test]
fn items_capped_at_one_hundred() {
    with_store(|store| {
        for index in 0..120 {
            store.add(
                &format!("item-{index}"),
                ts(1_700_000_000 + index),
            );
        }
        assert_eq!(store.items().len(), ClipboardStore::MAX_ITEMS);
        assert_eq!(store.items().first().unwrap().text, "item-119");
        assert_eq!(store.items().last().unwrap().text, "item-20");
    });
}

#[test]
fn duplicate_at_capacity_does_not_drop_others() {
    with_store(|store| {
        for index in 0..100 {
            store.add(
                &format!("item-{index}"),
                ts(1_700_000_000 + index),
            );
        }
        store.add("item-5", ts(1_700_000_500));
        assert_eq!(store.items().len(), 100);
        assert_eq!(store.items().first().unwrap().text, "item-5");
        assert!(store.items().iter().any(|i| i.text == "item-0"));
        assert!(store.items().iter().any(|i| i.text == "item-99"));
    });
}

#[test]
fn history_json_round_trip() {
    let dir = tempdir().unwrap();
    let file = dir.path().join("history.json");
    let mut store = ClipboardStore::new(&file);
    store.add("older", ts(1_700_000_000));
    store.add("newer", ts(1_700_000_050));
    let reloaded = ClipboardStore::new(&file);
    assert_eq!(reloaded.items(), store.items());
}

#[test]
fn clear_removes_persisted_history() {
    let dir = tempdir().unwrap();
    let file = dir.path().join("history.json");
    let mut store = ClipboardStore::new(&file);
    store.add("keep-me", ts(1_700_000_000));
    store.clear();
    let reloaded = ClipboardStore::new(&file);
    assert!(store.items().is_empty());
    assert!(reloaded.items().is_empty());
}

#[test]
fn pin_boards_and_legacy_pin() {
    let dir = tempdir().unwrap();
    let file = dir.path().join("history.json");
    let mut store = ClipboardStore::new(&file);
    store.add("keep", ts(1_700_000_000));
    let pinned_id = store.items()[0].id;
    assert!(store.set_pinned(pinned_id, true));
    assert_eq!(
        store.boards().iter().map(|b| b.name.as_str()).collect::<Vec<_>>(),
        ["固定"]
    );

    for index in 0..120 {
        store.add(
            &format!("item-{index}"),
            ts(1_700_000_100 + index),
        );
    }
    assert!(store
        .items()
        .iter()
        .any(|i| i.id == pinned_id && i.pinned));
    assert_eq!(
        store.items().iter().filter(|i| !i.pinned).count(),
        ClipboardStore::MAX_ITEMS
    );

    let work = store.add_board("  工作\n").unwrap();
    assert_eq!(work.name, "工作");
    assert!(store.add_board("工作").is_none());
    assert!(store.add_board("   ").is_none());

    // Legacy pin JSON
    let legacy_dir = tempdir().unwrap();
    let legacy_file = legacy_dir.path().join("history.json");
    fs::write(
        &legacy_file,
        r#"[
  {
    "copiedAt" : "2023-11-14T22:13:20Z",
    "id" : "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
    "pinned" : true,
    "text" : "legacy"
  }
]"#,
    )
    .unwrap();
    let legacy = ClipboardStore::new(&legacy_file);
    assert_eq!(
        legacy.boards().iter().map(|b| b.name.as_str()).collect::<Vec<_>>(),
        ["固定"]
    );
    assert_eq!(legacy.items()[0].board_id, Some(legacy.boards()[0].id));
    assert!(legacy.items()[0].pinned);
}

#[test]
fn scroll_selection_matches_arrows() {
    let mut accumulated = 0.0;
    assert_eq!(ScrollSelection::consume(1.0, false, &mut accumulated), -1);
    assert_eq!(ScrollSelection::consume(-1.0, false, &mut accumulated), 1);

    let mut trackpad = 0.0;
    assert_eq!(ScrollSelection::consume(20.0, true, &mut trackpad), 0);
    assert_eq!(ScrollSelection::consume(20.0, true, &mut trackpad), -1);
}

#[test]
fn history_model_selection_search_and_remove() {
    with_store(|store| {
        store.add("Alpha", ts(1_700_000_000));
        store.add("beta", ts(1_700_000_100));
        let mut model = HistoryModel::new();
        model.prepare(store.items().to_vec(), vec![], HistoryShelf::Recent);

        assert_eq!(model.selected_text(), Some("beta"));
        model.move_selection(1);
        assert_eq!(model.selected_text(), Some("Alpha"));
        model.move_selection(1);
        assert_eq!(model.selected_text(), Some("Alpha"));
        model.move_selection(-1);
        assert_eq!(model.selected_text(), Some("beta"));

        model.set_query("alp");
        assert_eq!(
            model.filtered().iter().map(|i| i.text.as_str()).collect::<Vec<_>>(),
            ["Alpha"]
        );
        assert_eq!(model.selected_text(), Some("Alpha"));
        model.set_query("missing");
        assert!(model.filtered().is_empty());
        assert_eq!(model.selected_text(), None);
    });

    with_store(|store| {
        store.add("older", ts(1_700_000_000));
        store.add("middle", ts(1_700_000_100));
        store.add("newer", ts(1_700_000_200));
        let mut model = HistoryModel::new();
        model.prepare(store.items().to_vec(), store.boards().to_vec(), HistoryShelf::Recent);
        model.move_selection(1);
        model.toggle_preview();
        let middle = model.selected_item().unwrap().clone();
        model.remove(middle.id);
        assert_eq!(
            model.items.iter().map(|i| i.text.as_str()).collect::<Vec<_>>(),
            ["newer", "older"]
        );
        assert_eq!(model.selected_text(), Some("older"));
        assert!(!model.is_previewing());
    });
}

#[test]
fn pinned_shelf_filters() {
    with_store(|store| {
        store.add("older", ts(1_700_000_000));
        store.add("middle", ts(1_700_000_100));
        store.add("newer", ts(1_700_000_200));
        let middle = store.items()[1].id;
        store.set_pinned(middle, true);

        let mut model = HistoryModel::new();
        model.prepare(store.items().to_vec(), store.boards().to_vec(), HistoryShelf::Recent);
        assert_eq!(model.shelf(), HistoryShelf::Recent);
        assert_eq!(model.filtered().len(), 3);
        assert_eq!(model.pinned_count(), 1);

        model.show_pinned();
        assert_eq!(
            model.filtered().iter().map(|i| i.text.as_str()).collect::<Vec<_>>(),
            ["middle"]
        );
        model.apply_pin(middle, false);
        assert!(model.filtered().is_empty());
        model.show_recent();
        assert_eq!(model.filtered().len(), 3);
    });
}

#[test]
fn images_stored_and_deduped() {
    let dir = tempdir().unwrap();
    let file = dir.path().join("history.json");
    let mut store = ClipboardStore::new(&file);
    let image = solid_png(2, 3, 40);
    assert!(!store.add_image(b"not-a-png", ts(1_700_000_000)));
    assert!(store.add_image(&image, ts(1_700_000_000)));
    assert!(store.items()[0].is_image());
    assert_eq!(store.items()[0].text, "图片\n2×3");
    assert_eq!(store.image_data(&store.items()[0]).as_deref(), Some(image.as_slice()));
    let original_id = store.items()[0].id;

    store.add("note", ts(1_700_000_100));
    assert!(store.add_image(&image, ts(1_700_000_100)));
    assert_eq!(store.items()[0].id, original_id);
    assert_eq!(store.items().len(), 2);
    assert!(store.contains_image(&image));
    assert!(store.contains_text("note"));
}

#[test]
fn install_id_stable_and_report_schema() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("install_id");
    let first = InstallIdentity::install_id(&path);
    let second = InstallIdentity::install_id(&path);
    assert_eq!(first, second);
    assert!(Uuid::parse_str(&first).is_ok());

    let report = InstallReport::new(
        "pasty",
        &first,
        "1.2.0",
        "Windows 11",
        "unknown",
        "x86_64",
        "zh_CN",
    );
    let data = serde_json::to_vec(&report).unwrap();
    let object: serde_json::Value = serde_json::from_slice(&data).unwrap();
    assert_eq!(object["product"], "pasty");
    assert_eq!(object["installId"], first);
    assert_eq!(object["appVersion"], "1.2.0");
}

#[test]
fn blank_does_not_erase_history() {
    with_store(|store| {
        store.add("alpha", ts(1_700_000_000));
        assert!(!store.add(" \n ", ts(1_700_000_100)));
        assert_eq!(
            store.items().iter().map(|i| i.text.as_str()).collect::<Vec<_>>(),
            ["alpha"]
        );
    });
}

#[test]
fn png_signature_helper() {
    let png = solid_png(1, 1, 1);
    assert!(ImagePNG::is_png(&png));
    assert_eq!(ImagePNG::pixel_label(&png).as_deref(), Some("1×1"));
}
