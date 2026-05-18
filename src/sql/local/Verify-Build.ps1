<#
.SYNOPSIS
    One-shot startup check for the BRK223 demo stack. Verifies (and where
    safe, starts) every background dependency. Run this any time the
    laptop has been rebooted or the demo has been idle.

.DESCRIPTION
    Idempotent. Checks the things that have to be running BEFORE the
    demo / before agent-path testing:

      1. Docker Desktop engine          (auto-start if installed)
      2. azsql-zavalivesite container         (auto `docker start` if stopped)
      3. SQL on localhost,14330         (sqlsim SELECT 1)
      4. Ollama + Caddy inside container (restarts via Restart-AiServices.ps1
                                          if either is missing)
      5. Endpoints :8444 (embeddings) + :8445 (chat) reachable from host
      6. Node + npm                     (info only)
      7. Copilot CLI                    (info only)
      8. Aspire AppHost on :8765        (info only — does NOT auto-start;
                                          run .\Start-LiveSite.ps1 manually)

    Exits non-zero if any REQUIRED check fails (1-5).

.PARAMETER ContainerName
    Default: azsql-zavalivesite.

.PARAMETER SqlPort
    Host port for SQL. Default: 14330.

.PARAMETER SaPassword
    SA password. Default: Password1.

.PARAMETER SkipAi
    Skip ollama/caddy checks (steps 4 + 5). Use when you only need SQL.

.EXAMPLE
    .\Verify-Build.ps1
#>
[CmdletBinding()]
param(
    [string]$ContainerName = 'azsql-zavalivesite',
    [int]$SqlPort          = 14330,
    [string]$SaPassword    = 'Password1',
    [switch]$SkipAi
)

$ErrorActionPreference = 'Stop'
$script:Failed = @()

. (Join-Path $PSScriptRoot 'Common.ps1')

function Write-Step  { param($m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info  { param($m) Write-Host "  [INFO] $m" -ForegroundColor Cyan }
function Write-Fail  { param($m) Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failed += $m }

# Refresh PATH from registry so freshly-installed CLIs (node, copilot) are visible.
$Env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')

# --- 1. Docker engine ---------------------------------------------------------
Write-Step '1. Docker engine'
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    $candidate = "$Env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
    if (Test-Path $candidate) { $Env:Path = (Split-Path $candidate) + ';' + $Env:Path }
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
}
if (-not $dockerCmd) { Write-Fail 'docker not in PATH (install Docker Desktop)'; }
else {
    docker info *>$null
    if ($LASTEXITCODE -ne 0) {
        $desktop = "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $desktop) {
            Write-Warn2 'Docker daemon not running — launching Docker Desktop...'
            Start-Process -FilePath $desktop | Out-Null
            $deadline = (Get-Date).AddMinutes(3)
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 3
                docker info *>$null
                if ($LASTEXITCODE -eq 0) { break }
            }
        }
        docker info *>$null
        if ($LASTEXITCODE -ne 0) { Write-Fail 'Docker daemon did not come up within 3 minutes' }
        else { Write-Ok 'Docker engine ready (auto-started)' }
    } else {
        Write-Ok ("Docker engine ready ({0})" -f (docker --version))
    }
}

# Bail early if docker is not usable — the rest depends on it.
if ($script:Failed.Count -gt 0) {
    Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red
    exit 1
}

# --- 2. azsql-zavalivesite container ------------------------------------------------
Write-Step "2. Container '$ContainerName'"
$exists = docker ps -a --filter "name=^/$ContainerName$" --format '{{.ID}}'
if (-not $exists) {
    Write-Fail "Container '$ContainerName' does not exist. Run .\Start-AzureSqlContainer.ps1 -Port $SqlPort"
} else {
    $running = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
    if ($running -ne 'true') {
        Write-Warn2 "Container exists but is stopped — running 'docker start'..."
        docker start $ContainerName | Out-Null
        Start-Sleep -Seconds 3
        $running = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
    }
    if ($running -eq 'true') {
        $status = docker inspect -f '{{.State.Status}} (started {{.State.StartedAt}})' $ContainerName
        Write-Ok "Container running — $status"
    } else {
        Write-Fail "Could not start container '$ContainerName'"
    }
}

if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 3. SQL on localhost,14330 ------------------------------------------------
Write-Step "3. SQL on localhost,$SqlPort"
try {
    $sqlsimPath = Get-Sqlsim
} catch {
    Write-Fail $_.Exception.Message
    $sqlsimPath = $null
}
if ($sqlsimPath) {
    $server   = "localhost,$SqlPort"
    $deadline = (Get-Date).AddSeconds(60)
    $ready    = $false
    $lastErr  = $null
    while ((Get-Date) -lt $deadline) {
        $out = Invoke-SqlsimQuery -Query 'SELECT 1' -Server $server -User sa -Password $SaPassword -Quiet 2>&1
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        $lastErr = $out
        Start-Sleep -Seconds 2
    }
    if ($ready) { Write-Ok "SQL responding on $server" }
    else        { Write-Fail "SQL did not respond on $server within 60s. Last error: $lastErr" }
}

# --- 4 + 5. Ollama + Caddy inside container ----------------------------------
if ($SkipAi) {
    Write-Step '4-5. AI services — SKIPPED (-SkipAi)'
} else {
    Write-Step "4. Ollama + Caddy inside '$ContainerName'"
    $ollamaPid = (docker exec -u root $ContainerName pgrep -f 'ollama serve' 2>$null) -join ''
    $caddyPid  = (docker exec -u root $ContainerName pgrep -f 'caddy run'    2>$null) -join ''
    $needsRestart = (-not $ollamaPid) -or (-not $caddyPid)
    if ($needsRestart) {
        Write-Warn2 ("Ollama running: {0} | Caddy running: {1}" -f [bool]$ollamaPid, [bool]$caddyPid)
        Write-Warn2 'Calling Restart-AiServices.ps1...'
        $restart = Join-Path $PSScriptRoot 'Restart-AiServices.ps1'
        if (Test-Path $restart) {
            & $restart -ContainerName $ContainerName
            if ($LASTEXITCODE -ne 0) { Write-Fail "Restart-AiServices.ps1 exited $LASTEXITCODE" }
            else { Write-Ok 'AI services restarted' }
        } else {
            Write-Fail "Missing $restart"
        }
    } else {
        Write-Ok "Ollama PID $ollamaPid, Caddy PID $caddyPid"
    }

    Write-Step '5. Caddy endpoint reachable from inside container'
    # Caddy 8444 is NOT published to the host — SQL inside the container talks
    # to it via localhost. BRK223 uses a single Caddy listener on 8444 for
    # BOTH /v1/embeddings and /v1/chat/completions (Ollama on :11434 behind it).
    $code = docker exec -u root $ContainerName sh -c "curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://localhost:8444/v1/models" 2>$null
    if ($code -match '^(200|404|405)$') { Write-Ok "Caddy :8444 in-container HTTP $code" }
    else { Write-Fail "Caddy :8444 in-container probe returned '$code'" }
}

# --- 6. Node / npm (informational) -------------------------------------------
Write-Step '6. Node + npm (informational)'
$node = Get-Command node -ErrorAction SilentlyContinue
$npm  = Get-Command npm  -ErrorAction SilentlyContinue
if ($node) { Write-Ok ("node {0}" -f (& node --version)) } else { Write-Warn2 'node not on PATH' }
if ($npm)  { Write-Ok ("npm  {0}" -f (& npm  --version)) } else { Write-Warn2 'npm not on PATH' }

# --- 7. Copilot CLI (informational) ------------------------------------------
Write-Step '7. GitHub Copilot CLI (informational)'
$copilotPath = "$Env:APPDATA\npm\copilot.cmd"
if (Test-Path $copilotPath) {
    $ver = (& $copilotPath --version 2>&1 | Select-String -Pattern 'GitHub Copilot CLI' | Select-Object -First 1)
    if ($ver) { Write-Ok $ver.ToString().Trim() } else { Write-Warn2 'copilot installed but --version produced no match' }
} else {
    Write-Warn2 "Copilot CLI not at $copilotPath (npm i -g @github/copilot)"
}

# --- 8. Aspire AppHost on :8765 (informational) ------------------------------
Write-Step '8. Aspire AppHost / DAB on :8765 (informational)'
try {
    $r = Invoke-WebRequest -Uri 'http://localhost:8765/api' -TimeoutSec 3 -ErrorAction Stop
    Write-Ok ("DAB responding on :8765 ({0})" -f $r.StatusCode)
} catch {
    Write-Info 'AppHost / DAB not running on :8765 — run .\Start-LiveSite.ps1 when ready'
}

# --- Summary ------------------------------------------------------------------
Write-Host ''
if ($script:Failed.Count -eq 0) {
    Write-Host '=== All required prereqs OK ===' -ForegroundColor Green
    exit 0
} else {
    Write-Host '=== Prereq failures ===' -ForegroundColor Red
    $script:Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
