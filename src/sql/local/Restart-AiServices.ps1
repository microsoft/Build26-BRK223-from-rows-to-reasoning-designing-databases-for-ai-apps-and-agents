<#
.SYNOPSIS
    Restarts Ollama + Caddy inside the BRK223 Azure SQL container.

.DESCRIPTION
    Lightweight counterpart to Prepare-AiContainer.ps1. Re-copies only
    03-start-services.sh into the container, kills the running ollama
    process (if any), and re-runs the start script. Use this after
    editing 03-start-services.sh (e.g. to pick up OLLAMA_KEEP_ALIVE
    changes) without re-installing Ollama, re-pulling models, or
    re-trusting the Caddy CA.

    Idempotent. Safe to re-run.

.PARAMETER ContainerName
    Default: azsql-zavalivesite

.PARAMETER SkillFolder
    Folder containing 03-start-services.sh. Default: c:\bwsql\ollama\container.

.EXAMPLE
    .\Restart-AiServices.ps1
#>
[CmdletBinding()]
param(
    [string]$ContainerName = 'azsql-zavalivesite',
    [string]$SkillFolder   = 'c:\bwsql\ollama\container'
)

$ErrorActionPreference = 'Stop'

function Get-Docker {
    $cmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$Env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${Env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe"
    )
    $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $found) { throw "Docker not found. Is Docker Desktop running?" }
    return $found
}

$docker = Get-Docker

# Verify container is running.
$state = & $docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
if ($LASTEXITCODE -ne 0 -or $state -ne 'true') {
    throw "Container '$ContainerName' is not running. Run .\Start-AzureSqlContainer.ps1 first."
}

$script = Join-Path $SkillFolder '03-start-services.sh'
if (-not (Test-Path $script)) { throw "Missing: $script" }

Write-Host "=== Step 1: copy 03-start-services.sh into container ===" -ForegroundColor Cyan
& $docker exec -u root $ContainerName mkdir -p /tmp/ai-prereq | Out-Null
& $docker cp $script "${ContainerName}:/tmp/ai-prereq/03-start-services.sh" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "docker cp failed." }
# docker cp on Windows can introduce CRLF line endings, which dash/sh chokes
# on (e.g. 'set -e\r' becomes 'set: -l: invalid option'). Strip CRs in-place
# so the script is repeatable regardless of how the file got copied in.
& $docker exec -u root $ContainerName sed -i 's/\r$//' /tmp/ai-prereq/03-start-services.sh | Out-Null
if ($LASTEXITCODE -ne 0) { throw "sed CR-strip failed." }

Write-Host ""
Write-Host "=== Step 2: stop existing ollama + caddy ===" -ForegroundColor Cyan
& $docker exec -u root $ContainerName chmod +x /tmp/ai-prereq/03-start-services.sh | Out-Null
# pkill returns 1 when no match; ignore exit code from these on purpose.
& $docker exec -u root $ContainerName pkill -f 'ollama serve' 2>$null
& $docker exec -u root $ContainerName pkill -f 'caddy run'    2>$null
Start-Sleep -Seconds 2
$global:LASTEXITCODE = 0
Write-Host "  stopped (or were not running)"

Write-Host ""
Write-Host "=== Step 3: start ollama + caddy ===" -ForegroundColor Cyan
& $docker exec -u root $ContainerName sh /tmp/ai-prereq/03-start-services.sh
if ($LASTEXITCODE -ne 0) { throw "Start step failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "=== Step 4: verify OLLAMA_KEEP_ALIVE ===" -ForegroundColor Cyan
$envOut = & $docker exec -u root $ContainerName sh -c "pid=`$(pgrep -f 'ollama serve' | head -1); if [ -n `"`$pid`" ]; then tr '\0' '\n' < /proc/`$pid/environ | grep KEEP_ALIVE || echo 'KEEP_ALIVE not set'; else echo 'ollama not running'; fi"
Write-Host $envOut

Write-Host ""
Write-Host "Restart complete." -ForegroundColor Green
