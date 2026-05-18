<#
.SYNOPSIS
    Day-of pre-stage wrapper. Run after Build.ps1, before walking on stage.

.DESCRIPTION
    Build.ps1 stands up a clean machine. This script gets a *running* machine
    into "ready to demo" state. Each step is a thin wrapper around an existing
    script; this file just sequences them, checks exit codes, and stops on
    the first hard failure so you don't walk on stage with a half-staged box.

    Steps (in order):
        1. Verify-Build.ps1     - probes Docker, container, SQL, Ollama, Caddy.
                                  Auto-starts Docker / container / AI services
                                  if they're down. Hard-fails if anything is
                                  unrecoverable.
        2. Reset-ForBeat2.ps1   - truncates Incident, drops the JSON index that
                                  Beat 2 builds live. Leaves IncidentArchive
                                  (~301 rows) and Runbook (20 rows) intact.
        3. Warmup-Ai.ps1        - one chat + one embed call so phi4-mini and
                                  mxbai-embed-large are pinned in memory
                                  (OLLAMA_KEEP_ALIVE=-1).
        4. Start-LiveSite.ps1   - Aspire AppHost: DAB on :8765, Blazor WASM
                                  on :8080. Backgrounded with logs in
                                  dotnet/AppHost/apphost.{out,err}.log.

    With -DryRun, also runs:
        5. Test-AgentPath.ps1   - full Beat-4 round trip (Copilot CLI -> Claude
                                  Opus 4.7 -> MCP -> DAB -> usp_GenerateMitigation).
                                  ~2 minutes. Dirties the demo state.
        6. Reset-ForBeat2.ps1   - re-runs the reset so the on-stage state is
                                  clean again after the dry run.

    Every step's stdout streams through. On failure the script stops, prints
    which step failed, and lists the remaining steps as SKIPPED. Exit 0 means
    every requested step succeeded.

.PARAMETER ContainerName
    SQL container name. Default: azsql-zavalivesite.

.PARAMETER SqlPort
    Host port for SQL. Default: 14330.

.PARAMETER SaPassword
    SA password. Default: Password1.

.PARAMETER SkipVerify
    Skip step 1 (Verify-Build.ps1). Use only when you just ran it.

.PARAMETER SkipReset
    Skip step 2 (Reset-ForBeat2.ps1). Use only mid-rehearsal when you
    *want* to keep the dirty state.

.PARAMETER SkipWarmup
    Skip step 3 (Warmup-Ai.ps1). Use only when models are known hot.

.PARAMETER SkipStart
    Skip step 4 (Start-LiveSite.ps1). Use when AppHost is already running.

.PARAMETER DryRun
    Run Test-AgentPath.ps1 then re-reset. Adds ~2 minutes. Recommended once
    before doors open; do not run after.

.EXAMPLE
    .\Prep-Demo.ps1
    Standard pre-show sequence.

.EXAMPLE
    .\Prep-Demo.ps1 -DryRun
    Pre-show sequence + full Beat-4 dry run + re-reset.

.EXAMPLE
    .\Prep-Demo.ps1 -SkipVerify -SkipWarmup
    Mid-rehearsal: skip the slow probes, just reset state and (re)start the site.
#>
[CmdletBinding()]
param(
    [string]$ContainerName = 'azsql-zavalivesite',
    [int]   $SqlPort       = 14330,
    [string]$SaPassword    = 'Password1',
    [switch]$SkipVerify,
    [switch]$SkipReset,
    [switch]$SkipWarmup,
    [switch]$SkipStart,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Write-Step  { param($n,$m) Write-Host "`n=== Step $n - $m ===" -ForegroundColor Cyan }
function Write-Ok    { param($m)   Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Skip  { param($m)   Write-Host "  [SKIP] $m" -ForegroundColor DarkYellow }
function Write-Fail2 { param($m)   Write-Host "  [FAIL] $m" -ForegroundColor Red }

# Step descriptor: { Num, Name, Skip, Action (scriptblock) }
# Action MUST throw on failure (or rely on $ErrorActionPreference='Stop' +
# a non-zero $LASTEXITCODE check).
$steps = @(
    @{
        Num    = 1
        Name   = 'Verify-Build.ps1'
        Skip   = $SkipVerify.IsPresent
        Action = {
            & "$PSScriptRoot\Verify-Build.ps1" -ContainerName $ContainerName -SqlPort $SqlPort -SaPassword $SaPassword
            if ($LASTEXITCODE -ne 0) { throw "Verify-Build.ps1 exited $LASTEXITCODE" }
        }
    },
    @{
        Num    = 2
        Name   = 'Reset-ForBeat2.ps1'
        Skip   = $SkipReset.IsPresent
        Action = {
            & "$PSScriptRoot\Reset-ForBeat2.ps1"
            if ($LASTEXITCODE -ne 0) { throw "Reset-ForBeat2.ps1 exited $LASTEXITCODE" }
        }
    },
    @{
        Num    = 3
        Name   = 'Warmup-Ai.ps1'
        Skip   = $SkipWarmup.IsPresent
        Action = {
            & "$PSScriptRoot\Warmup-Ai.ps1" -ContainerName $ContainerName
            if ($LASTEXITCODE -ne 0) { throw "Warmup-Ai.ps1 exited $LASTEXITCODE" }
        }
    },
    @{
        Num    = 4
        Name   = 'Start-LiveSite.ps1'
        Skip   = $SkipStart.IsPresent
        Action = {
            & "$PSScriptRoot\Start-LiveSite.ps1"
            if ($LASTEXITCODE -ne 0) { throw "Start-LiveSite.ps1 exited $LASTEXITCODE" }
        }
    }
)

if ($DryRun) {
    $steps += @{
        Num    = 5
        Name   = 'Test-AgentPath.ps1 (dry run)'
        Skip   = $false
        Action = {
            & "$PSScriptRoot\Test-AgentPath.ps1"
            if ($LASTEXITCODE -ne 0) { throw "Test-AgentPath.ps1 exited $LASTEXITCODE" }
        }
    }
    $steps += @{
        Num    = 6
        Name   = 'Reset-ForBeat2.ps1 (post-dryrun cleanup)'
        Skip   = $false
        Action = {
            & "$PSScriptRoot\Reset-ForBeat2.ps1"
            if ($LASTEXITCODE -ne 0) { throw "Reset-ForBeat2.ps1 (cleanup) exited $LASTEXITCODE" }
        }
    }
}

Write-Host "=== Prep-Demo.ps1 ===" -ForegroundColor Cyan
Write-Host "Container: $ContainerName  Port: $SqlPort  DryRun: $($DryRun.IsPresent)" -ForegroundColor DarkGray

$results  = @()
$failedAt = $null
$sw       = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($s in $steps) {
    if ($failedAt) {
        Write-Step $s.Num $s.Name
        Write-Skip "step $($s.Num) skipped because step $failedAt failed"
        $results += [pscustomobject]@{ Step=$s.Num; Name=$s.Name; Status='SKIPPED'; Seconds=0 }
        continue
    }
    if ($s.Skip) {
        Write-Step $s.Num $s.Name
        Write-Skip "skipped (-Skip flag)"
        $results += [pscustomobject]@{ Step=$s.Num; Name=$s.Name; Status='SKIPPED'; Seconds=0 }
        continue
    }

    Write-Step $s.Num $s.Name
    $stepSw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $s.Action
        $stepSw.Stop()
        Write-Ok ("step $($s.Num) succeeded in $([int]$stepSw.Elapsed.TotalSeconds)s")
        $results += [pscustomobject]@{ Step=$s.Num; Name=$s.Name; Status='OK'; Seconds=[int]$stepSw.Elapsed.TotalSeconds }
    }
    catch {
        $stepSw.Stop()
        Write-Fail2 $_.Exception.Message
        $results += [pscustomobject]@{ Step=$s.Num; Name=$s.Name; Status='FAILED'; Seconds=[int]$stepSw.Elapsed.TotalSeconds }
        $failedAt = $s.Num
    }
}

$sw.Stop()
Write-Host "`n=== Summary ($([int]$sw.Elapsed.TotalSeconds)s total) ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-Host

if ($failedAt) {
    Write-Host "Prep-Demo.ps1 FAILED at step $failedAt." -ForegroundColor Red
    Write-Host "Fix it, then re-run. Use -Skip* to skip already-good steps if you want." -ForegroundColor Yellow
    exit 1
}

Write-Host "Prep-Demo.ps1 succeeded. You're ready to walk on stage." -ForegroundColor Green
Write-Host "  Browser: http://localhost:8080/?dab=local" -ForegroundColor DarkGray
Write-Host "  Stop:    .\Stop-LiveSite.ps1" -ForegroundColor DarkGray
exit 0
