# Playwright MCP Configuration

This project runs **four** `@playwright/mcp` instances as separate MCP servers, each tuned for a different use case. One parametric PowerShell launcher ([launch.ps1](launch.ps1), documented separately in [LAUNCHER.md](LAUNCHER.md)) selects the appropriate `config.json` and applies mode-specific behaviour (per-session output dirs, named-mutex exclusivity).

## Files

| File / Folder | Role |
|---|---|
| [../.mcp.json](../.mcp.json) | Bootstraps four MCP server entries (`playwright-headless`, `playwright-interactive`, `playwright-tracing`, `playwright-persistent`). Each invokes the launcher with a different `-Mode`. |
| [launch.ps1](launch.ps1) | Parametric PowerShell launcher. Per-mode pre-launch behaviour, then `exec npx @playwright/mcp@latest --config <path> --output-mode file [...]`. |
| [LAUNCHER.md](LAUNCHER.md) | Launcher reference: parameters, behaviour matrix, mutex semantics, debugging. |
| [headless/config.json](headless/config.json) + [headless/README.md](headless/README.md) | Default mode for routine agent work. Ephemeral (`--isolated`), parallel-safe across Claude Code sessions, no HAR. |
| [interactive/config.json](interactive/config.json) + [interactive/README.md](interactive/README.md) | Rare. Headed for manual login. Ephemeral, single-instance via named mutex. |
| [tracing/config.json](tracing/config.json) + [tracing/README.md](tracing/README.md) | Debugging. Headed, full HAR + saveSession + verbose console. Ephemeral, single-instance via separate mutex. |
| [persistent/config.json](persistent/config.json) + [persistent/README.md](persistent/README.md) | The only mode with persistent profile (`userDataDir: playwright/persistent/profile/`). Headed. Single-instance via Chrome `SingletonLock`. |
| **README.md** (this file) | Canonical overview: architecture, "when to use which", full settings table covering all four modes, rules, drift policy. |

## When to use which server

| Mode | Use case | Concurrency |
|---|---|---|
| **headless** | Default — most agent work. Ephemeral. No state, no HAR. | Many parallel sessions. No locking. |
| **interactive** | Manual login (creds the agent should not see). Ephemeral. | Single-instance. Mutex `Global\<RepoName>-PlaywrightInteractive`. (`<RepoName>` is this repository's folder name.) |
| **tracing** | Debugging — network/console/session investigation. Ephemeral. | Single-instance. Mutex `Global\<RepoName>-PlaywrightTracing`. Independent of interactive. |
| **persistent** | Tasks that need login state to survive between runs (a site you sign into). | Single-instance. Chrome `SingletonLock` on profile dir. |

If you're unsure: use **headless**. Switch only when the mode's specific feature is required.

## Rules

**Drift rule.** When you change a value in any `<mode>/config.json` or in `.mcp.json`, update the matching row in the [Settings](#settings) table below in the **same commit**. Motivation only lives in this README, so it must not drift.

**HAR archive convention (tracing only).** `recordHar.path` is **static** — Playwright does not support placeholder substitution. Each new browser context overwrites `playwright/tracing/output/network.har` at close. If a session's trace is worth keeping, the agent MUST rename the file before the next context starts:

```powershell
Move-Item playwright/tracing/output/network.har `
  "playwright/tracing/output/network-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss')-<task-slug>.har"
```

Unrenamed `network.har` files are considered disposable.

**Screenshot filenames.** When calling `browser_take_screenshot` with an explicit `filename`, **prepend the mode's `outputDir`** — e.g. `playwright/headless/output/<session-subdir>/foo.png`. Upstream resolves explicit filenames via `workspaceFile()` against CWD (the repo root), not against `outputDir`, so a bare `foo.png` lands in the repo root. Auto-naming (omitting `filename` entirely) routes through `outputFile()` and does honour `outputDir`. The tool description ("Prefer relative file names to stay within the output directory") is misleading vs. the actual code path — see `packages/playwright-core/src/tools/backend/screenshot.ts` upstream. No config flag bridges the two; this is the agent's responsibility.

**Single-instance per-mode (interactive, tracing, persistent).** Enforcement varies:
- `interactive`: Windows named mutex `Global\<RepoName>-PlaywrightInteractive` acquired by [launch.ps1](launch.ps1).
- `tracing`: separate mutex `Global\<RepoName>-PlaywrightTracing`.
- `persistent`: Chrome's `SingletonLock` file inside the persistent `userDataDir` (`playwright/persistent/profile/`). Automatic.

`headless` has **no** single-instance constraint — many parallel sessions are explicitly supported.

**Per-session output isolation (headless only).** The launcher creates `playwright/headless/output/{yyyy-MM-dd-HH-mm-ss}-{4-char-suffix}/` per launch and passes it as `--output-dir` on the CLI (overrides the config's `outputDir`). This eliminates collisions for parallel sessions.

**Official documents (invoices, statements, policies).** Click the site's download button — Playwright intercepts the `download` event and writes the authentic server-served file to the active `outputDir`. Do **not** use `browser_pdf_save` for this: that tool renders the current HTML to PDF (a page screenshot), not the real file. The `pdf` capability is intentionally disabled — see row #56.

**Resetting profiles.**
- `persistent`: see [persistent/README.md](persistent/README.md). `Remove-Item -Recurse -Force playwright/persistent/profile/*` forces fresh logins on next launch.
- `headless`, `interactive`, `tracing`: nothing to reset — these are `--isolated`, profiles are tmp dirs Playwright wipes on close.

**Ephemeral profile dirs are gitignored.** Contents of `playwright/{headless,interactive,tracing}/profile/` are ignored (only the placeholder `README.md` stays tracked) — a defensive backstop so that if `isolated` (#4) ever regresses and a real on-disk profile with cookies/credentials appears, git can't accidentally commit it. See [.gitignore](../.gitignore).

**Debugging a failed session.** `saveSession: true` is on for all four modes. The most recent `<mode>/output/.../session-{timestamp}/session.md` contains the full tool-call trace (each call as a `### Tool call:` heading with `Args` and `Result` JSON-fenced blocks). For tracing mode, `<mode>/output/network.har` has the corresponding network activity including WebSocket frames.

**Upgrading `@playwright/mcp`.** `npx` pulls `@latest` on every server start, so upgrades are automatic. After a major upstream upgrade, run `npx @playwright/mcp@latest --help` and diff against the [Settings](#settings) table — new flags or config keys need a new row. If the upgrade bumps the pinned playwright-core revision, refresh headless mode's bundled browser with `npx -y @playwright/mcp@latest install-browser chromium` — headless runs the bundled chromium-headless-shell, not system Chrome (row #2), and fails with "Executable doesn't exist" until the matching revision is installed.

## Location legend

| Location | Meaning |
|---|---|
| `json` | Set in one or more mode `config.json` files. |
| `flag` | Set as a CLI argument by [launch.ps1](launch.ps1) (used when the setting has no config-schema equivalent, or when it must vary per launch). |
| `code` | Only settable programmatically (function/callable type). Listed for completeness; we never use these. |
| `default` | Not set by us in any mode — upstream default is active everywhere. |

## Merge order

Upstream: `defaults < configFile < env vars < CLI flags`. CLI wins over everything. We do not set environment variables; all overrides go through `config.json` or CLI flags emitted by the launcher.

---

## Settings

Values that differ across modes are written as `headless / interactive / tracing / persistent`. A single value means all four modes agree. `—` means default (not set by us).

| # | Setting | Location | Function | Value | Motivation |
|--:|---|:-:|---|---|---|
| | **▸ Browser engine & profile** | | | | |
| 1 | `browser.browserName` | json | Browser engine family | `chromium` (all) | Chromium required for full CDP access (WebSocket frames, network bodies, performance traces). Default: `chromium`. |
| 2 | `browser.launchOptions.channel` | json (3 modes) | Chrome channel within the Chromium engine | headless: —; others: `chrome` | Headed modes use system Chrome — matches daily browser, stays current via Windows Update. Headless deliberately sets no channel: Playwright then runs its bundled chromium-headless-shell, which has no window code path — system Chrome's modern headless can surface a blank window on Windows. Install the bundled browser once per playwright-core revision: `npx -y @playwright/mcp@latest install-browser chromium`. Default: bundled chromium. |
| 3 | `browser.userDataDir` | json (persistent only) | Persistent browser profile on disk | persistent: `playwright/persistent/profile`; others: — | Only `persistent` uses a real userDataDir. The other three modes use `isolated` (mutually exclusive). Default: temp dir per session. |
| 4 | `browser.isolated` | json (3 modes) | In-memory profile (mutually exclusive with #3) | headless/interactive/tracing: `true`; persistent: — | The three ephemeral modes use `isolated` so parallel sessions never collide on profile state. `persistent` uses `userDataDir` for state continuity. Default: `false`. |
| 5 | `browser.launchOptions.executablePath` | default | Explicit path to browser binary | — | Auto-detection finds system Chrome reliably. Default: auto. |
| | **▸ Launch options (browser process)** | | | | |
| 6 | `browser.launchOptions.headless` | json | Run without a visible window | headless: `true`; others: `false` | Only `headless` is invisible. Interactive needs a window for user login; tracing for debug visibility; persistent because if you can see your daily-driver state, you can recover from issues. Default: `false`. |
| 7 | `browser.launchOptions.args` | default | Extra Chromium CLI flags | — | No specific portal misbehaves; no anti-detection need. Default: `[]`. |
| 8 | `browser.launchOptions.env` | default | Environment variables for browser process | — | Shell env suffices. Default: inherits shell env. |
| 9 | `browser.launchOptions.slowMo` | default | Delay each action by N ms (debug aid) | — | Productive runs; slowing masks bugs. Default: `0`. |
| 10 | `browser.launchOptions.devtools` | default | Open DevTools automatically on page load | — | We use `capabilities: ["devtools"]` for programmatic CDP. Default: `false`. |
| 11 | `browser.launchOptions.downloadsPath` | default | Separate downloads directory from `outputDir` | — | Keeping everything under the mode's `outputDir` avoids split storage. Default: inherits `outputDir`. |
| 12 | `browser.launchOptions.chromiumSandbox` | default | Sandbox on the parent browser process | — | Renderer-sandbox is the real protection; this extra layer has Windows start-up quirks for little gain. Default: `false`. |
| 13 | `browser.launchOptions.timeout` | default | Browser launch timeout (ms) | — | 30s is comfortable on any machine we use. Default: `30000`. |
| 14 | `browser.launchOptions.proxy` | default | HTTP/SOCKS proxy + bypass | — | Direct network, no proxy in use. Default: none. |
| 15 | `browser.launchOptions.ignoreDefaultArgs` | default | Skip Playwright's default Chrome args | — | Advanced escape hatch, never needed. Default: `[]`. |
| 16 | `browser.launchOptions.firefoxUserPrefs` | default | Firefox-specific prefs | — | N/A, we use Chromium. Default: `{}`. |
| 17 | `browser.launchOptions.handleSIGINT/TERM/HUP` | default | Signal handling on MCP shutdown | — | Default `true` correct for stdio spawn. Default: `true` (all three). |
| 18 | `browser.launchOptions.artifactsDir` | default | Directory for Playwright's internal artifacts | — | `outputDir` already centralizes these. Default: inherits `outputDir`. |
| 19 | `browser.launchOptions.tracesDir` | default | Directory for Playwright's native `tracing.start()` output | — | HAR (in `tracing` mode) covers network; Playwright's own trace format is test-runner-oriented and redundant. Default: inherits `outputDir`. |
| 20 | `browser.launchOptions.logger` | code | Custom `Logger` interface for Playwright internals | — | Function/object type — not JSON-representable. Default: none. |
| | **▸ Context options — display & emulation** | | | | |
| 21 | `browser.contextOptions.viewport.width` | json | Viewport width in pixels | `1920` (all) | 1080p desktop — most common business resolution; triggers desktop layout. Default: `1280`. |
| 22 | `browser.contextOptions.viewport.height` | json | Viewport height in pixels | `1080` (all) | See #21. Default: `720`. |
| 23 | `browser.contextOptions.locale` | json | `navigator.language` + Accept-Language header | `nl-NL` (all) | Pinned explicitly so locale-sensitive UI renders reproducibly across machines. Default: inherits OS locale. |
| 24 | `browser.contextOptions.timezoneId` | json | Browser timezone | `Europe/Amsterdam` (all) | Explicit for reproducibility across machines. Default: inherits OS timezone. |
| 25 | `browser.contextOptions.colorScheme` | default | `prefers-color-scheme` override | — | Default `light` keeps screenshots readable. Default: `light`. |
| 26 | `browser.contextOptions.contrast` | default | `prefers-contrast` CSS override | — | Accessibility-testing feature, N/A here. Default: `no-preference`. |
| 27 | `browser.contextOptions.forcedColors` | default | Windows High Contrast emulation | — | Accessibility-testing feature, N/A here. Default: `none`. |
| 28 | `browser.contextOptions.reducedMotion` | default | `prefers-reduced-motion` override | — | Headless renders no animations; zero observable effect. Default: `no-preference`. |
| 29 | `browser.contextOptions.hasTouch` | default | Simulate touch input | — | Desktop-only workflow. Default: `false`. |
| 30 | `browser.contextOptions.isMobile` | default | Mobile device emulation | — | Desktop-only workflow. Default: `false`. |
| 31 | `browser.contextOptions.screen` | default | Outer screen dimensions (distinct from viewport) | — | Viewport covers rendering needs. Default: matches viewport. |
| 32 | `browser.contextOptions.deviceScaleFactor` | default | DPR override (hi-DPI emulation) | — | Default 1x is fine for automation. Default: `1`. |
| 33 | `browser.contextOptions.userAgent` | default | Override the UA string | — | Default Chrome UA works everywhere. Default: real Chrome UA. |
| | **▸ Context options — network & security** | | | | |
| 34 | `browser.contextOptions.ignoreHTTPSErrors` | json | Accept invalid/self-signed certs | `true` (all) | Internal dev servers with self-signed certs must remain reachable. Default: `false`. |
| 35 | `browser.contextOptions.permissions` | json | Permissions auto-granted (no dialog) | `["clipboard-read", "clipboard-write"]` (all) | Agent must copy/paste without modal interruption. Other permissions intentionally omitted. Default: `[]`. |
| 36 | `browser.contextOptions.geolocation` | default | Simulated GPS coordinates | — | Portals don't request this; simulation = fingerprint noise. Default: none. |
| 37 | `browser.contextOptions.httpCredentials` | default | Basic Auth credentials | — | Violates repo rule "tokens never on disk". Default: none. |
| 38 | `browser.contextOptions.extraHTTPHeaders` | default | Static custom headers on every request | — | No concrete use case. Default: `{}`. |
| 39 | `browser.contextOptions.baseURL` | default | URL prefix for relative `page.goto()` calls | — | We cross many portals; a single baseURL would break everything else. Default: none. |
| 40 | `browser.contextOptions.bypassCSP` | default | Disable Content-Security-Policy enforcement | — | Weakens security; standard agent tool set doesn't hit CSP walls. Default: `false`. |
| 41 | `browser.contextOptions.serviceWorkers` | default | `allow`/`block` service workers | — | Some web apps use service workers for offline sync. Default: `allow`. |
| 42 | `browser.contextOptions.javaScriptEnabled` | default | Disable JS execution | — | Modern portals require JS. Default: `true`. |
| 43 | `browser.contextOptions.offline` | default | Simulate offline network | — | Defeats the purpose. Default: `false`. |
| 44 | `browser.contextOptions.acceptDownloads` | default | Permit file downloads | — | Our download-to-`outputDir` flow **requires** this — never change. Default: `true`. |
| 45 | `browser.contextOptions.storageState` | default | Import serialised cookies/localStorage at context start | — | Redundant with `persistent` mode; ephemeral modes don't want state injection. Default: none. |
| 46 | `browser.contextOptions.clientCertificates` | default | mTLS client certificates per origin | — | No mTLS scenario. Default: `[]`. |
| 47 | `browser.contextOptions.proxy` | default | Per-context proxy | — | No proxy needed. Default: inherits `launchOptions.proxy`. |
| 48 | `network.allowedOrigins` | default | Whitelist of origins | — | User explicitly wants no URL restrictions. Default: all allowed. |
| 49 | `network.blockedOrigins` | default | Blacklist of origins | — | See #48. Default: none. |
| | **▸ Context options — recording** | | | | |
| 50 | `browser.contextOptions.recordVideo` | default | Record session as `.webm` video | — | Session log + (tracing's) HAR cover debug needs; video is large. Default: none. |
| 51 | `browser.contextOptions.videoSize` | default | Video recording resolution | — | Depends on #50. Default: matches viewport. |
| 52 | `browser.contextOptions.recordHar.path` | json (tracing only) | HAR file location | tracing: `playwright/tracing/output/network.har`; others: — | Tracing mode captures full HTTP + WebSocket. Other modes omit to stay light and parallel-safe (HAR path is static, would clobber). See HAR archive convention in "Rules". Default: no recording. |
| 53 | `browser.contextOptions.recordHar.mode` | json (tracing only) | `full` or `minimal` entry detail | tracing: `full`; others: — | Full entries required for debugging. Default: `full`. |
| 54 | `browser.contextOptions.recordHar.content` | json (tracing only) | `embed`/`attach`/`omit` — response body storage | tracing: `embed`; others: — | `embed` inlines bodies AND WebSocket frame payloads (via `_webSocketMessages` HAR extension). Default: varies per mode. |
| 55 | `browser.contextOptions.recordHar.urlFilter` | default | Regex/string filter | — | We want complete capture. Default: record all. |
| | **▸ Capabilities & tools** | | | | |
| 56 | `capabilities` | json | List of MCP tool capabilities | `["vision", "devtools"]` (all) | `vision` = screenshot tools + coord-based clicking. `devtools` = CDP introspection (WebSocket frames, network bodies, performance traces). `pdf` intentionally omitted — `browser_pdf_save` renders HTML→PDF (screenshot), we want server-served PDFs via Playwright's download handling. Default: core only. |
| 57 | `codegen` | json | Language for code-generation tools | `none` (all) | Agent works live interactively. Saves context + tool surface. Default: `typescript`. |
| 58 | `snapshot.mode` | default | Accessibility snapshot mode (`full`/`none`) | — | Non-vision workflow leans on snapshots. Default: `full`. |
| 59 | `imageResponses` | default | Screenshots in tool response | — | Model chooses when a screenshot is useful. Default: `auto`. |
| 60 | `testIdAttribute` | default | HTML attribute used as test id | — | External portals, not own-app testing. Default: `data-testid`. |
| 61 | `browser.contextOptions.strictSelectors` | default | Locators fail on multi-match instead of picking first | — | Breaks Playwright MCP's standard tool flow. Default: `false`. |
| | **▸ Output & logging** | | | | |
| 62 | `outputDir` | json (all) | Directory for downloads, auto-named screenshots, session folders, HAR | per-mode: `playwright/<mode>/output` | Each mode has its own output dir, fully isolated. Headless additionally gets per-session sub-dirs via the launcher's `--output-dir` CLI override (see "Per-session output isolation" rule). Default: OS temp dir. |
| 63 | `--output-mode` | flag (all) | Route snapshot/network/console to `file` or `stdout` | `file` (all) | Only CLI-only setting (not in Config schema). File instead of tool-response prevents context bloat on large pages. Default: `stdout`. |
| 64 | `saveSession` | json (all) | Per-session folder `{outputDir}/session-{timestamp}/session.md` — Markdown trace of every tool call | `true` (all) | Critical for post-hoc debugging. Format has been Markdown since upstream PR #740 (commit `b1a0f77`, 2025-07-22). Default: `false`. |
| 65 | `console.level` | json | Browser console message level | headless/interactive/persistent: `warning`; tracing: `info` | `warning` for normal modes — `info`/`debug` spam context. Tracing wants `info` to capture more for debugging. Default: `info`. |
| 66 | `allowUnrestrictedFileAccess` | json | Agent can access paths outside workspace + `file://` URLs | `true` (all) | Needed for local PDF analysis + `file://` debugging. Default: `false`. |
| 67 | `secrets` | default | Inline secrets object for injection into scripts | — | Violates "tokens never on disk" rule. Default: none. |
| 68 | `browser.contextOptions.logger` | code | Per-context custom `Logger` interface | — | Function/object type — not JSON-representable. Default: none. |
| | **▸ Timeouts** | | | | |
| 69 | `timeouts.action` | default | Per-action timeout (ms) | — | 5s is generous; longer masks bugs. Default: `5000`. |
| 70 | `timeouts.navigation` | default | Per-navigation timeout (ms) | — | 60s is ample for the portals we hit. Default: `60000`. |
| 71 | `timeouts.expect` | default | `expect()` assertion timeout | — | Test-runner feature; we use `browser_wait_for`. Default: `5000`. |
| | **▸ Transport & remote connections** (N/A under stdio) | | | | |
| 72 | `server.port` | default | HTTP/SSE transport bind port | — | stdio transport. Default: none. |
| 73 | `server.host` | default | HTTP/SSE transport bind host | — | stdio transport. Default: `localhost`. |
| 74 | `server.allowedHosts` | default | DNS rebinding protection | — | stdio transport. Default: bind host. |
| 75 | `sharedBrowserContext` | default | Share browser context between HTTP clients | — | stdio, no clients to share between. Default: `false`. |
| 76 | `extension` | default | Attach to running Edge/Chrome via bridge extension | — | We launch our own browser per mode. Default: `false`. |
| 77 | `browser.cdpEndpoint` | default | Connect to existing browser via CDP | — | We launch our own browser. Default: none. |
| 78 | `browser.cdpHeaders` | default | Headers for CDP connect | — | Depends on #77. Default: none. |
| 79 | `browser.cdpTimeout` | default | CDP connect timeout (ms) | — | Depends on #77. Default: `30000`. |
| 80 | `browser.remoteEndpoint` | default | Connect to running Playwright server | — | No use case. Default: none. |
| | **▸ Init scripts** | | | | |
| 81 | `browser.initPage[]` | default | TypeScript files evaluated on every Playwright page object | — | No custom runtime hooks needed. Default: `[]`. |
| 82 | `browser.initScript[]` | default | JS files injected into every page before site code | — | No use case (fingerprint masking, helpers, etc.). Default: `[]`. |

---

## Environment variables

Playwright MCP reads ~43 `PLAYWRIGHT_MCP_*` environment variables that override config at runtime (merge order: `defaults < configFile < env < cli`). Examples: `PLAYWRIGHT_MCP_HEADLESS`, `PLAYWRIGHT_MCP_BROWSER`, `PLAYWRIGHT_MCP_USER_DATA_DIR`, `PLAYWRIGHT_MCP_OUTPUT_DIR`, `PLAYWRIGHT_MCP_VIEWPORT_SIZE`, `PLAYWRIGHT_MCP_ISOLATED`. We do not use them; all configuration goes through one of the four `<mode>/config.json` files (with the launcher applying `--output-dir` to headless via CLI flag). Note: `recordHar.*` is **not** env-var-addressable — it's nested under `browser.contextOptions` and must be set in `config.json`.

Additional Playwright-level variables (`PWDEBUG`, `DEBUG`, `PLAYWRIGHT_BROWSERS_PATH`) are honoured by the underlying runtime — also unused.

## Hidden / undocumented flags

- `--vision` — deprecated alias for `capabilities: ["vision"]`. Hidden via `.hideHelp()`. Do not use.
- `install-browser <name>` — subcommand absent from `--help`. Delegates to Playwright's installer. Use this (not `npx playwright install <browser>`) to install headless mode's bundled browser: standalone `playwright@latest` can resolve to a different playwright-core than `@playwright/mcp`'s pin and install a mismatched browser revision (observed 2026-07-06: rev 1228 installed vs rev 1229 required).
- `browser.launchOptions.assistantMode` — forced `true` internally; not configurable.
