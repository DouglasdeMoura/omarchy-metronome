use super::engine::Params;
use crate::json::Json;
use std::path::PathBuf;

// The metronome's memory: one small json file under the user's config dir.
// The backend owns it, like Flea's ui.json, because the wire already speaks
// json and the save path then costs one atomic rename.

fn config_base() -> Option<PathBuf> {
    match std::env::var_os("XDG_CONFIG_HOME") {
        Some(v) if !v.is_empty() => Some(PathBuf::from(v)),
        _ => {
            let home = std::env::var_os("HOME")?;
            if home.is_empty() {
                return None;
            }
            Some(PathBuf::from(home).join(".config"))
        }
    }
}

pub fn state_path() -> Option<PathBuf> {
    config_base().map(|base| base.join("metronome").join("state.json"))
}

// Before the app was renamed its state lived in ~/.config/pulse, a directory
// it shared with PulseAudio's cookie. A first run with no state of its own
// reads the old file once; the next save writes the new place, and nothing
// in the old directory is touched.
fn legacy_state_path() -> Option<PathBuf> {
    config_base().map(|base| base.join("pulse").join("state.json"))
}

pub fn load() -> Params {
    match state_path() {
        Some(path) => load_preferring(&path, legacy_state_path().as_deref()),
        None => Params::default(),
    }
}

fn load_preferring(path: &std::path::Path, legacy: Option<&std::path::Path>) -> Params {
    if !path.is_file() {
        if let Some(old) = legacy.filter(|p| p.is_file()) {
            return load_from(old);
        }
    }
    load_from(path)
}

fn load_from(path: &std::path::Path) -> Params {
    let mut params = Params::default();
    let Ok(body) = std::fs::read_to_string(path) else {
        return params;
    };
    match Json::parse(&body).and_then(|doc| params.apply_patch(&doc).map(|_| doc)) {
        Ok(_) => params,
        Err(e) => {
            // A corrupt state file is a fresh start, said once on stderr where
            // a developer looks, never a reason to refuse to run.
            eprintln!(
                "metronome: {} was not read ({}), starting from defaults",
                path.display(),
                e
            );
            Params::default()
        }
    }
}

pub fn save(params: &Params) -> Result<(), String> {
    let path = state_path().ok_or_else(|| "no config directory to save in".to_string())?;
    save_to(params, &path)
}

fn save_to(params: &Params, path: &std::path::Path) -> Result<(), String> {
    let dir = path
        .parent()
        .ok_or_else(|| "the state path has no parent".to_string())?;
    std::fs::create_dir_all(dir)
        .map_err(|e| format!("{} was not created ({})", dir.display(), e))?;
    let tmp = dir.join(".state.json.tmp");
    std::fs::write(&tmp, params.to_json().render() + "\n")
        .map_err(|e| format!("{} was not written ({})", tmp.display(), e))?;
    std::fs::rename(&tmp, path)
        .map_err(|e| format!("{} was not renamed ({})", path.display(), e))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_and_save_round_trip_through_a_temp_config() {
        let dir = std::env::temp_dir().join(format!("metronome-state-test-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        let path = dir.join("metronome/state.json");

        let p = Params {
            bpm: 97.0,
            beats: 7,
            denominator: 8,
            voices: [2, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 2, 3, 0, 0, 1],
            volume: 0.55,
            subdivision: 4,
            subpattern: 0b1011,
            subshape: 0b1011,
        };
        save_to(&p, &path).unwrap();

        let loaded = load_from(&path);
        assert_eq!(loaded, p);

        // A corrupt file falls back to defaults instead of taking the backend down.
        std::fs::write(dir.join("metronome").join("state.json"), "{not json").unwrap();
        assert_eq!(load_from(&path), Params::default());

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn a_first_run_reads_the_state_from_before_the_rename() {
        let dir = std::env::temp_dir().join(format!("metronome-legacy-test-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        let new = dir.join("metronome/state.json");
        let old = dir.join("pulse/state.json");

        let mut before = Params::default();
        before.bpm = 97.0;
        save_to(&before, &old).unwrap();
        assert_eq!(load_preferring(&new, Some(&old)), before, "no state of its own: the old one");
        assert!(!new.exists(), "reading never writes");

        let mut after = Params::default();
        after.bpm = 133.0;
        save_to(&after, &new).unwrap();
        assert_eq!(load_preferring(&new, Some(&old)), after, "its own state wins");
        assert!(old.is_file(), "the old file is left alone");

        std::fs::remove_dir_all(&dir).ok();
    }
}
