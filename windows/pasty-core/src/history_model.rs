use crate::clipboard_store::{ClipItem, PinBoard};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum HistoryShelf {
    #[default]
    Recent,
    Board(Uuid),
}

#[derive(Debug, Default)]
pub struct HistoryModel {
    pub items: Vec<ClipItem>,
    pub boards: Vec<PinBoard>,
    pub query: String,
    shelf: HistoryShelf,
    selected_id: Option<Uuid>,
    is_previewing: bool,
    focus_token: u64,
}

impl HistoryModel {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn shelf(&self) -> HistoryShelf {
        self.shelf
    }

    pub fn selected_id(&self) -> Option<Uuid> {
        self.selected_id
    }

    pub fn is_previewing(&self) -> bool {
        self.is_previewing
    }

    pub fn focus_token(&self) -> u64 {
        self.focus_token
    }

    pub fn pinned_count(&self) -> usize {
        self.items.iter().filter(|item| item.board_id.is_some()).count()
    }

    pub fn count_on(&self, board_id: Uuid) -> usize {
        self.items
            .iter()
            .filter(|item| item.board_id == Some(board_id))
            .count()
    }

    pub fn filtered(&self) -> Vec<&ClipItem> {
        let base: Vec<&ClipItem> = match self.shelf {
            HistoryShelf::Recent => self.items.iter().collect(),
            HistoryShelf::Board(id) => self
                .items
                .iter()
                .filter(|item| item.board_id == Some(id))
                .collect(),
        };
        let trimmed = self.query.trim();
        if trimmed.is_empty() {
            return base;
        }
        let needle = trimmed.to_lowercase();
        base.into_iter()
            .filter(|item| item.text.to_lowercase().contains(&needle))
            .collect()
    }

    pub fn prepare(
        &mut self,
        items: Vec<ClipItem>,
        boards: Vec<PinBoard>,
        shelf: HistoryShelf,
    ) {
        self.items = items;
        self.boards = boards;
        self.shelf = match shelf {
            HistoryShelf::Recent => HistoryShelf::Recent,
            HistoryShelf::Board(id) => {
                if self.boards.iter().any(|b| b.id == id) {
                    HistoryShelf::Board(id)
                } else {
                    HistoryShelf::Recent
                }
            }
        };
        self.query.clear();
        self.selected_id = self.filtered().first().map(|item| item.id);
        self.is_previewing = false;
    }

    pub fn show_recent(&mut self) {
        self.shelf = HistoryShelf::Recent;
        self.clamp_selection();
    }

    pub fn show_board(&mut self, id: Uuid) {
        if !self.boards.iter().any(|b| b.id == id) {
            return;
        }
        self.shelf = HistoryShelf::Board(id);
        self.clamp_selection();
    }

    pub fn show_pinned(&mut self) {
        if let Some(first) = self.boards.first() {
            self.show_board(first.id);
        }
    }

    /// Updates the in-memory pin. The store is saved by the caller.
    pub fn apply_pin(&mut self, id: Uuid, pinned: bool) {
        if pinned {
            let board_id = self.boards.first().map(|b| b.id);
            self.apply_assignment(id, board_id);
        } else {
            self.apply_assignment(id, None);
        }
    }

    pub fn apply_assignment(&mut self, id: Uuid, board_id: Option<Uuid>) {
        let Some(index) = self.items.iter().position(|item| item.id == id) else {
            return;
        };
        if let Some(board_id) = board_id {
            if !self.boards.iter().any(|b| b.id == board_id) {
                return;
            }
        }
        let visible: Vec<Uuid> = self.filtered().iter().map(|item| item.id).collect();
        // Match Swift: leavingShelf when on a board shelf and the selected card leaves it.
        let leaving = match (self.shelf, self.selected_id) {
            (HistoryShelf::Board(current), Some(sel)) if sel == id => board_id != Some(current),
            _ => false,
        };
        let mut neighbor = None;
        if leaving {
            if let Some(visible_index) = visible.iter().position(|vid| *vid == id) {
                if visible_index + 1 < visible.len() {
                    neighbor = Some(visible[visible_index + 1]);
                } else if visible_index > 0 {
                    neighbor = Some(visible[visible_index - 1]);
                }
            }
        }
        self.items[index].board_id = board_id;
        self.items[index].pinned = board_id.is_some();
        if leaving {
            self.selected_id = neighbor;
            self.is_previewing = false;
        }
    }

    pub fn reload(&mut self, items: Vec<ClipItem>, boards: Option<Vec<PinBoard>>) {
        let previous = self.selected_id;
        self.items = items;
        if let Some(boards) = boards {
            self.boards = boards;
        }
        if let HistoryShelf::Board(id) = self.shelf {
            if !self.boards.iter().any(|b| b.id == id) {
                self.shelf = HistoryShelf::Recent;
            }
        }
        if let Some(previous) = previous {
            if self.filtered().iter().any(|item| item.id == previous) {
                self.selected_id = Some(previous);
            } else {
                self.selected_id = self.filtered().first().map(|item| item.id);
            }
        } else {
            self.selected_id = self.filtered().first().map(|item| item.id);
        }
    }

    pub fn request_focus(&mut self) {
        self.focus_token = self.focus_token.wrapping_add(1);
    }

    pub fn move_selection(&mut self, delta: i32) {
        let visible: Vec<Uuid> = self.filtered().iter().map(|item| item.id).collect();
        if visible.is_empty() {
            self.selected_id = None;
            return;
        }
        let Some(selected_id) = self.selected_id else {
            self.selected_id = if delta >= 0 {
                visible.first().copied()
            } else {
                visible.last().copied()
            };
            return;
        };
        let Some(index) = visible.iter().position(|id| *id == selected_id) else {
            self.selected_id = if delta >= 0 {
                visible.first().copied()
            } else {
                visible.last().copied()
            };
            return;
        };
        let next = (index as i32 + delta).clamp(0, (visible.len() - 1) as i32) as usize;
        self.selected_id = Some(visible[next]);
    }

    pub fn select(&mut self, id: Uuid) {
        if self.filtered().iter().any(|item| item.id == id) {
            self.selected_id = Some(id);
        }
    }

    /// Drops one row. Selection moves to the following visible row, or the previous one at the end.
    pub fn remove(&mut self, id: Uuid) {
        if !self.items.iter().any(|item| item.id == id) {
            return;
        }
        let visible: Vec<Uuid> = self.filtered().iter().map(|item| item.id).collect();
        let was_selected = self.selected_id == Some(id);
        let mut neighbor = None;
        if was_selected {
            if let Some(index) = visible.iter().position(|vid| *vid == id) {
                if index + 1 < visible.len() {
                    neighbor = Some(visible[index + 1]);
                } else if index > 0 {
                    neighbor = Some(visible[index - 1]);
                }
            }
        }
        self.items.retain(|item| item.id != id);
        if was_selected {
            self.selected_id = neighbor;
            self.is_previewing = false;
        }
    }

    pub fn selected_item(&self) -> Option<&ClipItem> {
        let visible = self.filtered();
        if let Some(selected_id) = self.selected_id {
            if let Some(item) = visible.iter().find(|item| item.id == selected_id) {
                return Some(*item);
            }
        }
        visible.first().copied()
    }

    pub fn selected_text(&self) -> Option<&str> {
        self.selected_item().map(|item| item.text.as_str())
    }

    pub fn toggle_preview(&mut self) {
        if self.selected_item().is_none() {
            self.is_previewing = false;
            return;
        }
        self.is_previewing = !self.is_previewing;
    }

    pub fn close_preview(&mut self) {
        self.is_previewing = false;
    }

    pub fn set_query(&mut self, query: impl Into<String>) {
        self.query = query.into();
        self.clamp_selection();
    }

    fn clamp_selection(&mut self) {
        let visible = self.filtered();
        if let Some(selected_id) = self.selected_id {
            if visible.iter().any(|item| item.id == selected_id) {
                return;
            }
        }
        self.selected_id = visible.first().map(|item| item.id);
    }
}
