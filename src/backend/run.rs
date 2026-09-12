use super::engine;
use super::proto::{self, Command};
use std::io::BufRead;

// pulse --backend: one json line per request on stdin, one json line per event
// on stdout. The process lives exactly as long as its stdin does, so a dead
// shell never leaves an orphan holding the audio device.

pub fn run() -> i32 {
    // PULSE_SILENT forces the silent clock, so a headless box or a test can
    // exercise the whole protocol without an audio device in the room.
    let silent_forced = std::env::var_os("PULSE_SILENT").is_some_and(|v| !v.is_empty());
    let initial = super::state::load();
    let handle = engine::launch(initial, silent_forced);

    let stdin = std::io::stdin();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        if line.trim().is_empty() {
            continue;
        }
        let cmd = match proto::parse(&line) {
            Ok(cmd) => cmd,
            Err(e) => {
                let _ = proto::emit(&proto::ev::error(&e));
                continue;
            }
        };
        if handle.cmd_tx.send(cmd).is_err() {
            // The control thread is gone; there is nothing left to serve.
            break;
        }
    }

    // stdin closed: the shell is gone or asked to quit. Either way the drain
    // is the same, and the control thread's join is the last word.
    let _ = handle.cmd_tx.send(Command::Quit);
    let _ = handle.control.join();
    0
}
