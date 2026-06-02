<#
.SYNOPSIS
    Post-reboot resume for the BRK223 live-site demo. Non-destructive.

.DESCRIPTION
    After a host reboot, the SQL container is stopped but the database,
    corpus, indexes, EXTERNAL MODEL, and Ollama models inside the container
    are all intact. This script brings the stack back online without
    rebuilding or removing anything:

      1. docker start azsql-zavalivesite (if not already running)
      2. Wait for SQL to accept connections on localhost,14330
      3. Verify-Build.ps1         (health checks; starts Ollama+Caddy if down)
      4. Warmup-Ai.ps1            (re-warm phi4 + mxbai-embed-large)
      5. Reset-ForBeat2.ps1       (rewind incident 5012 + drop Beat-2c index)
      6. Start-LiveSite.ps1       (AppHost + DAB + Web)

    Does NOT run Build.ps1 or deploy-prestage.ps1 — nothing is dropped or
    re-seeded. Safe to run repeatedly.

.PARAMETER SkipReset
    Skip Reset-ForBeat2 (keep current incident state).

.PARAMETER SkipStart
    Skip Start-LiveSite.

.EXAMPLE
    .\Resume-AfterReboot.ps1
#>
[CmdletBinding()]
param(
    [string]$ContainerName = 'azsql-zavalivesite',
    [int]$SqlPort = 14330,
    [switch]$SkipReset,
    [switch]$SkipStart,
    [string]$PasswordFile = $env:BRK223_PASSWORD_FILE
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Optional convenience: load passwords from a local file if env vars aren't set.
# Public repo users should set BRK223_SA_PASSWORD / BRK223_SQLADMIN_PASSWORD directly.
if ((-not $env:BRK223_SA_PASSWORD -or -not $env:BRK223_SQLADMIN_PASSWORD) -and
    $PasswordFile -and (Test-Path -LiteralPath $PasswordFile)) {
    $lines = Get-Content -LiteralPath $PasswordFile
    $idx = [Array]::IndexOf($lines, 'sqladmin / SA password:')
    if ($idx -ge 0 -and ($idx + 1) -lt $lines.Count) {
        $candidate = ([string]$lines[$idx + 1]).Trim()
        if ($candidate) {
            if (-not $env:BRK223_SA_PASSWORD)       { $env:BRK223_SA_PASSWORD = $candidate }
            if (-not $env:BRK223_SQLADMIN_PASSWORD) { $env:BRK223_SQLADMIN_PASSWORD = $candidate }
            Write-Host "[Resume] Loaded passwords from $PasswordFile" -ForegroundColor DarkGray
        }
    }
}

if (-not $env:BRK223_SA_PASSWORD)      { throw 'BRK223_SA_PASSWORD not set.' }
if (-not $env:BRK223_SQLADMIN_PASSWORD) { throw 'BRK223_SQLADMIN_PASSWORD not set.' }

function Write-Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Assert-DockerReady {
    param([int]$TimeoutSeconds = 180)

    docker info *>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker engine: ready" -ForegroundColor Green
        return
    }

    # Try to launch Docker Desktop.
    $dd = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    if (-not $dd) {
        throw "Docker engine not responding and Docker Desktop.exe not found. Start Docker manually and re-run."
    }

    Write-Host "Docker engine not responding. Launching Docker Desktop..." -ForegroundColor Yellow
    Start-Process -FilePath $dd | Out-Null

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        docker info *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker engine: ready" -ForegroundColor Green
            return
        }
    }
    throw "Docker engine did not become ready within $TimeoutSeconds seconds."
}

# 0. Make sure Docker Desktop is running (typical after a reboot).
Write-Step "0/6 Docker engine"
Assert-DockerReady

# 1. Start the SQL container if it is not already running.
Write-Step "1/6 Start SQL container ($ContainerName)"
$status = docker ps --filter "name=^/$ContainerName$" --format '{{.Status}}'
if ($status) {
    Write-Host "Already running: $status" -ForegroundColor Green
} else {
    $exists = docker ps -a --filter "name=^/$ContainerName$" --format '{{.Names}}'
    if (-not $exists) {
        throw "Container '$ContainerName' does not exist. Run Prepare-DemoEnvironment.ps1 to provision it."
    }
    docker start $ContainerName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker start $ContainerName failed." }
    Write-Host "Started $ContainerName." -ForegroundColor Green
}

# 2. Wait for SQL to accept connections.
Write-Step "2/6 Wait for SQL on localhost,$SqlPort"
& (Join-Path $PSScriptRoot 'Test-AzureSqlConnection.ps1') -Port $SqlPort -SaPassword $env:BRK223_SA_PASSWORD -ContainerName $ContainerName

# 3. Verify build. Runs BEFORE Warmup so Restart-AiServices can bring
#    Ollama + Caddy up if they aren't running yet (otherwise Warmup hits
#    a closed port and silently no-ops).
Write-Step "3/6 Verify-Build"
& (Join-Path $PSScriptRoot 'Verify-Build.ps1')

# 4. Warmup AI models (Ollama + Caddy guaranteed running after step 3).
Write-Step "4/6 Warmup Ollama models"
& (Join-Path $PSScriptRoot 'Warmup-Ai.ps1') -ContainerName $ContainerName

# 5. Optional: rewind incident state.
if (-not $SkipReset) {
    Write-Step "5/6 Reset-ForBeat2 (rewind incident state)"
    & (Join-Path $PSScriptRoot 'Reset-ForBeat2.ps1') -Server "localhost,$SqlPort" -Password $env:BRK223_SQLADMIN_PASSWORD
} else {
    Write-Step "5/6 Reset-ForBeat2 (skipped)"
}

# 6. Start the live site.
if (-not $SkipStart) {
    Write-Step "6/6 Start-LiveSite"
    & (Join-Path $PSScriptRoot 'Start-LiveSite.ps1')
} else {
    Write-Step "6/6 Start-LiveSite (skipped)"
}

Write-Host ""
Write-Host "Resume complete." -ForegroundColor Green
