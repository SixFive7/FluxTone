# playwright/tracing

**For debugging. Full HAR + Playwright session capture + verbose console.**

Ephemeral, headed, exclusive. Only one Claude Code session may run this at a time.

## When to use

Investigating *how* a page behaves: network requests/responses (including WebSocket frames), console messages, the exact sequence of MCP tool calls in a session, page state at each step. Specifically:
- Reverse-engineering an undocumented API.
- Debugging why an agent's action didn't have the expected effect.
- Capturing a network trace to share with someone else.

Do **not** use this for routine work - it produces large artefacts (HAR files can be megabytes per session) and is single-instance.

MCP tool prefix: `mcp__playwright-tracing__browser_*`.

## What's in this folder

- `config.json` - Playwright MCP configuration. `isolated: true`, `headless: false`, full HAR recording at `output/network.har`, `saveSession: true`, `console.level: info`. See [../README.md](../README.md) for the full settings table.
- `output/` - HAR files, session markdown traces (`session-{timestamp}/session.md`), screenshots. Gitignored.
- `profile/` - intentionally empty placeholder for visual symmetry with the other modes. See [profile/README.md](profile/README.md). The isolated tmp profile lives in Playwright's tmpdir, not here.

## Concurrency model

- Single-instance enforced via Windows named mutex `Global\<RepoName>-PlaywrightTracing`. (`<RepoName>` is this repository's folder name.)
- Independent of the [interactive](../interactive/) mutex - the two modes can be running side-by-side (interactive in one Claude Code session, tracing in another), but you can't have two tracing sessions at once.
- Acquired and released by [../launch.ps1](../launch.ps1).

## HAR file convention

`recordHar.path` is **static** (`playwright/tracing/output/network.har`) - Playwright does not support placeholder substitution. The file is overwritten every time a new browser context starts within the session.

If a HAR trace is worth keeping, rename it before the next context starts:

```powershell
Move-Item playwright/tracing/output/network.har `
  "playwright/tracing/output/network-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss')-<task-slug>.har"
```

Unrenamed `network.har` files are considered disposable.

## Session markdown trace

With `saveSession: true`, every MCP tool call is appended to `output/session-{timestamp}/session.md` as a `### Tool call: <name>` heading with `Args` and `Result` JSON-fenced blocks. This is the post-hoc trace for debugging complex flows - referenced screenshots/snapshots are saved as siblings in the same folder.

## Authentication

This mode is ephemeral. If the task requires login first, sign in inside the visible browser window when it appears - the agent should not see credentials. State is wiped at session close.
