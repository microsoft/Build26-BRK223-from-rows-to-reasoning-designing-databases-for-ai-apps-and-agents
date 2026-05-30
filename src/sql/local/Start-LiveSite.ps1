# Start-LiveSite.ps1
# Launches the BRK223 "live-site support" Aspire AppHost.
#
# Resources started:
#   - dab : Data API Builder container (REST /api + MCP /mcp)
#   - web : ZavaLiveSite.Web Blazor WebAssembly app (the on-stage UI)
#
# The Aspire dashboard is intentionally disabled (DisableDashboard = true
# in apphost.cs). We launch via `dotnet run` because the `aspire` CLI
# requires a dashboard URL and exits when it's disabled.
#
# Pre-req: azsql-zavalivesite SQL container must be running on host port 14330.
#          Use Start-AzureSqlContainer.ps1 if it isn't.

[CmdletBinding()]
param(
    [switch]$Foreground,
    [switch]$NoClean,
    [string]$PasswordFile = $env:BRK223_PASSWORD_FILE
)

$ErrorActionPreference = 'Stop'

if (-not $env:BRK223_SQL_CONNECTION_STRING) {
    if (-not $env:BRK223_SQLADMIN_PASSWORD -and $PasswordFile -and (Test-Path -LiteralPath $PasswordFile)) {
        $lines = Get-Content -LiteralPath $PasswordFile
        $idx = [Array]::IndexOf($lines, 'sqladmin / SA password:')
        if ($idx -ge 0 -and ($idx + 1) -lt $lines.Count) {
            $candidate = ([string]$lines[$idx + 1]).Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $env:BRK223_SQLADMIN_PASSWORD = $candidate
                Write-Host "[Start-LiveSite] Loaded BRK223_SQLADMIN_PASSWORD from $PasswordFile" -ForegroundColor DarkGray
            }
        }
    }

    if (-not $env:BRK223_SQLADMIN_PASSWORD) {
        throw 'BRK223_SQL_CONNECTION_STRING is not set and BRK223_SQLADMIN_PASSWORD is missing. Set one of them before launching AppHost.'
    }

    $env:BRK223_SQL_CONNECTION_STRING = "Server=host.docker.internal,14330;Database=zavalivesitedb;User Id=sqladmin;Password=$env:BRK223_SQLADMIN_PASSWORD;TrustServerCertificate=True;Encrypt=True;Command Timeout=180"
}

$apphostDir = Join-Path $PSScriptRoot 'dotnet\AppHost'
if (-not (Test-Path (Join-Path $apphostDir 'apphost.cs'))) {
    throw "apphost.cs not found at $apphostDir"
}

# Verify the SQL container is up before we start DAB (DAB will retry but
# fail-fast here gives a clearer error on stage).
$sql = docker ps --filter 'name=^/azsql-zavalivesite$' --format '{{.Status}}'
if (-not $sql) {
    throw "azsql-zavalivesite container is not running. Run .\Start-AzureSqlContainer.ps1 first."
}
Write-Host "[Start-LiveSite] azsql-zavalivesite: $sql" -ForegroundColor Green

if (-not $NoClean) {
    Write-Host "[Start-LiveSite] Cleaning prior AppHost/DAB runtime..." -ForegroundColor DarkGray
    & (Join-Path $PSScriptRoot 'Stop-LiveSite.ps1') | Out-Null
}

Push-Location $apphostDir
try {
    if ($Foreground) {
        Write-Host "[Start-LiveSite] Launching AppHost in foreground (Ctrl+C to stop)..." -ForegroundColor Cyan
        dotnet run apphost.cs
    }
    else {
        $outLog = Join-Path $apphostDir 'apphost.out.log'
        $errLog = Join-Path $apphostDir 'apphost.err.log'
        Remove-Item $outLog, $errLog -ErrorAction SilentlyContinue

        $proc = Start-Process -FilePath 'dotnet' `
            -ArgumentList 'run', 'apphost.cs' `
            -RedirectStandardOutput $outLog `
            -RedirectStandardError  $errLog `
            -PassThru -WindowStyle Hidden

        Write-Host "[Start-LiveSite] AppHost PID: $($proc.Id)" -ForegroundColor Green
        Write-Host "[Start-LiveSite] Logs: $outLog" -ForegroundColor DarkGray
        Write-Host "[Start-LiveSite] Stop with: .\Stop-LiveSite.ps1" -ForegroundColor DarkGray

        # Wait briefly and surface DAB + Web endpoints
        Start-Sleep -Seconds 25
        Write-Host "`n[Start-LiveSite] Containers:" -ForegroundColor Cyan
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' |
            Where-Object { $_ -match 'dab-|azsql-zavalivesite|NAMES' }
    }
}
finally {
    Pop-Location
}
