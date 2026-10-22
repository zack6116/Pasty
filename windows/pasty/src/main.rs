#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(windows)]
mod app;
#[cfg(windows)]
mod clipboard_monitor;
#[cfg(windows)]
mod hotkey;
#[cfg(windows)]
mod install_reporter;
#[cfg(windows)]
mod panel;
mod paths;
#[cfg(windows)]
mod settings;
#[cfg(windows)]
mod share;
#[cfg(windows)]
mod tray;

fn main() {
    #[cfg(windows)]
    {
        if let Err(error) = app::run() {
            eprintln!("Pasty failed to start: {error}");
            std::process::exit(1);
        }
    }

    #[cfg(not(windows))]
    {
        println!("Windows only");
    }
}
