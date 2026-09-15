# Metronome

A metronome for [Omarchy](https://omarchy.org): Rust backend, Quickshell/QML
frontend, and a look that follows your Omarchy theme live — change themes with
`omarchy theme set` and Metronome repaints without a restart, the same way
[Flea](https://github.com/thisisgm/flea) does.

![stack](https://img.shields.io/badge/Rust-backend-informational) ![stack](https://img.shields.io/badge/Quickshell%2FQML-frontend-purple)

## Features

- **Sample-accurate clicks.** The audio callback mixes each click at an exact
  frame on the output device (via [cpal](https://github.com/RustAudio/cpal),
  through PipeWire/ALSA); the beat meters are driven by the same timeline, so
  the visuals follow playback, subject to audio buffering and display latency.
- **Tempo at hand.** A slider and ± steppers over 10–400 BPM; above the
  number, the classical marking names what the beat is relative to — Largo,
  Andante, Allegretto, Presto…
- **Time signature editor.** Click the signature to pick 1–16 counts per bar
  over a 1, 2, 4 or 8 bottom number — 4/4, 6/8, 3/2, 12/8 and friends; the
  tick is the notated value, so 6/8 at 120 ticks on the eighth.
- **Per-beat voices.** A rectangle for every beat, divided in three bars:
  click to fill one, two or all three — low, medium or high tick — or leave
  it empty for silence, and build a pattern instead of a flat tick.
- **Tap tempo**: tap the button or press `t` in rhythm.
- **Omarchy theming**: colors, type scale, spacing and corner radius all come
  from the live theme (`colors.toml`, `shell.toml`), watched for changes.
- **Remembers itself**: bpm, meter and per-beat voices persist in
  `~/.config/metronome/state.json`.
- **Keyboard-first**, like Flea:

| key | action |
| --- | --- |
| `space` | start / stop |
| `t` | tap tempo |
| `↑` / `↓` | tempo ±1 (`shift` ±5, `PgUp`/`PgDn` ±10) |
| `1`, `2`, `4`, `8` | time-signature denominator |
| `esc` | stop |
| `ctrl+q` | quit |

## Running

```sh
cargo build --release  # Rust 1.89 or newer
./target/release/metronome
```

A checkout finds its own `ui/` automatically; `METRONOME_UI`, `METRONOME_BIN`,
`METRONOME_SILENT` (protocol without audio, for tests and headless boxes) and
`METRONOME_FONT` are the dev seams — see `src/paths.rs` and `src/gui.rs`.

## Installing

```sh
sudo install -Dm755 target/release/metronome /usr/local/bin/metronome
sudo cp -r ui /usr/local/share/metronome/ui
sudo cp packaging/metronome.desktop /usr/share/applications/
sudo cp packaging/metronome.svg /usr/share/icons/hicolor/scalable/apps/
```

If you want Metronome to open as a small floating window instead of a tile, give
Hyprland a rule (Omarchy's `~/.config/hypr/` user conf or a drop-in):

```ini
windowrule = float, class:^(com\.douglasdemoura\.metronome)$
```

## Architecture

Two processes, one app — Flea's shape:

```
metronome (CLI)
 └─ exec qs -p ui/shell.qml          the window; METRONOME_BIN tells QML who to call
     └─ Process: metronome --backend     json lines over stdio, docs/protocol.md
         └─ cpal output stream        the timeline and the clicks
```

- `src/backend/engine.rs` — the metronome: one f64 frame timeline, click
  synthesis, and the realtime rules (the callback only touches atomics; params
  land at the next click boundary, where a musician expects them). No device?
  A silent clock keeps the visuals alive.
- `ui/Theme.qml` — reads `~/.local/state/omarchy/current/theme/colors.toml`
  and `shell.toml` before the first paint and watches `theme.name`, the one
  file `omarchy-theme-set` rewrites in place, so the watch survives theme
  switches. Hyprland answers for corner rounding and reduced motion.
- `src/json.rs` — the whole of the wire-format code; besides cpal the backend
  is std-only.

## Tests

```sh
cargo test          # timeline, protocol process, json, state
bash tests/ui.sh    # offscreen Quickshell frontend regression checks
```
