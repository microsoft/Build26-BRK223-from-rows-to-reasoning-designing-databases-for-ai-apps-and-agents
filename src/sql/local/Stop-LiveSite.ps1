# Stop-LiveSite.ps1
# Stops the BRK223 Aspire AppHost (started via Start-LiveSite.ps1) and
# any DCP-managed dab-* containers it spawned.
#
# Leaves azsql-zavalivesite running so demo data is preserved between sessions.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# 1. Kill any dotnet process running apphost.cs
$apphost = Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" |
    Where-Object { $_.CommandLine -match 'apphost\.cs' }

if ($apphost) {
    foreach ($p in $apphost) {
        Write-Host "[Stop-LiveSite] Stopping AppHost PID $($p.ProcessId)" -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host "[Stop-LiveSite] No AppHost process found" -ForegroundColor DarkGray
}

Start-Sleep -Seconds 3

# 2. Aspire DCP names DAB containers `dab-<random>`. Stop and remove them.
$dabs = docker ps -a --filter 'name=^dab-' --format '{{.Names}}'
if ($dabs) {
    foreach ($name in $dabs) {
        Write-Host "[Stop-LiveSite] Removing $name" -ForegroundColor Yellow
        docker rm -f $name | Out-Null
    }
}

Write-Host "[Stop-LiveSite] Done. azsql-zavalivesite left running." -ForegroundColor Green
docker ps --format 'table {{.Names}}\t{{.Status}}' | Where-Object { $_ -match 'azsql-zavalivesite|NAMES' }
