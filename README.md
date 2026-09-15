# Winkel

A metronome for [Omarchy](https://omarchy.org): Rust backend, Quickshell/QML
frontend, and a look that follows your Omarchy theme live — change themes with
`omarchy theme set` and Winkel repaints without a restart, the same way
[Flea](https://github.com/thisisgm/flea) does.

## Why Winkel

The mechanical metronome was invented by Dietrich Nikolaus Winkel, in
Amsterdam, in 1814: a spring-driven inverted pendulum with a fixed and a
sliding weight. Johann Nepomuk Maelzel took Winkel's ideas, added a numbered
scale, named the device a metronome, patented it in England in 1815, and from
1816 mass-produced it as "Maelzel's Metronome" — which is why scores still
mark tempos M.M. This app carries the name of the man who actually built it.

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
  in `~/.config/winkel/state.json`. A first launch opens at 80 BPM in 4/4.
  Settings saved under the app's earlier names, in `~/.config/metronome` or
  `~/.config/pulse`, are read once and carried over.
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

## Requirements

Winkel runs on Linux with a graphical session.

| | Needed | Notes |
| --- | --- | --- |
| **Quickshell** | yes | The interface runs in Quickshell (`qs`). Arch: `quickshell`. |
| **ALSA library** | yes | The audio backend's link to the sound system, `alsa-lib`, with PipeWire, PulseAudio or plain ALSA behind it. |
| **Wayland or X11** | yes | Any desktop; Omarchy's Hyprland is the home turf. |
| **JetBrainsMono Nerd Font** | recommended | The default font; set `WINKEL_FONT` to use another. |
| **Omarchy** | optional | Supplies the live theme. Without it Winkel uses its built-in palette. |
| **Hyprland** | optional | Supplies corner rounding and the reduced-motion setting. |

Building from source also needs Rust 1.89 or newer with cargo, the ALSA
development headers (included in Arch's `alsa-lib`, `libasound2-dev` on
Debian and Ubuntu), `pkg-config` and `make`.

## Installing

### Arch Linux and Omarchy (AUR)

```sh
yay -S winkel
```

Three packages are available: `winkel` builds the release from
source, `winkel-bin` installs the prebuilt binary, and
`winkel-git` builds the latest development version.

### Release tarball

Prebuilt binaries for x86_64 and aarch64 are attached to every
[release](https://github.com/DouglasdeMoura/winkel/releases). They
need Quickshell and the ALSA library installed, but no Rust toolchain:

```sh
tar xzf winkel-0.1.0-x86_64-linux.tar.gz
cd winkel-0.1.0-x86_64-linux
sudo make install
```

### From source

```sh
git clone https://github.com/DouglasdeMoura/winkel
cd winkel
make
sudo make install                 # to /usr/local; PREFIX=/usr to change it
```

`sudo make uninstall` removes it again, with the same `PREFIX`.

## Running

Start it from your launcher, or:

```sh
winkel
```

From a checkout, `./target/release/winkel` finds its own `ui/`.
Launch the binary, not `qs` directly: the binary tells the window where its
backend is.

The development switches, see `src/paths.rs` and `src/gui.rs`:

| variable | effect |
| --- | --- |
| `WINKEL_UI` | the `ui/` directory to load |
| `WINKEL_BIN` | the backend binary the window starts |
| `WINKEL_SILENT` | run the protocol without audio, for tests and headless boxes |
| `WINKEL_LANG` | force a language, or `pseudo` / `pseudo-rtl` to test translations |
| `WINKEL_FONT` | the font family |

If you want Winkel to open as a small floating window instead of a tile, give
Hyprland a rule. Omarchy's Hyprland config is Lua; add this to a file in
`~/.config/hypr/`, such as `bindings.lua`:

```lua
o.window("^dev\\.douglasmoura\\.winkel$", { float = true, center = true, size = { 377, 610 } })
```

## Architecture

Two processes, one app — Flea's shape:

```
winkel (CLI)
 └─ exec qs -p ui/shell.qml                      the window; WINKEL_BIN tells QML who to call
     └─ Process: winkel --backend     json lines over stdio, docs/protocol.md
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

## Credits

The app icon's metronome shape comes from [Phosphor Icons](https://phosphoricons.com),
MIT; see `packaging/ICON-LICENSE`.

## Tests

```sh
make test           # both suites below
cargo test          # timeline, protocol process, json, state, translation catalogues
bash tests/ui.sh    # offscreen Quickshell frontend regression checks
```

Releases follow [docs/releasing.md](docs/releasing.md), and changes are
recorded in [CHANGELOG.md](CHANGELOG.md).
