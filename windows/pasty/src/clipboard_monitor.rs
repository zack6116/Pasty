#![cfg(windows)]

use clipboard_win::{formats, get_clipboard_string, set_clipboard};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use windows::core::w;
use windows::Win32::Foundation::{HANDLE, HGLOBAL};
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, GetClipboardData, GetClipboardSequenceNumber, OpenClipboard,
    RegisterClipboardFormatW, SetClipboardData,
};
use windows::Win32::System::Memory::{
    GlobalAlloc, GlobalLock, GlobalSize, GlobalUnlock, GMEM_MOVEABLE,
};

/// Polls the Windows clipboard for text and PNG images.
pub struct ClipboardMonitor {
    interval: Duration,
    ignore_sequence: Arc<AtomicU64>,
    stop: Arc<AtomicU64>,
}

impl ClipboardMonitor {
    pub fn new(interval: Duration) -> Self {
        Self {
            interval,
            ignore_sequence: Arc::new(AtomicU64::new(0)),
            stop: Arc::new(AtomicU64::new(0)),
        }
    }

    pub fn start<F, G>(self, mut on_text: F, mut on_image: G) -> MonitorHandle
    where
        F: FnMut(String) + Send + 'static,
        G: FnMut(Vec<u8>) + Send + 'static,
    {
        let interval = self.interval;
        let ignore_sequence = Arc::clone(&self.ignore_sequence);
        let stop = Arc::clone(&self.stop);
        let join = thread::spawn(move || {
            let mut last_seq = current_sequence();
            while stop.load(Ordering::SeqCst) == 0 {
                thread::sleep(interval);
                let seq = current_sequence();
                if seq == last_seq {
                    continue;
                }
                last_seq = seq;
                if ignore_sequence.load(Ordering::SeqCst) == seq {
                    continue;
                }
                if let Some(text) = read_plain_text() {
                    if !text.trim().is_empty() {
                        on_text(text);
                        continue;
                    }
                }
                if let Some(png) = read_png() {
                    on_image(png);
                }
            }
        });
        MonitorHandle {
            ignore_sequence: self.ignore_sequence,
            stop: self.stop,
            join: Some(join),
        }
    }
}

pub struct MonitorHandle {
    ignore_sequence: Arc<AtomicU64>,
    stop: Arc<AtomicU64>,
    join: Option<thread::JoinHandle<()>>,
}

impl MonitorHandle {
    pub fn write_text(&self, text: &str) -> bool {
        match set_clipboard(formats::Unicode, text) {
            Ok(()) => {
                self.ignore_sequence
                    .store(current_sequence(), Ordering::SeqCst);
                true
            }
            Err(_) => false,
        }
    }

    pub fn write_image_png(&self, png: &[u8]) -> bool {
        if write_png_clipboard(png) {
            self.ignore_sequence
                .store(current_sequence(), Ordering::SeqCst);
            true
        } else {
            false
        }
    }

    pub fn stop(mut self) {
        self.stop.store(1, Ordering::SeqCst);
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}

impl Drop for MonitorHandle {
    fn drop(&mut self) {
        self.stop.store(1, Ordering::SeqCst);
    }
}

fn current_sequence() -> u64 {
    unsafe { GetClipboardSequenceNumber() as u64 }
}

fn read_plain_text() -> Option<String> {
    get_clipboard_string().ok().filter(|s| !s.is_empty())
}

fn png_clipboard_format() -> u32 {
    unsafe { RegisterClipboardFormatW(w!("PNG")) }
}

fn read_png() -> Option<Vec<u8>> {
    unsafe {
        OpenClipboard(None).ok()?;
        let result = read_png_unlocked();
        let _ = CloseClipboard();
        result
    }
}

unsafe fn read_png_unlocked() -> Option<Vec<u8>> {
    let format = png_clipboard_format();
    if format == 0 {
        return None;
    }
    let handle = GetClipboardData(format).ok()?;
    let bytes = hglobal_to_vec(handle)?;
    if pasty_core::ImagePNG::is_png(&bytes) {
        Some(bytes)
    } else {
        None
    }
}

fn write_png_clipboard(png: &[u8]) -> bool {
    if !pasty_core::ImagePNG::is_png(png) {
        return false;
    }
    unsafe {
        if OpenClipboard(None).is_err() {
            return false;
        }
        let ok = write_png_unlocked(png);
        let _ = CloseClipboard();
        ok
    }
}

unsafe fn write_png_unlocked(png: &[u8]) -> bool {
    if EmptyClipboard().is_err() {
        return false;
    }
    let format = png_clipboard_format();
    if format == 0 {
        return false;
    }
    let Some(handle) = vec_to_hglobal(png) else {
        return false;
    };
    SetClipboardData(format, HANDLE(handle.0)).is_ok()
}

unsafe fn hglobal_to_vec(handle: HANDLE) -> Option<Vec<u8>> {
    let hglobal = HGLOBAL(handle.0);
    let ptr = GlobalLock(hglobal);
    if ptr.is_null() {
        return None;
    }
    let size = GlobalSize(hglobal);
    let slice = std::slice::from_raw_parts(ptr as *const u8, size);
    let bytes = slice.to_vec();
    let _ = GlobalUnlock(hglobal);
    Some(bytes)
}

unsafe fn vec_to_hglobal(bytes: &[u8]) -> Option<HGLOBAL> {
    let hglobal = GlobalAlloc(GMEM_MOVEABLE, bytes.len()).ok()?;
    let ptr = GlobalLock(hglobal);
    if ptr.is_null() {
        return None;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr as *mut u8, bytes.len());
    let _ = GlobalUnlock(hglobal);
    Some(hglobal)
}
