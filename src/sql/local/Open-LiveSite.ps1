# Open-LiveSite.ps1
# Opens the BRK223 ZavaLiveSite Blazor app in the default browser.
#
# The Web project is pinned to http://localhost:8080 in apphost.cs.
# If the AppHost isn't running, this just tells you to run Start-LiveSite.ps1.

[CmdletBinding()]
param(
    [string]$Url = 'http://localhost:8080',
    [int]$WaitSeconds = 20
)

$ErrorActionPreference = 'Stop'

Write-Host "[Open-LiveSite] Probing $Url ..." -ForegroundColor Cyan

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$ready = $false
do {
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) { $ready = $true; break }
    } catch { Start-Sleep -Milliseconds 500 }
} while ((Get-Date) -lt $deadline)

if (-not $ready) {
    Write-Host "[Open-LiveSite] $Url did not respond within $WaitSeconds s." -ForegroundColor Yellow
    Write-Host "  Is the AppHost running? If not: .\Start-LiveSite.ps1" -ForegroundColor Yellow
    Write-Host "  Opening anyway so you can refresh once it comes up." -ForegroundColor DarkGray
}
else {
    Write-Host "[Open-LiveSite] Ready (HTTP $($resp.StatusCode))." -ForegroundColor Green
}

Start-Process $Url
