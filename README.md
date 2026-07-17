<div align="center">

<h1>FLUX·TONE</h1>

<p><strong>Drag to play — a touch-driven generative synthesizer in a single HTML file.</strong></p>

<p>
  <a href="https://github.com/SixFive7/FluxTone/releases"><img src="https://img.shields.io/github/v/release/SixFive7/FluxTone?sort=semver&label=release&color=4d9fff" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/SixFive7/FluxTone?color=9a5bff" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/single%20file-no%20build-6b7280" alt="Single file, no build">
</p>

<p>
  <a href="https://sixfive7.github.io/FluxTone/" title="Play FLUX·TONE live"><img src="assets/hero.gif" alt="FLUX·TONE — three glowing voices playing across the pitch spectrum" width="640"></a>
</p>

<p>
  <a href="https://sixfive7.github.io/FluxTone/"><img src="https://img.shields.io/badge/%E2%96%B6%20play%20it%20live-ff4fa8?style=for-the-badge&labelColor=06070d" alt="Play it live" height="38"></a>
</p>

</div>

---

FLUX·TONE turns a drag of your finger — or mouse — into sound and light. Every gesture plays
a voice through the Web Audio API and ripples across a fluid, audio-reactive particle field.
Nothing to read, nothing to install: the whole instrument is one self-contained `.html` file
with no build step, no framework, and no server.

## Controls

| Gesture | Effect |
| --- | --- |
| **Drag** | play a voice |
| **Horizontal** | pitch — low ↔ high |
| **Vertical** | timbre — bright ↔ dark |
| **Multiple fingers** | layer voices into chords |

Waveform, pitch mode (glide or snapped notes), scale, and a space/echo effect are all a tap
away in the on-screen controls.

## Record &amp; export

Capture a take, play it back, rename it, and **download it as an MP3**. Recordings are
encoded and kept entirely in your browser (IndexedDB) — still one static file, still no
server.

## Versions

`index.html` always serves the latest release, and every version is kept as its own file so
older ones stay playable.

| File | Release | Highlights |
| --- | --- | --- |
| `v1.html` | [v1.0.0](https://github.com/SixFive7/FluxTone/releases/tag/v1.0.0) | the original synth |
| `v2.html` | [v1.1.0](https://github.com/SixFive7/FluxTone/releases/tag/v1.1.0) | record · replay · download |
| `v2.1.html` | [v1.1.1](https://github.com/SixFive7/FluxTone/releases/tag/v1.1.1) | MP3 export · lazy storage prompt |

Full history lives in the [changelog](CHANGELOG.md); the project follows
[Semantic Versioning](https://semver.org).

## Run it yourself

Open `index.html` in any modern browser, or drop the folder behind any static web server —
that is the entire deployment story.

## Development

There is nothing to build; edit the HTML directly. Browser-based testing and verification
run through four Playwright MCP servers (headless / interactive / tracing / persistent)
driven by a single parametric launcher — see [playwright/README.md](playwright/README.md)
and [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE) © Jori Huisman
