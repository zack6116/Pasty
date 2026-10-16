//! Shared clipboard history logic mirrored from Sources/PastyCore.

mod clipboard_store;
mod history_model;
mod image_png;
mod install_identity;
mod scroll_selection;

pub use clipboard_store::{ClipItem, ClipboardStore, PinBoard};
pub use history_model::{HistoryModel, HistoryShelf};
pub use image_png::ImagePNG;
pub use install_identity::{InstallIdentity, InstallReport};
pub use scroll_selection::ScrollSelection;
