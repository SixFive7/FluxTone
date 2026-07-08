# Changelog

All notable changes to FLUX·TONE are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-07-08

A small fix-and-polish pass.

### Added
- Download recordings as **MP3**, transcoded entirely in the browser with a bundled
  LAME encoder. Recordings are still stored as compact WebM/Opus; the MP3 is produced
  on demand at download time.

### Changed
- The browser's storage-persistence permission is now requested on the first recording
  instead of on page load, so visitors are no longer prompted on arrival.

## [1.1.0] - 2026-07-08

Made for my wife. 💛

### Added
- **Record, replay, and download** your performance. Everything is captured in the
  browser and stored locally in IndexedDB — no server, and still a single static file.
- A recordings library with per-take play/pause, rename, download, and delete.

## [1.0.0] - 2026-07-08

Made for my daughter. 💛

### Added
- Initial release — a touch-and-drag generative synthesizer. Drag to play; horizontal
  controls pitch, vertical controls timbre (brightness), multi-touch plays chords.
- Selectable waveforms, pitch modes (glide / snapped notes), scales, and a space/echo
  effect, over a fluid, audio-reactive particle visualizer.
- Runs entirely from a single self-contained HTML file — host it as static content anywhere.
