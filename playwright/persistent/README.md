# playwright/persistent

**The only mode where browser state survives between sessions.**

Persistent profile, headed, exclusive via Chrome's `SingletonLock`.

## When to use

- Long-running personal sessions where logins persist across runs (a site / vendor portals you sign into manually once and reuse).
- Tasks where the agent reasonably has access to the credentials already stored in this profile.

**Important security note:** any agent calling this MCP server has access to every login stored in `profile/`. Do not use this server in workflows where the agent shouldn't see those credentials. For credential-sensitive one-shots, use [../interactive/](../interactive/) instead, which is ephemeral.

MCP tool prefix: `mcp__playwright-persistent__browser_*`.

## What's in this folder

- `config.json` - Playwright MCP configuration. `userDataDir: playwright/persistent/profile`, `headless: false`. No HAR. See [../README.md](../README.md) for the full settings table.
- `profile/` - Chrome's persistent user-data directory. Cookies, localStorage, cache, extensions, autofill, history. Gitignored.
- `output/` - screenshots, snapshots, session traces. Gitignored.
- `state/` - launcher runtime state (lockfiles, log), created on demand. See [../LAUNCHER.md](../LAUNCHER.md). Gitignored.

Any logins you establish in this profile persist here between sessions.

## Concurrency model

- Single-instance enforced by Chrome's `SingletonLock` file inside `profile/`. No mutex script needed - the lock is automatic.
- Second concurrent launch attempt produces `Browser is already in use` from Playwright. Clear failure surface.

## Resetting the profile (force fresh logins)

If logins get stale, the profile gets corrupted, or you want to start fresh:

```powershell
Remove-Item -Recurse -Force playwright/persistent/profile/*
```

Then the next launch starts with a clean profile (everything logged out).

## When `SingletonLock` becomes a problem

If Playwright or Chrome crashes hard and leaves a stale `SingletonLock` file behind, the next launch may refuse with `Browser is already in use` even though nothing is running. Remove the lock file manually:

```powershell
Remove-Item playwright/persistent/profile/SingletonLock -ErrorAction SilentlyContinue
```

(Don't do this routinely - only when you're certain no other Chrome process owns the profile.)
