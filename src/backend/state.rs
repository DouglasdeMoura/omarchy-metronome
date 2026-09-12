use super::engine::Params;
use crate::json::Json;
use std::path::PathBuf;

// The metronome's memory: one small json file under the user's config dir.
// The backend owns it, like Flea's ui.json, because the wire already speaks
// json and the save path then costs one atomic rename.

pub fn state_path() -> Option<PathBuf> {
    let base = match std::env::var_os("XDG_CONFIG_HOME") {
        Some(v) if !v.is_empty() => PathBuf::from(v),
        _ => {
            let home = std::env::var_os("HOME")?;
            if home.is_empty() {
                return None;
            }
            PathBuf::from(home).join(".config")
        }
    };
    Some(base.join("pulse").join("state.json"))
}

pub fn load() -> Params {
    let mut params = Params::default();
    let Some(path) = state_path() else {
        return params;
    };
    let Ok(body) = std::fs::read_to_string(&path) else {
        return params;
    };
    match Json::parse(&body).and_then(|doc| params.apply_patch(&doc).map(|_| doc)) {
        Ok(_) => params,
        Err(e) => {
            // A corrupt state file is a fresh start, said once on stderr where
            // a developer looks, never a reason to refuse to run.
            eprintln!("pulse: {} was not read ({}), starting from defaults", path.display(), e);
            Params::default()
        }
    }
}

pub fn save(params: &Params) -> Result<(), String> {
    let path = state_path().ok_or_else(|| "no config directory to save in".to_string())?;
    let dir = path.parent().ok_or_else(|| "the state path has no parent".to_string())?;
    std::fs::create_dir_all(dir).map_err(|e| format!("{} was not created ({})", dir.display(), e))?;
    let tmp = dir.join(".state.json.tmp");
    std::fs::write(&tmp, params.to_json().render() + "\n")
        .map_err(|e| format!("{} was not written ({})", tmp.display(), e))?;
    std::fs::rename(&tmp, &path).map_err(|e| format!("{} was not renamed ({})", path.display(), e))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_and_save_round_trip_through_a_temp_config() {
        let dir = std::env::temp_dir().join(format!("pulse-state-test-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::env::set_var("XDG_CONFIG_HOME", &dir);

        let mut p = Params::default();
        p.bpm = 97.0;
        p.beats = 7;
        p.denominator = 8;
        p.voices = [2, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 2];
        p.volume = 0.55;
        save(&p).unwrap();

        let loaded = load();
        assert_eq!(loaded, p);

        // A corrupt file falls back to defaults instead of taking the backend down.
        std::fs::write(dir.join("pulse").join("state.json"), "{not json").unwrap();
        assert_eq!(load(), Params::default());

        std::env::remove_var("XDG_CONFIG_HOME");
        std::fs::remove_dir_all(&dir).ok();
    }
}
