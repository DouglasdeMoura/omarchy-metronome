# AGENTS.md

Notes for working on Metronome, an Omarchy app in Flea's shape:
a std-only Rust backend speaking json lines over stdio, a Quickshell/QML
frontend, and a look that follows the live Omarchy theme.

## Commands

```sh
cargo build --release          # the binary also finds ./ui relative to a checkout
cargo test                     # timeline, protocol, json, state, catalogues — all offline
bash tests/ui.sh               # the QML frontend, offscreen
./target/release/metronome     # launch the app (needs a wayland session + qs)
```

Headless / CI:

```sh
METRONOME_SILENT=1 ./target/release/metronome --backend < lines-of-json
```

Launch `target/release/metronome`, never `qs -p ui/shell.qml` and never a stale
`target/release/pulse` from before the rename: only the current binary sets
`METRONOME_BIN`, and without it the window reports that the backend could not
be started.

## The shape

- `src/main.rs` — `--backend`, `--version`, anything else is a window.
- `src/gui.rs` — execs `qs -p <ui>/shell.qml`, passing `METRONOME_BIN` so the QML
  spawns this exact binary as its backend.
- `src/paths.rs` — finds the ui dir: `METRONOME_UI`, beside the binary, up the
  tree to a checkout or a prefixed install, then `/usr/share/metronome/ui`.
- `src/backend/run.rs` — the stdin loop and the single-instance lock in
  `$XDG_RUNTIME_DIR`.
- `src/backend/proto.rs` — the one interpreter of docs/protocol.md; the wire
  has exactly one author per message, and `ERROR_CODES` lists every error.
- `src/backend/engine.rs` — the metronome. The audio callback owns a
  callback-owned timeline and touches only atomics from the control plane;
  params are read per click, so every change lands at the next boundary.
  Events go out one channel; the out thread prints them. No audio device
  means the silent clock takes over and `ready` says `silent: true`.
  The stream never carries digital silence: a -74 dBFS noise floor runs
  under everything, because Bluetooth earbuds sleep on silence and eat the
  next tick. Tests bound quiet by `FLOOR_AMP`, never by zero.
- `src/backend/state.rs` — `~/.config/metronome/state.json`. With no state of
  its own, a first run reads `~/.config/pulse/state.json` once; that directory
  also holds PulseAudio's cookie, so nothing there is ever written.
- `src/json.rs` — hand-rolled json (parse + render) since the backend is
  std-only. cpal is the single dependency, and the only one planned.
- `src/i18n_check.rs` — test-only: holds the catalogues to the UI's keys.
- `ui/shell.qml` — the window: app id `dev.douglasmoura.metronome`, 377×610.
- `ui/Main.qml` — the one screen, its focus ring, and the time signature,
  subdivision and keys dialogs.
- `ui/Rhythm.js` — the subdivision catalogue and its names. A cell is a
  division into 1–6 slots, a `subpattern` of the slots that tick, and a
  `subshape` of the slots that start a figure.
- `ui/NoteFigure.qml` — draws a cell as notation and measures its ink, so a
  holder can centre the notes rather than the box.
- `ui/Theme.qml` — reads `~/.local/state/omarchy/current/theme/{colors,shell}.toml`
  and watches `theme.name` (rewritten in place by omarchy-theme-set, which is
  why the watch survives theme switches — an inotify on a file inside the
  theme dir would die with the old inode). hyprctl answers rounding and
  reduced motion. Theme *name* must be taken in `onLoaded`; a name read in
  the watch handler lags one theme behind.
- `ui/I18n.qml` — the locale and its catalogues in `ui/i18n`; every word on
  screen is `I18n.tr(key)`. See docs/i18n.md.
- `ui/Backend.qml` — the process bridge: queue before spawn, SplitParser on
  stdout, one signal per protocol event.

## Rules this repo keeps

- The backend stays std-only (cpal aside); no serde, no clap.
- New protocol messages get: a constructor in proto.rs, a branch in
  Backend.qml's receive(), a row in docs/protocol.md, and a test.
- Timeline changes get a test against `Timeline` directly — it is the shared
  core of both the audio callback and the silent clock.
- Everything user-visible is a theme token from Theme.qml; there are no
  literal colors outside the fallback palette.
- Every size and gap on the main view is a step of `Theme.golden(n)`, eight
  times phi to the n, so any two relate by a power of phi.
- The subdivision's sound is `subpattern`; `subshape` is only its spelling,
  carried for the shell and never read by the engine. The backend keeps the
  two coherent: a figure starts at every onset and at the beat.
- Every user-visible string is a key in `ui/i18n/en.json`, shown through
  `I18n.tr`; no literal words in QML. A new backend error gets a code in
  proto.rs's `ERROR_CODES` and an `error.wire.<code>` message. cargo test
  enforces both.
