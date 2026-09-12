use std::path::PathBuf;

// Where the QML lives: PULSE_UI first, so a checkout always wins for its own
// runs; then beside the binary; then a capped walk up the tree, which finds
// both the cargo checkout (`target/release/pulse` → `ui/` at the repo root)
// and a prefixed install (`/usr/local/bin/pulse` → `/usr/local/share/pulse/ui`);
// then the system path pacman owns.
pub fn ui_dir() -> Option<PathBuf> {
    if let Some(v) = std::env::var_os("PULSE_UI") {
        if !v.is_empty() {
            return Some(PathBuf::from(v));
        }
    }
    let exe = std::env::current_exe().ok()?;
    let mut dir = exe.parent().map(PathBuf::from)?;
    if dir.join("ui").join("shell.qml").is_file() {
        return Some(dir.join("ui"));
    }
    for _ in 0..4 {
        let repo = dir.join("ui");
        if repo.join("shell.qml").is_file() {
            return Some(repo);
        }
        let installed = dir.join("share/pulse/ui");
        if installed.join("shell.qml").is_file() {
            return Some(installed);
        }
        if !dir.pop() {
            break;
        }
    }
    let system = PathBuf::from("/usr/share/pulse/ui");
    if system.join("shell.qml").is_file() {
        return Some(system);
    }
    None
}

pub fn has_display() -> bool {
    ["WAYLAND_DISPLAY", "DISPLAY"].iter().any(|var| {
        std::env::var_os(var).is_some_and(|v| !v.is_empty())
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn a_display_is_wayland_or_x() {
        // The assertion runs on the machine building Pulse; headless CI keeps
        // both unset, a desktop always has one. Either way the answer is honest.
        let has = super::has_display();
        let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some_and(|v| !v.is_empty());
        let x = std::env::var_os("DISPLAY").is_some_and(|v| !v.is_empty());
        assert_eq!(has, wayland || x);
    }
}
