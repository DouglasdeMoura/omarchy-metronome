use super::engine::Params;
use crate::json::Json;

// The one place the protocol's request half is interpreted. Every line the UI
// sends names its command in "c"; anything else is a parse error the backend
// answers with an error event, never a silent drop.
pub enum Command {
    Hello,
    Start,
    Stop,
    Toggle,
    Params(Json),
    Save(Json),
    Quit,
}

pub fn parse(line: &str) -> Result<Command, String> {
    let body = Json::parse(line)?;
    match body.get("c").and_then(|v| v.as_str()) {
        Some("hello") => Ok(Command::Hello),
        Some("start") => Ok(Command::Start),
        Some("stop") => Ok(Command::Stop),
        Some("toggle") => Ok(Command::Toggle),
        Some("params") => Ok(Command::Params(body)),
        Some("save") => Ok(Command::Save(body)),
        Some("quit") => Ok(Command::Quit),
        Some(other) => Err(format!("unknown command '{}'", other)),
        None => Err("every request names its command in \"c\"".to_string()),
    }
}

// The event half, one constructor per line, so the wire has exactly one author
// per message and docs/protocol.md can be checked against this file alone.
pub mod ev {
    use super::{Json, Params};

    pub fn state(p: &Params) -> String {
        let Json::Obj(mut fields) = p.to_json() else {
            unreachable!()
        };
        fields.insert(0, ("t".into(), Json::str("state")));
        Json::Obj(fields).render()
    }

    pub fn ready(device: &str, rate: u32, silent: bool) -> String {
        Json::obj(vec![
            ("t", Json::str("ready")),
            ("device", Json::str(device)),
            ("rate", Json::int(rate as i64)),
            ("silent", Json::Bool(silent)),
        ])
        .render()
    }

    pub fn started() -> String {
        Json::obj(vec![("t", Json::str("started"))]).render()
    }

    pub fn beat(beat: u32, kind: &str) -> String {
        Json::obj(vec![
            ("t", Json::str("beat")),
            ("beat", Json::int(beat as i64)),
            ("kind", Json::str(kind)),
        ])
        .render()
    }

    pub fn stopped(beats: u64) -> String {
        Json::obj(vec![
            ("t", Json::str("stopped")),
            ("beats", Json::int(beats as i64)),
        ])
        .render()
    }

    pub fn error(msg: &str) -> String {
        Json::obj(vec![("t", Json::str("error")), ("msg", Json::str(msg))]).render()
    }

    pub fn quitready() -> String {
        Json::obj(vec![("t", Json::str("quitready"))]).render()
    }
}

// stdout is the event channel's other end; one locked write per line keeps a
// beat and a state reply from interleaving mid-line.
pub fn emit(line: &str) -> std::io::Result<()> {
    use std::io::Write;
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    lock.write_all(line.as_bytes())?;
    lock.write_all(b"\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_command_parses() {
        for (line, want) in [
            (r#"{"c":"hello"}"#, "hello"),
            (r#"{"c":"start"}"#, "start"),
            (r#"{"c":"stop"}"#, "stop"),
            (r#"{"c":"toggle"}"#, "toggle"),
            (r#"{"c":"params","bpm":140}"#, "params"),
            (r#"{"c":"save","bpm":140}"#, "save"),
            (r#"{"c":"quit"}"#, "quit"),
        ] {
            let cmd = parse(line).unwrap_or_else(|e| panic!("{}: {}", line, e));
            let name = match cmd {
                Command::Hello => "hello",
                Command::Start => "start",
                Command::Stop => "stop",
                Command::Toggle => "toggle",
                Command::Params(_) => "params",
                Command::Save(_) => "save",
                Command::Quit => "quit",
            };
            assert_eq!(name, want);
        }
    }

    #[test]
    fn garbage_is_an_error_not_a_crash() {
        assert!(parse("").is_err());
        assert!(parse("{}").is_err());
        assert!(parse(r#"{"c":"explode"}"#).is_err());
        assert!(parse(r#"{"c":42}"#).is_err());
        assert!(parse("start").is_err());
    }

    #[test]
    fn event_lines_are_valid_json_with_a_t() {
        let p = Params::default();
        for line in [
            ev::state(&p),
            ev::ready("pipewire", 48_000, false),
            ev::started(),
            ev::beat(0, "high"),
            ev::stopped(12),
            ev::error("boom"),
            ev::quitready(),
        ] {
            let parsed = Json::parse(&line).unwrap_or_else(|e| panic!("{}: {}", line, e));
            assert!(parsed.get("t").unwrap().as_str().is_some());
        }
        let beat = Json::parse(&ev::beat(3, "accent")).unwrap();
        assert_eq!(beat.get("beat").unwrap().as_u32(), Some(3));
        assert_eq!(beat.get("kind").unwrap().as_str(), Some("accent"));
        let ready = Json::parse(&ev::ready("default", 44_100, true)).unwrap();
        assert_eq!(ready.get("rate").unwrap().as_u32(), Some(44_100));
        assert_eq!(ready.get("silent"), Some(&Json::Bool(true)));
    }
}
