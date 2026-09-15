use crate::paths;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

// exec rather than spawn, so the shell replaces this process and no pid is
// orphaned between the two halves of one app.
pub fn exec_qs(ui: &Path) -> i32 {
    let mut cmd = Command::new("qs");
    cmd.arg("-p").arg(ui.join("shell.qml"));
    // The backend binary the shell calls back into is this one, unless the
    // caller pinned it — METRONOME_BIN is the dev seam, the same idea as FLEA_BIN.
    if std::env::var_os("METRONOME_BIN").is_none_or(|v| v.is_empty()) {
        if let Ok(binary) = std::env::current_exe() {
            cmd.env("METRONOME_BIN", binary);
        }
    }
    // exec() only returns on failure; the reason is elided, never shown raw.
    let _ = cmd.exec();
    eprintln!("omarchy-metronome: could not start the shell, qs is not on PATH or failed to run");
    1
}

pub fn launch() -> i32 {
    // One Metronome at a time: a second metronome half a beat out from the first
    // makes ticks fuse and vanish. Answer before a window is spawned so the
    // second launch is a polite no-op, not a broken shell.
    if paths::backend_running() {
        eprintln!("omarchy-metronome: Metronome is already running");
        return 0;
    }
    if !paths::has_display() {
        eprintln!("omarchy-metronome: there is no graphical session to open a window in");
        return 2;
    }
    match paths::ui_dir() {
        Some(ui) => exec_qs(&ui),
        None => {
            eprintln!(
                "omarchy-metronome: the shell config is missing, set METRONOME_UI or install /usr/share/omarchy-metronome/ui"
            );
            2
        }
    }
}
