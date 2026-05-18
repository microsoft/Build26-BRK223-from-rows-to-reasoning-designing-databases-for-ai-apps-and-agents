<#
.SYNOPSIS
    Rewinds the BRK223 demo to "before Beat 1 ran". Use between rehearsals.

.DESCRIPTION
    Runs sqlscripts\_reset_for_beat2.sql against the Azure SQL container via sqlsim,
    which:
      - drops ix_archive_tags_errorCode (the JSON index from Beat 2c)
      - deletes dbo.Incident row #5012 (the row from Beat 1)
      - reports verification counts

    Does NOT touch the corpus, vector indexes, EXTERNAL MODEL, procs, or DB
    options. Safe to run repeatedly.

.PARAMETER Server
    Default: localhost,1434

.PARAMETER User
    Default: sqladmin

.PARAMETER Password
    Default: StrongPassw0rd

.EXAMPLE
    .\Reset-ForBeat2.ps1
#>
[CmdletBinding()]
param(
    [string]$Server   = 'localhost,14330',
    [string]$User     = 'sqladmin',
    [string]$Password = 'StrongPassw0rd'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$reset = Join-Path $PSScriptRoot 'sqlscripts\_reset_for_beat2.sql'
if (-not (Test-Path $reset)) { throw "Reset script not found: $reset" }

Write-Host "Resetting demo state on $Server/zavalivesitedb..." -ForegroundColor Cyan
# Invoke-SqlsimScript prepends the standard SET preamble so JSON-index DDL stays valid.
Invoke-SqlsimScript -Path $reset -Server $Server -User $User -Password $Password `
                    -Database zavalivesitedb -QueryTimeoutSeconds 60

Write-Host ""
Write-Host "Reset complete. You can now run Beat 1 (05_create_incident.sql)." -ForegroundColor Green
