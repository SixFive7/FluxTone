# playwright-screenshot-hook.ps1
# PreToolUse hook for the four Playwright MCP servers' browser_take_screenshot tool.
# Denies a call that passes an explicit `filename` which is NOT under a Playwright
# outputDir / workdir / absolute path. Upstream resolves an explicit filename via
# workspaceFile() against the server CWD (the repo root), not outputDir, so a bare
# name like "foo.png" silently drops a stray untracked file in the repo root.
# See playwright/README.md > Rules > "Screenshot filenames".
#
# Registered via the `matcher` field (tool-name regex) in .claude/settings.json.
# Filename filtering is done here in-script because the `if` field's input mapping
# is undocumented for MCP tools. The same script also covers browser_snapshot if
# that tool is ever added to the matcher (it reads tool_input.filename generically).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read the PreToolUse payload from stdin. On any trouble, stay out of the way.
$stdin = [Console]::In.ReadToEnd()
try { $data = $stdin | ConvertFrom-Json } catch { exit 0 }
if ($null -eq $data) { exit 0 }

# Extract tool_input.filename defensively (StrictMode-safe).
$fn = $null
if ($data.PSObject.Properties.Name -contains 'tool_input') {
    $ti = $data.tool_input
    if ($ti -and ($ti.PSObject.Properties.Name -contains 'filename')) {
        $fn = [string]$ti.filename
    }
}

# No explicit filename => auto-naming routes into outputDir correctly. Allow.
if ([string]::IsNullOrWhiteSpace($fn)) { exit 0 }

# Normalize separators and a leading ./ for the path check.
$norm = ($fn -replace '\\', '/') -replace '^\./', ''

# Accept: under a mode output dir, under workdir/, or an absolute path (deliberate).
$ok = (
    ($norm -match '^playwright/(headless|interactive|tracing|persistent)/output/') -or
    ($norm -match '^workdir/') -or
    ($norm -match '^[A-Za-z]:/') -or
    ($norm -match '^/')
)
if ($ok) { exit 0 }

# Bare / repo-root-relative filename: block with an actionable reason.
$reason = "Playwright screenshot filename '$fn' would resolve against the repo root (server CWD), not the Playwright outputDir, leaving a stray untracked file in the repo. Re-call with a path under playwright/<mode>/output/<session-subdir>/ (the per-session dir shown in the navigate result), for example 'playwright/headless/output/<session>/$fn' -- or omit 'filename' entirely to let it auto-route into outputDir. See playwright/README.md > Rules > 'Screenshot filenames'."

@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason
    }
} | ConvertTo-Json -Depth 5 -Compress | Write-Output

exit 0
