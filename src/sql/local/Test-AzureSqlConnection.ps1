<#
.SYNOPSIS
    Tests connectivity to the SQL container and prints @@VERSION + edition details.

.DESCRIPTION
    Waits for SQL to accept connections on localhost,<Port> and runs SELECT @@VERSION.
    Independent of how the container was started.

.PARAMETER Port
    Host port to connect to. Default: 1433.

.PARAMETER SaPassword
    SA password. Default: Password1.

.PARAMETER TimeoutSeconds
    How long to wait for SQL to become ready. Default: 120.

.PARAMETER ContainerName
    Optional. If sqlsim never connects, the script will tail this container's logs.
    Default: azsql-zavalivesite.

.EXAMPLE
    .\Test-AzureSqlConnection.ps1
#>
[CmdletBinding()]
param(
    [int]$Port = 1433,
    [string]$SaPassword = 'Password1',
    [int]$TimeoutSeconds = 120,
    [string]$ContainerName = 'azsql-zavalivesite'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$sqlsim = Get-Sqlsim
Write-Host "sqlsim : $sqlsim"

$server = "localhost,$Port"
Write-Host "`n=== Waiting for SQL on $server (timeout ${TimeoutSeconds}s) ===" -ForegroundColor Cyan
$ready    = $false
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastErr  = $null
while ((Get-Date) -lt $deadline) {
    $out = Invoke-SqlsimQuery -Query 'SELECT 1' -Server $server -User sa -Password $SaPassword -Quiet 2>&1
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    $lastErr = $out
    Start-Sleep -Seconds 2
}
if (-not $ready) {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $exists = docker ps -a --filter "name=^/$ContainerName$" --format '{{.ID}}'
        if ($exists) {
            Write-Host "Container '$ContainerName' logs (tail):" -ForegroundColor Yellow
            docker logs --tail 80 $ContainerName | Out-Host
        }
    }
    throw "SQL did not become ready within ${TimeoutSeconds}s. Last sqlsim error:`n$lastErr"
}
Write-Host "SQL is online." -ForegroundColor Green

Write-Host "`n=== SELECT @@VERSION ===" -ForegroundColor Cyan
& $sqlsim -S $server -U sa -P $SaPassword -C -Q 'SET NOCOUNT ON; SELECT @@VERSION;'
if ($LASTEXITCODE -ne 0) { throw "Version query failed." }

Write-Host "`n=== Edition / build details ===" -ForegroundColor Cyan
& $sqlsim -S $server -U sa -P $SaPassword -C -Q @"
SET NOCOUNT ON;
SELECT
    SERVERPROPERTY('Edition')        AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel')   AS ProductLevel,
    SERVERPROPERTY('ProductBuild')   AS ProductBuild,
    SERVERPROPERTY('EngineEdition')  AS EngineEdition;
"@
