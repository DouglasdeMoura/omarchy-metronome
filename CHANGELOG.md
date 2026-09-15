# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

The first release.

### Added

- A sample-accurate metronome with a Rust audio backend and a Quickshell
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
