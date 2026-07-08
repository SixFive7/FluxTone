# playwright/headless

**The default mode for routine agent work.**

Ephemeral, headless, parallel-safe. Many Claude Code sessions can run this server simultaneously without interfering.

## When to use

This is the right mode for almost everything an agent does in this repo: scraping data, filling forms with credentials it already has, checking a page, fetching content. Use this unless one of the other three modes is specifically required.

MCP tool prefix: `mcp__playwright-headless__browser_*`.

## What's in this folder

- `config.json` - Playwright MCP configuration. `isolated: true` (in-memory tmp profile), `headless: true`, and deliberately **no `channel`** — headless runs Playwright's bundled chromium-headless-shell rather than system Chrome, because Chrome's modern headless can surface a blank window on Windows. The other three (headed) modes keep `channel: "chrome"`. See [../README.md](../README.md) for the full settings table.
- `output/` - per-session subdirectories created by the launcher, named `{yyyy-MM-dd-HH-mm-ss}-{4-char-suffix}/`. Gitignored. Each parallel session writes only into its own subdir, so collisions are impossible.
- `profile/` - intentionally empty placeholder for visual symmetry with the other modes. See [profile/README.md](profile/README.md). The isolated tmp profile lives in Playwright's tmpdir, not here.

## Concurrency model

- Profile is in-memory per session (Playwright tmpdir created by `--isolated`). Never touches disk. No `SingletonLock` to fight.
- `outputDir` is overridden per session by [../launch.ps1](../launch.ps1) - each launch gets a fresh timestamped subdir.
- HAR recording is **disabled**. If you need HAR, switch to [../tracing/](../tracing/).
- No mutex. Any number of Claude Code sessions can run this in parallel.

## Finding your session's output files

The agent doesn't need to be told the path explicitly. Every Playwright MCP tool response includes the resolved path of any file it wrote (screenshots, snapshots, downloads, session logs). Read it from the response. The `outputDir` for the session is the parent of those returned paths.

## Cleanup

`output/` accumulates one subdir per session. There is no automatic GC. Wipe the folder periodically to reclaim disk if needed:

```powershell
Remove-Item -Recurse -Force playwright/headless/output/*
```
