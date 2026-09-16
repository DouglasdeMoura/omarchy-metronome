# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Dialog titles, the tempo marking and the other captions were drawn in the
  theme's muted colour, which most Omarchy themes set too faint to read: 32
  of the 39 themes installed here fell below WCAG AA, as low as 1.3:1. Each
  caption is now lifted toward the foreground only as far as it takes to
  reach 4.5:1 on the surface behind it, so a theme that already reads well
  keeps its own ink.

## [0.1.1] - 2026-09-15

### Added

- Screenshots in the README, in the Tokyo Night and Catppuccin Latte themes.
- AUR publishing from GitHub: every release now updates `winkel`,
  `winkel-bin` and `winkel-git`, and `packaging/aur/set-version.sh` and
  `packaging/aur/publish.sh` do the same from a local machine.

### Changed

- The README is reorganised and rewritten for clarity, with a licence
  section and a floating-window recipe for Hyprland.
- The release recipes carry real checksums.

## [0.1.0] - 2026-09-15

The first release.

### Added

- Winkel, a sample-accurate metronome with a Rust audio backend and a Quickshell
  interface that follows the live Omarchy theme.
- Tempo from 10 to 400 BPM with steppers, typing, the arrow keys and tap
  tempo, and the classical tempo marking.
- A time signature editor for 1 to 16 counts over 1, 2, 4 or 8.
- Per-beat voices: silent, low, medium or high.
- Subdivisions in musical notation, from eighths and triplets to dotted
  rhythms, quintuplets and sextuplets, with any figure turned into a rest.
- A keys sheet, full keyboard control, and a single running instance.
- An inaudible keep-alive floor so Bluetooth earbuds never drop a tick.
- Translation support with plural rules, right-to-left layouts and
  pseudo-locales for testing.
- Packaging: AUR packages, release tarballs, `make install`, a desktop entry,
  an icon and AppStream metainfo.
