# playwright/interactive

**Rare. For tasks that need a visible browser window so the user can sign in by hand.**

Ephemeral, headed, exclusive. Only one Claude Code session may run this at a time.

## When to use

A task requires credentials the agent should not see (typically: log in to a site / a vendor portal as a human, then let the agent take over). The browser window pops onto the user's screen; the user types credentials directly; the agent then drives the authenticated session.

Do **not** use this for routine work. Use [../headless/](../headless/) instead.

MCP tool prefix: `mcp__playwright-interactive__browser_*`.

## What's in this folder

- `config.json` - Playwright MCP configuration. `isolated: true` (in-memory tmp profile, wiped on close), `headless: false`. No HAR recording. See [../README.md](../README.md) for the full settings table.
- `output/` - screenshots, snapshots, session traces saved during the run. Gitignored.
- `profile/` - intentionally empty placeholder for visual symmetry with the other modes. See [profile/README.md](profile/README.md). Nothing is ever written there because the isolated tmp profile lives in Playwright's tmpdir.

**Nothing persists across sessions.** That's the point of interactive — no credentials linger after the session ends. The empty `profile/` placeholder is the visible evidence of that guarantee.

## Concurrency model

- Single-instance enforced via Windows named mutex `Global\<RepoName>-PlaywrightInteractive`. (`<RepoName>` is this repository's folder name.)
- The mutex is acquired by [../launch.ps1](../launch.ps1) before invoking `npx`. Second concurrent launch attempt fails fast with a clear error and the MCP server does not start in the second session.
- Mutex is released when the holding process exits (cleanly or via crash - the Windows kernel handles abandoned-mutex recovery).

## Workflow expectations

A typical interactive task:
1. Agent navigates to the login page.
2. Browser window appears on user's screen.
3. Agent tells the user to sign in. **Agent does not see, read, or ask for credentials.**
4. User signs in, completes 2FA if prompted, confirms with the agent.
5. Agent verifies the authenticated state, then performs the task.
6. Browser window closes when the MCP server stops. Tmpdir profile is wiped automatically.

## Need persistent login state across sessions?

This mode forgets everything between runs. If you want logins to survive (and accept that any agent calling that server then shares those credentials), use [../persistent/](../persistent/) instead.
