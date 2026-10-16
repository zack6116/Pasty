use crate::image_png::ImagePNG;
use chrono::{DateTime, SecondsFormat, Utc};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipItem {
    pub id: Uuid,
    pub text: String,
    pub copied_at: DateTime<Utc>,
    pub image_file: Option<String>,
    pub content_hash: Option<String>,
    pub pinned: bool,
    pub board_id: Option<Uuid>,
}

impl ClipItem {
    pub fn is_image(&self) -> bool {
        self.image_file.is_some()
    }
}

impl Serialize for ClipItem {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut map = serializer.serialize_map(None)?;
        map.serialize_entry("id", &self.id)?;
        map.serialize_entry("text", &self.text)?;
        map.serialize_entry(
            "copiedAt",
            &self.copied_at.to_rfc3339_opts(SecondsFormat::Secs, true),
        )?;
        if let Some(ref image_file) = self.image_file {
            map.serialize_entry("imageFile", image_file)?;
        }
        if let Some(ref content_hash) = self.content_hash {
            map.serialize_entry("contentHash", content_hash)?;
        }
        map.serialize_entry("pinned", &self.pinned)?;
        if let Some(ref board_id) = self.board_id {
            map.serialize_entry("boardID", board_id)?;
        }
        map.end()
    }
}

impl<'de> Deserialize<'de> for ClipItem {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct Raw {
            id: Uuid,
            text: String,
            #[serde(rename = "copiedAt")]
            copied_at: String,
            #[serde(rename = "imageFile", default)]
            image_file: Option<String>,
            #[serde(rename = "contentHash", default)]
            content_hash: Option<String>,
            #[serde(default)]
            pinned: bool,
            #[serde(rename = "boardID", default)]
            board_id: Option<Uuid>,
        }

        let raw = Raw::deserialize(deserializer)?;
        let copied_at = parse_iso8601(&raw.copied_at).map_err(serde::de::Error::custom)?;
        Ok(ClipItem {
            id: raw.id,
            text: raw.text,
            copied_at,
            image_file: raw.image_file,
            content_hash: raw.content_hash,
            pinned: raw.pinned,
            board_id: raw.board_id,
        })
    }
}

fn parse_iso8601(s: &str) -> Result<DateTime<Utc>, String> {
    DateTime::parse_from_rfc3339(s)
        .map(|dt| dt.with_timezone(&Utc))
        .or_else(|_| {
            chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%SZ")
                .map(|ndt| DateTime::from_naive_utc_and_offset(ndt, Utc))
        })
        .map_err(|e| e.to_string())
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PinBoard {
    pub id: Uuid,
    pub name: String,
}

impl PinBoard {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
        }
    }

    pub fn with_id(id: Uuid, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
        }
    }
}

pub struct ClipboardStore {
    items: Vec<ClipItem>,
    boards: Vec<PinBoard>,
    file_url: PathBuf,
    boards_url: PathBuf,
}

impl ClipboardStore {
    pub const MAX_ITEMS: usize = 100;
    pub const MAX_BOARDS: usize = 12;
    pub const MAX_BOARD_NAME_LENGTH: usize = 16;
    pub const DEFAULT_BOARD_NAME: &'static str = "固定";

    pub fn new(file_url: impl AsRef<Path>) -> Self {
        let file_url = file_url.as_ref().to_path_buf();
        let boards_url = file_url
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("boards.json");
        let mut store = Self {
            items: Vec::new(),
            boards: Vec::new(),
            file_url,
            boards_url,
        };
        store.load();
        store
    }

    pub fn items(&self) -> &[ClipItem] {
        &self.items
    }

    pub fn boards(&self) -> &[PinBoard] {
        &self.boards
    }

    pub fn add(&mut self, text: &str, at: DateTime<Utc>) -> bool {
        if text.trim().is_empty() {
            return false;
        }

        if let Some(index) = self
            .items
            .iter()
            .position(|item| item.image_file.is_none() && item.text == text)
        {
            let mut existing = self.items.remove(index);
            existing.copied_at = at;
            self.items.insert(0, existing);
        } else {
            self.items.insert(
                0,
                ClipItem {
                    id: Uuid::new_v4(),
                    text: text.to_string(),
                    copied_at: at,
                    image_file: None,
                    content_hash: None,
                    pinned: false,
                    board_id: None,
                },
            );
            self.trim_to_capacity();
        }
        self.save();
        true
    }

    /// Stores a PNG and moves an identical image to the front instead of duplicating it.
    pub fn add_image(&mut self, png_data: &[u8], at: DateTime<Utc>) -> bool {
        if !ImagePNG::is_png(png_data) {
            return false;
        }
        let hash = Self::digest(png_data);

        if let Some(index) = self.items.iter().position(|item| {
            item.content_hash.as_deref() == Some(&hash) && item.image_file.is_some()
        }) {
            let mut existing = self.items.remove(index);
            let previous_date = existing.copied_at;
            existing.copied_at = at;
            if let Some(ref image_file) = existing.image_file {
                if !self.file_exists(Some(image_file)) && !self.write_image(png_data, image_file) {
                    existing.copied_at = previous_date;
                    self.items.insert(index, existing);
                    return false;
                }
            }
            self.insert_chronologically(existing);
            self.save();
            return true;
        }

        let id = Uuid::new_v4();
        // Swift uses UUID.uuidString which is uppercase.
        let filename = format!("{}.png", id.to_string().to_uppercase());
        if !self.write_image(png_data, &filename) {
            return false;
        }
        let label = ImagePNG::pixel_label(png_data)
            .map(|size| format!("图片\n{size}"))
            .unwrap_or_else(|| "图片".to_string());
        self.insert_chronologically(ClipItem {
            id,
            text: label,
            copied_at: at,
            image_file: Some(filename),
            content_hash: Some(hash),
            pinned: false,
            board_id: None,
        });
        self.trim_to_capacity();
        self.save();
        true
    }

    pub fn contains_text(&self, text: &str) -> bool {
        self.items
            .iter()
            .any(|item| item.image_file.is_none() && item.text == text)
    }

    pub fn contains_image(&self, png_data: &[u8]) -> bool {
        if !ImagePNG::is_png(png_data) {
            return false;
        }
        let hash = Self::digest(png_data);
        self.items
            .iter()
            .any(|item| item.content_hash.as_deref() == Some(&hash) && item.image_file.is_some())
    }

    pub fn image_path(&self, item: &ClipItem) -> Option<PathBuf> {
        let image_file = item.image_file.as_ref()?;
        let path = self.images_directory().join(image_file);
        if path.is_file() {
            Some(path)
        } else {
            None
        }
    }

    pub fn image_data(&self, item: &ClipItem) -> Option<Vec<u8>> {
        let path = self.image_path(item)?;
        fs::read(path).ok()
    }

    /// Keeps a clip out of the 100-item trim. Unpinning can drop it if history is already full.
    pub fn set_pinned(&mut self, id: Uuid, pinned: bool) -> bool {
        if pinned {
            let board_id = if let Some(board) = self.boards.first() {
                board.id
            } else {
                match self.add_board(Self::DEFAULT_BOARD_NAME) {
                    Some(board) => board.id,
                    None => return false,
                }
            };
            self.assign(id, Some(board_id))
        } else {
            self.assign(id, None)
        }
    }

    pub fn add_board(&mut self, name: &str) -> Option<PinBoard> {
        let trimmed = Self::sanitize_board_name(name);
        if trimmed.is_empty() || self.boards.len() >= Self::MAX_BOARDS {
            return None;
        }
        if self.boards.iter().any(|b| b.name == trimmed) {
            return None;
        }
        let board = PinBoard::new(trimmed);
        self.boards.push(board.clone());
        self.save_boards();
        Some(board)
    }

    pub fn rename_board(&mut self, id: Uuid, name: &str) -> bool {
        let Some(index) = self.boards.iter().position(|b| b.id == id) else {
            return false;
        };
        let trimmed = Self::sanitize_board_name(name);
        if trimmed.is_empty() {
            return false;
        }
        if self
            .boards
            .iter()
            .any(|b| b.id != id && b.name == trimmed)
        {
            return false;
        }
        self.boards[index].name = trimmed;
        self.save_boards();
        true
    }

    /// Removes the board and returns its cards to ordinary history.
    pub fn delete_board(&mut self, id: Uuid) -> bool {
        if !self.boards.iter().any(|b| b.id == id) {
            return false;
        }
        self.boards.retain(|b| b.id != id);
        for item in &mut self.items {
            if item.board_id == Some(id) {
                item.board_id = None;
                item.pinned = false;
            }
        }
        self.trim_to_capacity();
        self.save_boards();
        self.save();
        true
    }

    pub fn assign(&mut self, id: Uuid, board_id: Option<Uuid>) -> bool {
        let Some(index) = self.items.iter().position(|item| item.id == id) else {
            return false;
        };
        if let Some(board_id) = board_id {
            if !self.boards.iter().any(|b| b.id == board_id) {
                return false;
            }
        }
        self.items[index].board_id = board_id;
        self.items[index].pinned = board_id.is_some();
        if board_id.is_none() {
            self.trim_to_capacity();
        }
        self.save();
        true
    }

    pub fn delete(&mut self, id: Uuid) -> bool {
        let Some(index) = self.items.iter().position(|item| item.id == id) else {
            return false;
        };
        let removed = self.items.remove(index);
        self.delete_image_file(removed.image_file.as_deref());
        self.save();
        true
    }

    pub fn clear(&mut self) {
        let removed: Vec<_> = self.items.drain(..).collect();
        for item in removed {
            self.delete_image_file(item.image_file.as_deref());
        }
        self.save();
    }

    fn load(&mut self) {
        self.boards = self.load_boards();
        let Ok(data) = fs::read(&self.file_url) else {
            return;
        };
        let Ok(mut decoded) = serde_json::from_slice::<Vec<ClipItem>>(&data) else {
            return;
        };
        let migrated = self.attach_legacy_pins(&mut decoded);
        let mut unpinned_kept = 0usize;
        let mut kept = Vec::with_capacity(decoded.len().min(Self::MAX_ITEMS));
        for item in decoded.iter().cloned() {
            if item.pinned {
                kept.push(item);
            } else if unpinned_kept < Self::MAX_ITEMS {
                unpinned_kept += 1;
                kept.push(item);
            }
        }
        let available: Vec<ClipItem> = kept
            .into_iter()
            .filter(|item| match &item.image_file {
                Some(name) => self.file_exists(Some(name)),
                None => true,
            })
            .collect();
        let changed = migrated || available.len() != decoded.len();
        self.items = available;
        if changed {
            self.save();
        }
    }

    /// Older history used a single pin flag. Those cards move onto the first board.
    fn attach_legacy_pins(&mut self, decoded: &mut [ClipItem]) -> bool {
        let needs_fallback = decoded
            .iter()
            .any(|item| item.pinned && item.board_id.is_none());
        if needs_fallback && self.boards.is_empty() {
            self.boards = vec![PinBoard::new(Self::DEFAULT_BOARD_NAME)];
            self.save_boards();
        }
        let fallback = self.boards.first().map(|b| b.id);
        let mut changed = false;
        for item in decoded.iter_mut() {
            if item.pinned && item.board_id.is_none() {
                item.board_id = fallback;
                changed = true;
            }
            if let Some(board_id) = item.board_id {
                if !self.boards.iter().any(|b| b.id == board_id) {
                    item.board_id = None;
                    changed = true;
                }
            }
            let pinned = item.board_id.is_some();
            if item.pinned != pinned {
                item.pinned = pinned;
                changed = true;
            }
        }
        changed
    }

    fn load_boards(&self) -> Vec<PinBoard> {
        let Ok(data) = fs::read(&self.boards_url) else {
            return Vec::new();
        };
        let Ok(decoded) = serde_json::from_slice::<Vec<PinBoard>>(&data) else {
            return Vec::new();
        };
        let mut seen = std::collections::HashSet::new();
        decoded
            .into_iter()
            .take(Self::MAX_BOARDS)
            .filter_map(|board| {
                let name = Self::sanitize_board_name(&board.name);
                if name.is_empty() || !seen.insert(name.clone()) {
                    None
                } else {
                    Some(PinBoard::with_id(board.id, name))
                }
            })
            .collect()
    }

    fn save_boards(&self) {
        if let Err(error) = write_json_sorted(&self.boards_url, &self.boards) {
            eprintln!("Pasty failed to save boards: {error}");
        }
    }

    fn sanitize_board_name(name: &str) -> String {
        let trimmed = name.replace('\n', " ").trim().to_string();
        trimmed.chars().take(Self::MAX_BOARD_NAME_LENGTH).collect()
    }

    fn save(&self) {
        if let Err(error) = write_json_sorted(&self.file_url, &self.items) {
            eprintln!("Pasty failed to save history: {error}");
        }
    }

    fn images_directory(&self) -> PathBuf {
        self.file_url
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("images")
    }

    fn insert_chronologically(&mut self, item: ClipItem) {
        let index = self
            .items
            .iter()
            .position(|existing| existing.copied_at <= item.copied_at)
            .unwrap_or(self.items.len());
        self.items.insert(index, item);
    }

    /// The cap applies to unpinned history. Pinned cards stay until they are unpinned or deleted.
    fn trim_to_capacity(&mut self) {
        while self.items.iter().filter(|item| !item.pinned).count() > Self::MAX_ITEMS {
            let Some(index) = self.items.iter().rposition(|item| !item.pinned) else {
                return;
            };
            let dropped = self.items.remove(index);
            self.delete_image_file(dropped.image_file.as_deref());
        }
    }

    fn write_image(&self, data: &[u8], filename: &str) -> bool {
        let dir = self.images_directory();
        if let Err(error) = fs::create_dir_all(&dir) {
            eprintln!("Pasty failed to save image: {error}");
            return false;
        }
        let path = dir.join(filename);
        match fs::write(&path, data) {
            Ok(()) => true,
            Err(error) => {
                eprintln!("Pasty failed to save image: {error}");
                false
            }
        }
    }

    fn file_exists(&self, filename: Option<&str>) -> bool {
        match filename {
            Some(name) => self.images_directory().join(name).is_file(),
            None => false,
        }
    }

    fn delete_image_file(&self, filename: Option<&str>) {
        if let Some(name) = filename {
            let _ = fs::remove_file(self.images_directory().join(name));
        }
    }

    fn digest(data: &[u8]) -> String {
        if let Some(fingerprint) = ImagePNG::pixel_fingerprint(data) {
            fingerprint
        } else {
            hex::encode(Sha256::digest(data))
        }
    }
}

fn write_json_sorted<T: Serialize>(path: &Path, value: &T) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let value = serde_json::to_value(value)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    let sorted = sort_value(value);
    let mut buf = Vec::new();
    let formatter = serde_json::ser::PrettyFormatter::with_indent(b"  ");
    let mut ser = serde_json::Serializer::with_formatter(&mut buf, formatter);
    sorted
        .serialize(&mut ser)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    let tmp = path.with_extension("tmp");
    {
        let mut file = fs::File::create(&tmp)?;
        file.write_all(&buf)?;
        file.sync_all()?;
    }
    fs::rename(&tmp, path)?;
    Ok(())
}

fn sort_value(value: serde_json::Value) -> serde_json::Value {
    match value {
        serde_json::Value::Object(map) => {
            let mut entries: Vec<_> = map.into_iter().collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            let mut out = serde_json::Map::new();
            for (k, v) in entries {
                out.insert(k, sort_value(v));
            }
            serde_json::Value::Object(out)
        }
        serde_json::Value::Array(arr) => {
            serde_json::Value::Array(arr.into_iter().map(sort_value).collect())
        }
        other => other,
    }
}
