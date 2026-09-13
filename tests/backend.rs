use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::Duration;

#[test]
fn voices_save_stop_and_quit_work_over_stdio() {
    let dir = std::env::temp_dir().join(format!("pulse-protocol-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_pulse"))
        .arg("--backend")
        .env("PULSE_SILENT", "1")
        .env("XDG_RUNTIME_DIR", &dir)
        .env("XDG_CONFIG_HOME", &dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    let output = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        for line in BufReader::new(output).lines() {
            tx.send(line.unwrap()).unwrap();
        }
    });
    // Startup completes before exercising all four wire voices.
    while !rx
        .recv_timeout(Duration::from_secs(3))
        .unwrap()
        .contains("\"t\":\"ready\"")
    {}
    writeln!(
        input,
        r#"{{"c":"save","bpm":400,"beats":4,"denominator":8,"voices":[3,2,1,0]}}"#
    )
    .unwrap();
    writeln!(input, r#"{{"c":"start"}}"#).unwrap();
    assert_eq!(
        rx.recv_timeout(Duration::from_secs(3)).unwrap(),
        r#"{"t":"started"}"#
    );
    for (beat, kind) in ["high", "medium", "low", "off"].iter().enumerate() {
        assert_eq!(
            rx.recv_timeout(Duration::from_secs(3)).unwrap(),
            format!(r#"{{"t":"beat","beat":{beat},"kind":"{kind}"}}"#),
        );
    }
    writeln!(input, r#"{{"c":"stop"}}"#).unwrap();
    loop {
        let line = rx.recv_timeout(Duration::from_secs(3)).unwrap();
        if line.contains("\"t\":\"stopped\"") {
            break;
        }
        assert!(line.contains("\"t\":\"beat\""));
    }
    let state = std::fs::read_to_string(dir.join("pulse/state.json")).unwrap();
    assert!(state.contains("\"voices\":[3,2,1,0,1,1,1,1,1,1,1,1]"));
    assert!(state.contains("\"denominator\":8"));
    writeln!(input, "{{\"c\":\"quit\"}}").unwrap();
    loop {
        let line = rx.recv_timeout(Duration::from_secs(3)).unwrap();
        if line.contains("quitready") {
            break;
        }
    }
    let deadline = std::time::Instant::now() + Duration::from_secs(1);
    let exited = loop {
        if child.try_wait().unwrap().is_some() {
            break true;
        }
        if std::time::Instant::now() >= deadline {
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    if !exited {
        child.kill().unwrap();
    }
    child.wait().unwrap();
    drop(input);
    reader.join().unwrap();
    std::fs::remove_dir_all(dir).unwrap();
    assert!(
        exited,
        "quitready must be followed by process exit without waiting for EOF"
    );
}
