# Teardown-LiveSite.ps1
# Full teardown of the BRK223 local stack so the environment can be
# re-created from scratch in a different workspace.
#
# Removes (in order):
#   1. Aspire AppHost dotnet process (apphost.cs)
#   2. DCP-managed dab-* containers
#   3. The azsql-zavalivesite SQL container (Caddy + Ollama run inside it,
#      so they go with it)
#
# Optional:
#   -RemoveImage     also `docker rmi` the SQL image
#   -PruneVolumes    also `docker volume prune -f` (no demo data lives in
#                    volumes today, but harmless if you want a clean slate)

[CmdletBinding()]
param(
    [string]$ContainerName = 'azsql-zavalivesite',
    [switch]$RemoveImage,
    [switch]$PruneVolumes
)

$ErrorActionPreference = 'Continue'

# 1. Kill AppHost (best effort) + dab-* containers via Stop-LiveSite
$stopScript = Join-Path $PSScriptRoot 'Stop-LiveSite.ps1'
if (Test-Path $stopScript) {
    Write-Host "[Teardown] Running Stop-LiveSite.ps1" -ForegroundColor Cyan
    & $stopScript
}
else {
    Write-Host "[Teardown] Stop-LiveSite.ps1 not found, killing AppHost inline" -ForegroundColor Yellow
    $apphost = Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" |
        Where-Object { $_.CommandLine -match 'apphost\.cs' }
    foreach ($p in $apphost) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    docker ps -a --filter 'name=^dab-' --format '{{.Names}}' | ForEach-Object {
        docker rm -f $_ | Out-Null
    }
}

# 2. Capture the SQL container image *before* removing the container, in
#    case -RemoveImage is set.
$image = $null
if ($RemoveImage) {
    $image = docker inspect --format '{{.Config.Image}}' $ContainerName 2>$null
}

# 3. Remove the SQL container (Ollama + Caddy live inside it)
$existing = docker ps -a --filter "name=^/$ContainerName$" --format '{{.ID}}'
if ($existing) {
    Write-Host "[Teardown] Removing container '$ContainerName' ($existing)" -ForegroundColor Yellow
    docker rm -f $ContainerName | Out-Null
}
else {
    Write-Host "[Teardown] No container named '$ContainerName' to remove" -ForegroundColor DarkGray
}

# 4. Optional: remove the SQL image
if ($RemoveImage -and $image) {
    Write-Host "[Teardown] Removing image '$image'" -ForegroundColor Yellow
    docker rmi $image 2>$null | Out-Null
}

# 5. Optional: prune dangling volumes
if ($PruneVolumes) {
    Write-Host "[Teardown] Pruning unused docker volumes" -ForegroundColor Yellow
    docker volume prune -f | Out-Null
}

Write-Host "`n[Teardown] Done. Remaining BRK223-related docker resources:" -ForegroundColor Green
$leftovers = docker ps -a --format 'table {{.Names}}\t{{.Status}}' |
    Where-Object { $_ -match 'NAMES|azsql-zavalivesite|^dab-' }
if ($leftovers.Count -gt 1) { $leftovers | ForEach-Object { Write-Host "  $_" } }
else { Write-Host "  (none)" -ForegroundColor DarkGray }
