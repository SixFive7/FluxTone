# FLUX·TONE

[![Latest release](https://img.shields.io/github/v/release/SixFive7/FluxTone?sort=semver&label=release&color=4d9fff)](https://github.com/SixFive7/FluxTone/releases)
[![License: MIT](https://img.shields.io/github/license/SixFive7/FluxTone?color=9a5bff)](LICENSE)
[![Live demo](https://img.shields.io/badge/demo-play%20now-ff4fa8)](https://sixfive7.github.io/FluxTone/)
![Single file, no build](https://img.shields.io/badge/single%20file-no%20build-6b7280)

![FLUX·TONE — three voices playing across the pitch spectrum](assets/hero.gif)

A touch-and-drag generative synthesizer that lives in a single HTML file.

Drag anywhere on the screen to play. Move **left / right** to sweep pitch, **up / down**
to shape the timbre, and use **several fingers** for chords — every gesture drives a
fluid, audio-reactive visualizer built on the Web Audio API and a canvas particle field.

You can also **record** your performance, play it back, and **download** it — captured
and stored entirely in your browser, with no server involved.

There is no build step and no framework. The entire instrument is one self-contained
`.html` file you can open locally or host as static content anywhere.

## Play it

Open `index.html` in a modern browser, or drop the folder behind any static web server.
Play it live on **[GitHub Pages](https://sixfive7.github.io/FluxTone/)**.

`index.html` always serves a copy of the latest release. Every version is also kept as
its own file, so older ones stay playable:

| File | Version |
| ---- | ------- |
| `v1.html` | the original synth |
| `v2.html` | adds recording — capture, replay, and download your takes |
| `v2.1.html` | downloads as MP3; asks for storage only when you first record |

See [CHANGELOG.md](CHANGELOG.md) for what changed between versions. This project follows
[Semantic Versioning](https://semver.org).

## Development

There is nothing to build — edit the HTML directly. Browser-based testing and
verification run through a set of Playwright MCP servers (headless / interactive /
tracing / persistent) driven by a single parametric launcher; see
[playwright/README.md](playwright/README.md) and [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE) © Jori Huisman
