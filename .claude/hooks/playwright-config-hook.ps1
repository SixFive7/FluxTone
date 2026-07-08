# playwright-config-hook.ps1
# Fires BEFORE Read / Edit / Write on any file that is part of the four-server
# Playwright MCP setup (matched via the `if` field in .claude/settings.json).
# Injects the architectural context so the agent has it before interacting
# with the file - edits are informed, not retroactively corrected, and
# readers know which file they are touching is part of a larger system.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Force UTF-8 stdout so multi-byte chars (em-dash etc.) survive the pipe to
# Claude Code's JSON parser. Without this, additionalContext is silently dropped.
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Single-quoted here-string: no escape processing. Backticks render literally.
$message = @'
[Playwright MCP config reminder] You are about to touch one of the files that defines the four-server Playwright MCP setup.

Architecture - four MCP servers, four subfolders, one parametric launcher:

  1. .mcp.json
       Bootstraps four MCP server entries (playwright-headless, playwright-interactive, playwright-tracing, playwright-persistent).
       Each entry invokes launch.ps1 with a different -Mode argument.

  2. playwright/{mode}/config.json
       Per-mode Playwright configuration. Each mode (headless, interactive, tracing, persistent) has its own config.json.
       Canonical source of Playwright-level settings for that mode. Absent keys = upstream defaults.

  3. playwright/{mode}/README.md
       Per-mode docs explaining the mode's purpose, when to use it, mode-specific behaviour.

  4. playwright/launch.ps1
       Parametric PowerShell launcher. Handles per-session timestamped outputDir (headless),
       Windows named-mutex exclusivity (interactive, tracing), and direct passthrough (persistent).

  5. playwright/LAUNCHER.md
       Launcher reference: parameters, mode behaviour matrix, mutex semantics, debugging.

  6. playwright/README.md
       SINGLE SOURCE OF TRUTH - the canonical architecture overview, "when to use which server" decision rules,
       full settings table covering all four modes (with value columns per mode), Rules section (drift, HAR convention,
       screenshot discipline, profile reset, debugging pointers, upgrade procedure).

Modes summary:
  - headless    : ephemeral (browser.isolated=true), HEADLESS, parallel-safe, no HAR.
                  Launcher overrides outputDir per session: playwright/headless/output/{yyyy-MM-dd-HH-mm-ss}-{4chr}/
                  No mutex - many parallel Claude Code sessions OK.
  - interactive : ephemeral, HEADED, single-instance via mutex Global\<RepoName>-PlaywrightInteractive. No HAR.
  - tracing     : ephemeral, HEADED, single-instance via separate mutex Global\<RepoName>-PlaywrightTracing.
                  Full recordHar + saveSession + verbose console.
  - persistent  : PERSISTENT userDataDir at playwright/persistent/profile/, HEADED.
                  Exclusivity via Chrome SingletonLock (automatic). No HAR.

Drift rule: when you change a VALUE in any <mode>/config.json or in .mcp.json, update the matching row
in playwright/README.md (Value column; Motivation column if the reasoning shifts) in the SAME commit.
Motivation only lives in the markdown - it cannot recover itself.

Rules and reference data live exclusively in playwright/README.md. Read it before making config changes
if you have not yet this conversation. Per-mode specifics live in playwright/{mode}/README.md.
Launcher specifics live in playwright/LAUNCHER.md.

This hook is defined in .claude/settings.json and runs .claude/hooks/playwright-config-hook.ps1.
To change the hook behaviour or matcher list, edit those files.
'@

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = 'PreToolUse'
        permissionDecision = 'allow'
        additionalContext = $message
    }
} | ConvertTo-Json -Depth 5 -Compress

Write-Output $payload
exit 0
