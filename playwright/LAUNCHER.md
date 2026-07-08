# Launcher (`playwright/launch.ps1`)

Parametric PowerShell launcher for the four Playwright MCP servers. Reference doc for [launch.ps1](launch.ps1).

## Files

- [launch.ps1](launch.ps1) — the launcher. Invoked from [../.mcp.json](../.mcp.json) with `-Mode {headless|interactive|tracing|persistent}`. Selects the matching `playwright/<Mode>/config.json` and applies mode-specific pre-launch behaviour, then execs `npx @playwright/mcp@latest`.

## Why one parametric script

Each `.mcp.json` entry needs slightly different launch logic:
- `headless` needs a timestamped per-session `outputDir` so parallel Claude Code sessions don't collide.
- `interactive` and `tracing` need a Windows named mutex acquired before launch to enforce single-instance.
- `persistent` needs nothing extra (Chrome's `SingletonLock` does it).

Rather than four near-duplicate scripts, one parametric script keeps the logic in one place. Adding a new mode or changing common behaviour means editing one file.

## Mode behaviour matrix

| Mode | Pre-launch | npx CLI additions | Mutex name | Lockfile | Watchdog | Notes |
|---|---|---|---|---|---|---|
| headless | create `playwright/headless/output/{ts}-{4chr}/` | `--output-dir <session-dir>` | none | none | yes | parallel-safe |
| interactive | acquire mutex + write lockfile | none | `Global\<RepoName>-PlaywrightInteractive` | `playwright/interactive/state/launcher.lock` | yes | exclusive across all CC sessions |
| tracing | acquire mutex + write lockfile | none | `Global\<RepoName>-PlaywrightTracing` | `playwright/tracing/state/launcher.lock` | yes | independent of interactive |
| persistent | nothing | none | none (Chrome `SingletonLock`) | none | yes | profile dir is the lock |

## Mutex semantics

`Global\` prefix scopes the mutex system-wide (across user sessions, including services).

`<RepoName>-` prefix scopes it to this project — here `<RepoName>` is this repository's folder name, substituted into the mutex name at launch by `launch.ps1` — so a second Claude Code window in a *different* project that happens to also use these names won't collide.

Windows kernel handles abandoned mutexes automatically: if the holding process crashes, the OS marks the mutex abandoned, and the next acquirer's `WaitOne` throws `AbandonedMutexException` — which the launcher catches and treats as a successful acquire.

**Stale-lock recovery (interactive, tracing).** The kernel-level abandoned-mutex handling fails when the launcher process is still alive but orphaned (parent died, stdio severed, but the launcher loop never exited). In that case the mutex stays held. To recover: alongside each mutex acquire the launcher writes a sibling JSON lockfile (`<mode>/state/launcher.lock`) recording `{pid, started, mode, mutexName}`. On a contended acquire, the next launcher reads the lockfile; if the recorded PID is dead OR its command line doesn't match the launcher signature, the lockfile is treated as stale and the mutex acquire is retried. The lockfile is always overwritten on successful acquire and removed in `finally`.

**Parent-PID liveness watchdog (all modes).** All four modes spawn a background runspace that polls the parent process every `$ParentLivenessCheckIntervalMs` (default 2000ms). When the parent (Claude Code) disappears — tab/window closed, VS Code crash — the watchdog kills the entire npx descendant tree (node, chromium, …) and lets the main thread fall through its `finally` block, which releases the mutex and removes the lockfile. This solves the orphaned-launcher class of failures the bare mutex cannot.

**Diagnostic side-channel.** stdout/stderr is reserved for MCP JSON-RPC; the launcher logs to `playwright/<mode>/state/launcher.log` instead. That directory and the lockfile inside it are gitignored. Tail the log if you suspect launcher misbehaviour.

## Debugging

**The MCP server failed to start.** Run the script directly in a terminal to see its actual error:
```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File playwright/launch.ps1 -Mode headless
```
The MCP server is a long-running stdio process — it will sit waiting for protocol messages. Ctrl+C to exit. The actual error (config not found, npx failed, etc.) appears on stderr before that. For richer detail, tail the per-mode launcher log: `playwright/<mode>/state/launcher.log`.

**"playwright-interactive is already running"** — another Claude Code session (or a stale prior launcher) holds the mutex. The launcher first attempts stale-lock recovery via the sibling lockfile (`playwright/interactive/state/launcher.lock`); if recovery cannot prove staleness (no lockfile, OR live PID with matching launcher signature), the message above stands. Close the other session or wait.

**Stale `SingletonLock` on persistent profile** — see [persistent/README.md](persistent/README.md).

**Tracing HAR file empty** — if the browser context didn't close cleanly, the HAR may not have flushed. Reload `network.har` after explicitly closing the browser, or wait a few seconds.

## Adding a new mode

1. Create `playwright/<newmode>/` with `config.json` and `README.md` matching the existing pattern.
2. Add a new case to the `switch` in [launch.ps1](launch.ps1) with whatever pre-launch behaviour the mode needs.
3. Add a new `mcpServers.playwright-<newmode>` entry in [../.mcp.json](../.mcp.json) invoking the launcher with `-Mode <newmode>`.
4. Add a new row to the settings table and the "When to use which" decision rule in [README.md](README.md).
5. Update the hook in [../.claude/settings.json](../.claude/settings.json) and the matcher messages in [../.claude/hooks/playwright-config-hook.ps1](../.claude/hooks/playwright-config-hook.ps1) if needed.

## Why PowerShell instead of Node

This project is Windows-only and already uses PowerShell for `.claude/hooks/`. Windows named mutexes via `System.Threading.Mutex` are kernel-managed and self-cleaning on process death — no `package.json`, no `node_modules/`, no `proper-lockfile`. The stale-lock-recovery lockfile and the parent-PID watchdog runspace add a few helper functions on top — see [launch.ps1](launch.ps1).
