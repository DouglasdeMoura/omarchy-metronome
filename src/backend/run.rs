use super::engine;
use super::proto::{self, Command};
use std::io::BufRead;
use std::os::unix::fs::OpenOptionsExt;

// metronome --backend: one json line per request on stdin, one json line per event
// on stdout. The process lives exactly as long as its stdin does, so a dead
// shell never leaves an orphan holding the audio device.

// One Metronome at a time: two metronomes playing the same bar a beat-length
// apart fuse and mask each other's clicks, and the player hears ticks
// vanish at random positions. The lock file is held for the backend's
// whole life; flock releases it even on a crash, so it never goes stale.

pub fn lock_path() -> std::path::PathBuf {
    // std has no getuid; /proc/self/status is the std-only answer, and the
    // number is only a namespace for the file name.
    let uid = std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines().find_map(|l| {
                l.strip_prefix("Uid:")
                    .and_then(|rest| rest.split_whitespace().next())
                    .and_then(|v| v.parse::<u32>().ok())
            })
        });
    let name = match uid {
        Some(id) => format!("metronome-{}.lock", id),
        None => "metronome.lock".to_string(),
    };
    match std::env::var_os("XDG_RUNTIME_DIR") {
        Some(v) if !v.is_empty() => std::path::PathBuf::from(v).join(name),
        _ => std::path::PathBuf::from("/tmp").join(name),
    }
}

// Try to become the one Metronome. Ok(file) holds the lock for the process's
// life; Err names the failure's wire code and says why.
pub fn acquire_instance_lock() -> Result<std::fs::File, (&'static str, String)> {
    let path = lock_path();
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(&path)
        .map_err(|e| ("lock_failed", format!("{} could not be opened ({})", path.display(), e)))?;
    file.try_lock().map(|()| file).map_err(|err| match err {
        std::fs::TryLockError::WouldBlock => (
            "already_running",
            format!("Metronome is already running ({})", path.display()),
        ),
        std::fs::TryLockError::Error(err) => (
            "lock_failed",
            format!("{} could not be locked ({})", path.display(), err),
        ),
    })
}

// A lock held by nobody: used by the GUI launch for a cheap early answer.
pub fn instance_is_running() -> bool {
    let path = lock_path();
    let Ok(file) = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(&path)
    else {
        return false;
    };
    matches!(file.try_lock(), Err(std::fs::TryLockError::WouldBlock))
}

pub fn run() -> i32 {
    // The lock lives in this binding on purpose: dropping it would hand the
    // single-instance claim back while the backend is still running.
    let _instance_lock = match acquire_instance_lock() {
        Ok(f) => f,
        Err((code, msg)) => {
            // The fresh shell gets the reason on the wire, where its error
            // caption shows it, and on stderr for the logs.
            eprintln!("metronome: {}", msg);
            let _ = proto::emit(&proto::ev::error(code, &msg, &msg));
            return 2;
        }
    };

    // METRONOME_SILENT forces the silent clock, so a headless box or a test can
    // exercise the whole protocol without an audio device in the room.
    let silent_forced = std::env::var_os("METRONOME_SILENT").is_some_and(|v| !v.is_empty());
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
                let _ = proto::emit(&proto::ev::error("request_unreadable", &e, &e));
                continue;
            }
        };
        let quitting = matches!(cmd, Command::Quit);
        if handle.cmd_tx.send(cmd).is_err() {
            // The control thread is gone; there is nothing left to serve.
            break;
        }
        if quitting {
            break;
        }
    }

    // stdin closed: the shell is gone or asked to quit. Either way the drain
    // is the same, and the control thread's join is the last word.
    let _ = handle.cmd_tx.send(Command::Quit);
    let _ = handle.control.join();
    0
}
