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
- **No lost ticks on Bluetooth.** A metronome is mostly silence, and earbuds
  switch their amplifier off during silence, swallowing the next tick. The
  output carries an inaudible noise floor under everything so the link stays
  awake.
- **Tempo at hand.** ± steppers, the arrow keys, or type straight into the
  number, over 10–400 BPM; above it, the classical marking names the tempo —
  Largo, Andante, Allegretto, Presto…
- **Time signature editor.** Click the signature to pick 1–16 counts per bar
  over a 1, 2, 4 or 8 bottom number — 4/4, 6/8, 3/2, 12/8 and friends; the
  tick is the notated value, so 6/8 at 120 ticks on the eighth.
- **Per-beat voices.** Three bars for every beat: click to fill one, two or all
  three — low, medium or high tick — or leave them empty for silence, and build
  a pattern instead of a flat tick.
- **Subdivisions in notation.** The button right of Tap shows the beat's
  rhythm as a musical figure. Its editor offers the common cells as tiles —
  eighths, triplets, swing, dotted rhythms, sixteenth groups, quintuplets and
  sextuplets — and a row of note squares turns any figure into a rest, so
  every rhythm of up to six notes per beat is reachable.
- **Tap tempo**: tap the button or press `t` in rhythm.
- **Omarchy theming**: colors, type scale, spacing and corner radius all come
  from the live theme (`colors.toml`, `shell.toml`), watched for changes.
- **Ready for translation**: every word comes from a catalogue, plurals follow
  each language's rules, and right-to-left languages mirror the window. See
  [docs/i18n.md](docs/i18n.md).
- **Remembers itself**: tempo, meter, per-beat voices and subdivision persist
  in `~/.config/metronome/state.json`. A first launch opens at 80 BPM in 4/4.
  Settings saved before the app was renamed, in `~/.config/pulse`, are read
  once and carried over.
- **One at a time**: a second launch leaves the running metronome alone, so two
  never tick against each other.
- **Keyboard-first**, like Flea. Press `?` for the full list in the app:

| key | action |
| --- | --- |
| `space` | start / stop |
| `t` | tap tempo |
| `↑` / `↓` | tempo ±1 (`shift` ±5, `PgUp`/`PgDn` ±10) |
| `1`, `2`, `4`, `8` | time-signature denominator |
| `tab` | next control |
| `enter` | press the focused control |
| `esc` | stop, or close a dialog |
| `?` | the keys sheet |
| `ctrl+q` | quit |

## Running

```sh
cargo build --release  # Rust 1.89 or newer
./target/release/metronome
```

A checkout finds its own `ui/` automatically. Launch `metronome`, not `qs`
directly: the binary tells the window where its backend is.

The development switches, see `src/paths.rs` and `src/gui.rs`:

| variable | effect |
| --- | --- |
| `METRONOME_UI` | the `ui/` directory to load |
| `METRONOME_BIN` | the backend binary the window starts |
| `METRONOME_SILENT` | run the protocol without audio, for tests and headless boxes |
| `METRONOME_LANG` | force a language, or `pseudo` / `pseudo-rtl` to test translations |
| `METRONOME_FONT` | the font family |

## Installing

```sh
sudo install -Dm755 target/release/metronome /usr/local/bin/metronome
sudo cp -r ui /usr/local/share/metronome/ui
sudo cp packaging/metronome.desktop /usr/share/applications/
sudo cp packaging/metronome.svg /usr/share/icons/hicolor/scalable/apps/
```

If you want Metronome to open as a small floating window instead of a tile, give
Hyprland a rule. Omarchy's Hyprland config is Lua; add this to a file in
`~/.config/hypr/`, such as `bindings.lua`:

```lua
o.window("^dev\\.douglasmoura\\.metronome$", { float = true, center = true, size = { 377, 610 } })
```

## Architecture

Two processes, one app — Flea's shape:

```
metronome (CLI)
 └─ exec qs -p ui/shell.qml              the window; METRONOME_BIN tells QML who to call
     └─ Process: metronome --backend     json lines over stdio, docs/protocol.md
         └─ cpal output stream           the timeline and the clicks
```

- `src/backend/engine.rs` — the metronome: one f64 frame timeline, click
  synthesis, and the realtime rules (the callback only touches atomics; params
  land at the next click boundary, where a musician expects them). No device?
  A silent clock keeps the visuals alive.
- `ui/Main.qml` — the one screen and its dialogs.
- `ui/Rhythm.js` and `ui/NoteFigure.qml` — the subdivision cells and the
  notation that draws them.
- `ui/Theme.qml` — reads `~/.local/state/omarchy/current/theme/colors.toml`
  and `shell.toml` before the first paint and watches `theme.name`, the one
  file `omarchy-theme-set` rewrites in place, so the watch survives theme
  switches. Hyprland answers for corner rounding and reduced motion.
- `ui/I18n.qml` — the locale and its catalogues in `ui/i18n/`.
- `src/json.rs` — the whole of the wire-format code; besides cpal the backend
  is std-only.

## Tests

```sh
cargo test          # timeline, protocol process, json, state, translation catalogues
bash tests/ui.sh    # offscreen Quickshell frontend regression checks
```
