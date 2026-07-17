# FLUX·TONE — Repository Guide

FLUX·TONE is a single-file, static, browser-based generative synthesizer. The whole app
is one self-contained HTML file per version (`v1.html`, `v2.html`, …), and `index.html`
is a copy of the latest. There is no build system, package manager, or server — edits are
made directly in the HTML, and it is hosted as static content.

When adding a new version, keep every previous `vN.html` in place, copy the newest one
over `index.html`, and add a matching entry to `CHANGELOG.md`.

## Playwright usage policy

Four Playwright MCP servers are configured: `playwright-headless`, `playwright-interactive`, `playwright-tracing`, `playwright-persistent`. Apply this policy when choosing one:

1. **Default to `playwright-headless`** — parallel-safe, ephemeral, no state. Use it for almost everything that needs browser automation.
2. **Use Playwright as little as possible.** After one research round on a new site, evaluate whether the task can be done by calling the underlying API directly (with credentials you already have). Prefer direct HTTP over browser automation — it is faster, more reliable, and easier to debug.
3. **Use `playwright-tracing`** to reverse-engineer a site's API shapes (request/response, auth flow, WebSocket frames). The goal is usually to *stop* using Playwright on that site — capture enough trace to make direct calls work, then switch.
4. **Use `playwright-interactive` only** when a credentialed login is required and the credentials are not already on hand. Tell the user what you are about to do. Do not see, ask for, or attempt to capture credentials — the user types them directly in the visible window.
5. **Use `playwright-persistent` only** when the user explicitly instructs you to AND has validated the request. Saved logins in `playwright/persistent/profile/` are accessible to any agent that touches that server — treat as a security risk, never default to it.

The rules above are sufficient for using the servers. Only read [playwright/README.md](playwright/README.md) if you need the architecture rationale, the per-mode settings table, or are about to *change* the Playwright configuration.

### Automation hooks

Two Claude Code `PreToolUse` hooks in [.claude/settings.json](.claude/settings.json) support the setup:

- **`.claude/hooks/playwright-config-hook.ps1`** — fires before reading or editing any Playwright setup file and injects context about the four-server architecture, plus the drift rule: if you change a value in a `config.json` or `.mcp.json`, update the matching row of [playwright/README.md](playwright/README.md) in the same commit.
- **`.claude/hooks/playwright-screenshot-hook.ps1`** — guards `browser_take_screenshot`, denying an explicit `filename` that would resolve against the repo root instead of the mode's `output/` directory (an upstream quirk that otherwise litters the repo root with stray screenshots).

## .work — agent scratch space

The `.work/` directory (gitignored, created on demand) is scratch space for agent
workflows that follow a download → restructure → rename → review cycle. Each session gets
its own subdirectory; nothing under `.work/` is committed.
