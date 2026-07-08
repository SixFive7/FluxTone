<#
.SYNOPSIS
  Parametric launcher for the Playwright MCP server. One script, four modes.

.DESCRIPTION
  Invoked from .mcp.json with -Mode {headless|interactive|tracing|persistent}.
  Each mode loads its own playwright/<Mode>/config.json and applies
  mode-specific behaviour:

    headless    - per-session timestamped outputDir under playwright/headless/output/.
                  Collision-safe for parallel Claude Code sessions.

    interactive - single-instance via Windows named mutex
                  'Global\<RepoName>-PlaywrightInteractive'. Second concurrent
                  attempt across any Claude Code session fails fast with a clear error.
                  Sibling JSON lockfile at playwright/interactive/state/launcher.lock
                  enables stale-lock recovery if a prior launcher orphaned the mutex.

    tracing     - single-instance via separate named mutex
                  'Global\<RepoName>-PlaywrightTracing'. Independent of interactive
                  (the two can run side-by-side). Same stale-lock-recovery lockfile
                  pattern as interactive.

    persistent  - no extra handling. Chrome's SingletonLock on the persistent
                  userDataDir (playwright/persistent/profile/) provides exclusivity.
                  A second concurrent launch surfaces 'Browser is already in use'.

  ALL modes also run a parent-PID liveness watchdog: a background runspace polls
  the parent process (Claude Code) every $ParentLivenessCheckIntervalMs. When the
  parent disappears (tab/window closed), the watchdog kills the npx child tree
  (npx -> node -> chromium and any descendants) and signals clean exit through
  the existing finally block. This solves orphaned-launcher / orphaned-browser
  cases that the bare mutex pattern cannot recover from until VS Code restart.

  See playwright/LAUNCHER.md for the full launcher reference, and
  playwright/README.md for the four-server architecture and per-mode settings table.

.PARAMETER Mode
  One of: headless, interactive, tracing, persistent.

.EXAMPLE
  powershell.exe -ExecutionPolicy Bypass -NoProfile -File playwright/launch.ps1 -Mode headless

.NOTES
  Mutexes are Windows kernel objects. If the holding process crashes, the OS marks
  the mutex 'abandoned' and the next acquirer is granted ownership with an
  AbandonedMutexException - which we catch and treat as a successful acquire.

  However: if the launcher process itself becomes a zombie (parent severed stdio
  but child still runs), the mutex stays held until that zombie is killed. The
  parent-PID watchdog (all modes) and lockfile stale-break (mutex modes) handle
  this. The watchdog is the primary mechanism; the lockfile is a defensive
  fallback for the case where a prior session crashed before the watchdog could
  fire (e.g. powershell.exe itself was force-killed).

  Mutex names are scoped to the project ("<RepoName>-...") so other projects in
  parallel Claude Code windows cannot collide with these locks.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('headless', 'interactive', 'tracing', 'persistent')]
  [string]$Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Force UTF-8 stdio so multi-byte characters survive the pipe to Claude Code.
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Resolve repo root from this script's location: launch.ps1 lives in playwright/,
# so go up one level. Defensive: do not assume CWD is the repo root.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepoName = Split-Path -Leaf $RepoRoot
Set-Location -Path $RepoRoot

# ---- Tunables ---------------------------------------------------------------

# How often the parent-PID watchdog polls Get-Process for the original parent.
# 2000ms balances responsiveness (cleanup within ~2s of parent death) and CPU
# load (idle launchers shouldn't burn cycles).
$ParentLivenessCheckIntervalMs = 2000

# Mutex-mode lockfile config. Maps modes that take a mutex to their lockfile path.
$LockfilePaths = @{
  'interactive' = 'playwright/interactive/state/launcher.lock'
  'tracing'     = 'playwright/tracing/state/launcher.lock'
}
$MutexNames = @{
  'interactive' = "Global\$RepoName-PlaywrightInteractive"
  'tracing'     = "Global\$RepoName-PlaywrightTracing"
}

# Per-mode diagnostic log (side channel; stdout/stderr is MCP-relevant and must
# stay clean of launcher chatter).
$LogPath = "playwright/$Mode/state/launcher.log"

# ---- Helpers ----------------------------------------------------------------

function Write-LauncherLog {
  param([string]$Message)
  $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fff')
  $line = "[$stamp] [pid $PID] [$Mode] $Message"
  try {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -Path $dir)) {
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Add-Content -Path $LogPath -Value $line -Encoding utf8
  }
  catch {
    # Logging must never break the launcher. Swallow.
  }
}

function Get-ParentProcessId {
  param([int]$ChildPid)
  try {
    $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ChildPid" -ErrorAction Stop
    if ($null -ne $proc) { return [int]$proc.ParentProcessId }
  }
  catch {
    Write-LauncherLog "Get-ParentProcessId failed for pid $ChildPid : $($_.Exception.Message)"
  }
  return 0
}

function Test-ProcessAlive {
  param([int]$TargetPid)
  if ($TargetPid -le 0) { return $false }
  try {
    $null = Get-Process -Id $TargetPid -ErrorAction Stop
    return $true
  }
  catch {
    return $false
  }
}

function Stop-ProcessTree {
  # Recursively kill a process and all descendants. Used to clean up the
  # npx -> node -> chromium chain when the parent watchdog fires.
  param([int]$RootPid)
  if ($RootPid -le 0) { return }
  try {
    $children = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $RootPid" -ErrorAction SilentlyContinue
    foreach ($c in @($children)) {
      Stop-ProcessTree -RootPid ([int]$c.ProcessId)
    }
  }
  catch {
    Write-LauncherLog "Stop-ProcessTree enumerate failed for pid $RootPid : $($_.Exception.Message)"
  }
  try {
    Stop-Process -Id $RootPid -Force -ErrorAction Stop
    Write-LauncherLog "Killed pid $RootPid"
  }
  catch {
    # Process may have already exited - that's fine.
  }
}

function Get-ProcessCommandLine {
  param([int]$TargetPid)
  if ($TargetPid -le 0) { return $null }
  try {
    $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $TargetPid" -ErrorAction Stop
    if ($null -ne $proc) { return [string]$proc.CommandLine }
  }
  catch {}
  return $null
}

function Test-LauncherSignature {
  # Heuristic: a real launcher process is powershell.exe (or pwsh.exe) running
  # launch.ps1 with the same -Mode. This is a sanity check on the lockfile -
  # if pid is recycled to e.g. notepad.exe, we want to treat the lock as stale.
  param([int]$TargetPid, [string]$ExpectedMode)
  $cmdline = Get-ProcessCommandLine -TargetPid $TargetPid
  if ([string]::IsNullOrEmpty($cmdline)) { return $false }
  $hasLauncher = $cmdline -match 'launch\.ps1'
  $hasMode = $cmdline -match "(?i)-Mode\s+$([regex]::Escape($ExpectedMode))\b"
  return ($hasLauncher -and $hasMode)
}

function Write-Lockfile {
  param(
    [string]$Path,
    [string]$MutexName
  )
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $payload = [ordered]@{
    pid        = $PID
    started    = (Get-Date).ToString('o')
    mode       = $Mode
    mutexName  = $MutexName
  } | ConvertTo-Json -Compress
  $payload | Out-File -FilePath $Path -Encoding utf8 -NoNewline
}

function Read-Lockfile {
  param([string]$Path)
  if (-not (Test-Path -Path $Path)) { return $null }
  try {
    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    Write-LauncherLog "Lockfile at $Path unreadable: $($_.Exception.Message). Treating as stale."
    return $null
  }
}

function Remove-LockfileSafe {
  param([string]$Path)
  if ($null -eq $Path) { return }
  if (Test-Path -Path $Path) {
    try { Remove-Item -Path $Path -Force -ErrorAction Stop }
    catch { Write-LauncherLog "Lockfile remove failed: $($_.Exception.Message)" }
  }
}

function Invoke-MutexAcquire {
  # Mutex acquire with stale-lock recovery (Option A).
  #
  # Flow:
  #   1. Try to acquire the mutex normally (with abandoned-mutex catch).
  #   2. If acquire fails, inspect the sibling lockfile:
  #      - if PID dead OR commandline doesn't match a launcher: stale -> remove
  #        lockfile, retry acquire (Windows will surface AbandonedMutexException
  #        on the next attempt once the original holder is gone; if not, the
  #        mutex is genuinely held and we error out cleanly).
  #      - otherwise: lock is live, refuse to acquire.
  #   3. On success, overwrite lockfile with current PID/timestamp.
  param(
    [string]$MutexName,
    [string]$LockfilePath
  )
  $created = $false
  $mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$created)
  $acquired = $created
  if (-not $acquired) {
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
  }

  if (-not $acquired) {
    # Probe failed. Check whether the lockfile points at a dead/wrong process.
    $existing = Read-Lockfile -Path $LockfilePath
    $stale = $false
    if ($null -eq $existing) {
      # No lockfile but mutex held - some other process owns it without our
      # bookkeeping. Treat as live (cannot prove staleness).
      Write-LauncherLog "Mutex $MutexName held but no lockfile present. Treating as live."
    }
    else {
      # PSObject.Properties access is StrictMode-safe (no exception on missing prop).
      $heldPid = 0
      $pidProp = $existing.PSObject.Properties['pid']
      if ($null -ne $pidProp -and $null -ne $pidProp.Value) {
        try { $heldPid = [int]$pidProp.Value } catch {}
      }
      $alive = Test-ProcessAlive -TargetPid $heldPid
      $matchesLauncher = $false
      if ($alive) { $matchesLauncher = Test-LauncherSignature -TargetPid $heldPid -ExpectedMode $Mode }
      if (-not $alive) {
        Write-LauncherLog "Lockfile pid $heldPid is dead. Forcing stale cleanup."
        $stale = $true
      }
      elseif (-not $matchesLauncher) {
        Write-LauncherLog "Lockfile pid $heldPid alive but commandline does not match launcher signature. Forcing stale cleanup."
        $stale = $true
      }
    }

    if ($stale) {
      Remove-LockfileSafe -Path $LockfilePath
      # Retry acquire. If the original holder's process is gone, Windows should
      # mark the mutex abandoned and the next WaitOne throws
      # AbandonedMutexException (which we treat as success). If for some reason
      # it does not (e.g. a different process still holds the handle), the
      # acquire stays $false and we fall through to the clean error below.
      try { $acquired = $mutex.WaitOne(0) }
      catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    }
  }

  if (-not $acquired) {
    $mutex.Dispose()
    return $null
  }

  Write-Lockfile -Path $LockfilePath -MutexName $MutexName
  Write-LauncherLog "Mutex $MutexName acquired. Lockfile $LockfilePath written."
  return $mutex
}

# ---- Pre-launch validation --------------------------------------------------

$ConfigPath = "playwright/$Mode/config.json"
if (-not (Test-Path -Path $ConfigPath)) {
  Write-Error "Config not found: $ConfigPath (cwd=$RepoRoot)"
  exit 1
}

# Ensure the state directory exists ahead of time so logging works.
$StateDir = "playwright/$Mode/state"
if (-not (Test-Path -Path $StateDir)) {
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
}

Write-LauncherLog "Launcher start. ParentPid=$(Get-ParentProcessId -ChildPid $PID)"

# ---- Mode-specific setup ----------------------------------------------------

$ExtraArgs = @()
$Mutex = $null
$LockfilePath = $null

switch ($Mode) {

  'headless' {
    # Per-session outputDir: timestamp + 4-char random suffix.
    # Eliminates collisions when multiple Claude Code sessions run headless in parallel
    # within the same second.
    $Timestamp = Get-Date -Format 'yyyy-MM-dd-HH-mm-ss'
    $Suffix = -join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    $SessionDir = "playwright/headless/output/$Timestamp-$Suffix"
    New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
    # CLI flag wins over config (merge order: defaults < configFile < env < CLI).
    $ExtraArgs = @('--output-dir', $SessionDir)
  }

  'interactive' {
    $LockfilePath = $LockfilePaths[$Mode]
    $Mutex = Invoke-MutexAcquire -MutexName $MutexNames[$Mode] -LockfilePath $LockfilePath
    if ($null -eq $Mutex) {
      Write-Error 'playwright-interactive is already running in another Claude Code session. Wait for it to finish or close the other session.'
      exit 1
    }
  }

  'tracing' {
    $LockfilePath = $LockfilePaths[$Mode]
    $Mutex = Invoke-MutexAcquire -MutexName $MutexNames[$Mode] -LockfilePath $LockfilePath
    if ($null -eq $Mutex) {
      Write-Error 'playwright-tracing is already running in another Claude Code session. Wait for it to finish or close the other session.'
      exit 1
    }
  }

  'persistent' {
    # No external lock. Chrome's SingletonLock on playwright/persistent/profile/
    # blocks a second concurrent launch and produces a clear error.
  }
}

# ---- Parent-PID watchdog (Option B, all modes) ------------------------------
#
# Why this exists: when a Claude Code tab closes, the parent (the CC process
# that spawned this powershell) goes away but the npx child can survive (its
# stdio is no longer connected, but its main loop does not necessarily notice).
# That leaves an orphaned launcher holding the mutex / lockfile / chromium.
#
# Mechanism: capture the parent PID NOW (before anything can re-parent us),
# spawn a runspace that polls Get-Process on that PID every N ms, and when it
# disappears, kill the entire npx descendant tree. The main thread then
# observes npx exiting and runs its normal finally block (mutex release,
# lockfile cleanup).
#
# CRUCIAL: the watchdog must NOT touch [Console]::In. The MCP server reads
# stdin for JSON-RPC; consuming bytes would corrupt the protocol.

$ParentPid = Get-ParentProcessId -ChildPid $PID
Write-LauncherLog "Parent-liveness watchdog: tracking parent pid $ParentPid (poll ${ParentLivenessCheckIntervalMs}ms)"

# Shared state between main thread and watchdog runspace.
$WatchdogState = [hashtable]::Synchronized(@{
  ChildPid       = 0     # npx child PID; main sets this once $Process is launched
  Stop           = $false # main asks watchdog to exit (normal shutdown)
  TriggeredKill  = $false # watchdog records that it fired (for logging)
})

$Runspace = [runspacefactory]::CreateRunspace()
$Runspace.ApartmentState = 'STA'
$Runspace.ThreadOptions = 'ReuseThread'
$Runspace.Open()
$Runspace.SessionStateProxy.SetVariable('ParentPid', $ParentPid)
$Runspace.SessionStateProxy.SetVariable('PollMs', $ParentLivenessCheckIntervalMs)
$Runspace.SessionStateProxy.SetVariable('State', $WatchdogState)
$Runspace.SessionStateProxy.SetVariable('LogPath', $LogPath)
$Runspace.SessionStateProxy.SetVariable('LauncherMode', $Mode)
$Runspace.SessionStateProxy.SetVariable('LauncherPid', $PID)

$Watchdog = [powershell]::Create()
$Watchdog.Runspace = $Runspace
[void]$Watchdog.AddScript({
  function _Log([string]$msg) {
    try {
      $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fff')
      Add-Content -Path $LogPath -Value "[$stamp] [pid $LauncherPid] [$LauncherMode] [watchdog] $msg" -Encoding utf8
    } catch {}
  }
  function _KillTree([int]$rootPid) {
    if ($rootPid -le 0) { return }
    try {
      $kids = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $rootPid" -ErrorAction SilentlyContinue
      foreach ($k in @($kids)) { _KillTree ([int]$k.ProcessId) }
    } catch {}
    try { Stop-Process -Id $rootPid -Force -ErrorAction Stop; _Log "killed pid $rootPid" } catch {}
  }

  _Log "watchdog started, watching parent pid $ParentPid"
  while (-not $State.Stop) {
    Start-Sleep -Milliseconds $PollMs
    if ($State.Stop) { break }
    $alive = $false
    try { $null = Get-Process -Id $ParentPid -ErrorAction Stop; $alive = $true } catch { $alive = $false }
    if (-not $alive) {
      _Log "parent pid $ParentPid has exited - tearing down npx tree (child pid=$($State.ChildPid))"
      $State.TriggeredKill = $true
      if ($State.ChildPid -gt 0) { _KillTree ([int]$State.ChildPid) }
      # Also kill ourselves' descendants in case ChildPid was never set or has already detached.
      _KillTree ([int]$LauncherPid)
      break
    }
  }
  _Log "watchdog exiting (Stop=$($State.Stop), TriggeredKill=$($State.TriggeredKill))"
})

$WatchdogHandle = $Watchdog.BeginInvoke()

# ---- Spawn npx and block ----------------------------------------------------

$Process = $null
$exitCode = 0
try {
  # Launch npx as a tracked child so the watchdog can kill its descendant tree.
  #
  # Why not Start-Process with -FilePath 'npx'?  Start-Process won't run a .ps1
  # shim and PATH-resolution of bare 'npx' yields npx.ps1 first on Windows.
  #
  # Why not [System.Diagnostics.Process]::Start('npx.cmd', ...)?  Bypasses
  # cmd.exe resolution, which subtly breaks the npm-prefix probe inside npx.cmd
  # and leaves node modules unresolvable on some setups.
  #
  # Solution: invoke via cmd.exe /c -- treats the call exactly like a shell
  # invocation (matching the previous `& npx` semantics), stdio inherits, and
  # we still get a Process object via Start-Process with -PassThru. The extra
  # cmd.exe layer dies along with its npx child.
  $argList = @('-y', '@playwright/mcp@latest', '--config', $ConfigPath, '--output-mode', 'file') + $ExtraArgs
  $cmdArgs = @('/c', 'npx') + $argList
  $Process = Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -NoNewWindow -PassThru
  $WatchdogState.ChildPid = $Process.Id
  Write-LauncherLog "cmd.exe -> npx started (pid $($Process.Id))"

  $Process.WaitForExit()
  Write-LauncherLog "npx exited with code $($Process.ExitCode)"
  $exitCode = $Process.ExitCode
}
catch {
  Write-LauncherLog "Launcher main block error: $($_.Exception.Message)"
  throw
}
finally {
  # Tell watchdog to stop (whether we exited normally or it killed us).
  $WatchdogState.Stop = $true
  try {
    if ($null -ne $WatchdogHandle) {
      # Give the watchdog a moment to notice $Stop. Don't block forever.
      $null = $Watchdog.EndInvoke($WatchdogHandle)
    }
  }
  catch {
    Write-LauncherLog "Watchdog end error: $($_.Exception.Message)"
  }
  finally {
    try { $Watchdog.Dispose() } catch {}
    try { $Runspace.Close() } catch {}
    try { $Runspace.Dispose() } catch {}
  }

  if ($null -ne $Process) {
    try { $Process.Dispose() } catch {}
  }

  if ($null -ne $Mutex) {
    try { $Mutex.ReleaseMutex() } catch {}
    try { $Mutex.Dispose() } catch {}
    Write-LauncherLog "Mutex released."
  }

  if ($null -ne $LockfilePath) {
    Remove-LockfileSafe -Path $LockfilePath
    Write-LauncherLog "Lockfile $LockfilePath removed."
  }

  Write-LauncherLog "Launcher exit."
}

exit $exitCode
