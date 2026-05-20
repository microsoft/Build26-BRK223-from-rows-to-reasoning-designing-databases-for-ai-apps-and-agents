<#
.SYNOPSIS
    Pre-stage deployment for BRK223 demo against the Azure SQL container.

.DESCRIPTION
    Runs the one-time sa bootstrap (creates sqladmin sysadmin login) and then
    deploys 00 -> 04 against localhost,1434 as sqladmin so the zavalivesitedb database
    is ready for the on-stage scripts (05 -> 08).

    Idempotent: 00_setup.sql drops + recreates zavalivesitedb each run; bootstrap is
    safe to re-run. Use -SkipBootstrap on subsequent runs to keep using the
    sqladmin login without touching sa.

.PARAMETER Server
    Server to connect to. Default: localhost,1434

.PARAMETER SaPassword
    Password for sa. Only used by the bootstrap step.
    Default: value of $env:BRK223_SA_PASSWORD. Required.

.PARAMETER SqlAdminPassword
    Password for sqladmin.
    Default: value of $env:BRK223_SQLADMIN_PASSWORD. Required.

.PARAMETER SkipBootstrap
    Skip the sa bootstrap step. Use after the very first deploy.

.PARAMETER IncludeOnStage
    Also run 05 -> 08 (the on-stage scripts). Default: false. The demo flow
    expects 05 -> 08 to be run live in VS Code, not pre-staged.

.EXAMPLE
    $env:BRK223_SA_PASSWORD = '<sa pwd>'
    $env:BRK223_SQLADMIN_PASSWORD = '<sqladmin pwd>'
    .\deploy-prestage.ps1
    # First run: bootstraps sqladmin, deploys 00 -> 04.

.EXAMPLE
    .\deploy-prestage.ps1 -SkipBootstrap
    # Subsequent runs: skips sa, redeploys 00 -> 04 as sqladmin.
#>
[CmdletBinding()]
param(
    [string]$Server = 'localhost,14330',
    [string]$SaPassword = $env:BRK223_SA_PASSWORD,
    [string]$SqlAdminPassword = $env:BRK223_SQLADMIN_PASSWORD,
    [switch]$SkipBootstrap,
    [switch]$IncludeOnStage
)

$ErrorActionPreference = 'Stop'

if (-not $SkipBootstrap -and [string]::IsNullOrEmpty($SaPassword)) {
    throw 'SaPassword required. Pass -SaPassword or set $env:BRK223_SA_PASSWORD.'
}
if ([string]::IsNullOrEmpty($SqlAdminPassword)) {
    throw 'SqlAdminPassword required. Pass -SqlAdminPassword or set $env:BRK223_SQLADMIN_PASSWORD.'
}

. (Join-Path $PSScriptRoot 'Common.ps1')

$sqlDir = Join-Path $PSScriptRoot 'sqlscripts'
if (-not (Test-Path $sqlDir)) {
    throw "SQL scripts directory not found: $sqlDir"
}

# Locate sqlsim via the standard resolver (PATH, $env:SQLSIM_PATH, repo dev path).
$sqlsim = Get-Sqlsim
Write-Host "Using sqlsim: $sqlsim" -ForegroundColor DarkGray

function Invoke-SqlScript {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [string]$Database = 'master'
    )
    if (-not (Test-Path $Path)) { throw "Script not found: $Path" }
    $name = Split-Path $Path -Leaf
    Write-Host ""
    Write-Host "=== [$User] $name ===" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Common.ps1::Invoke-SqlsimScript prepends the standard SET preamble so
    # JSON / filtered / indexed-view / computed-column indexes don't fail Msg 1934.
    $code = Invoke-SqlsimScript -Path $Path -Server $Server -User $User -Password $Password `
                                -Database $Database -LoginTimeoutSeconds 30 -PassThruExitCode
    $sw.Stop()

    if ($code -ne 0) {
        throw "FAILED: $name (exit $code) after $([int]$sw.Elapsed.TotalSeconds)s"
    }
    Write-Host "    OK ($([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Green
}

# --- Step 1: sa bootstrap (creates sqladmin) ---
if (-not $SkipBootstrap) {
    Write-Host "Step 1: sa bootstrap (one-time)" -ForegroundColor Yellow
    # _bootstrap_login.sql references $(SqlAdminPassword); pass via SqlcmdVariables
    # so the password is never written to disk as a literal.
    Invoke-SqlsimScript -Path (Join-Path $sqlDir '_bootstrap_login.sql') `
                        -Server $Server -User 'sa' -Password $SaPassword -Database 'master' `
                        -SqlcmdVariables @{ SqlAdminPassword = $SqlAdminPassword }
} else {
    Write-Host "Step 1: SKIPPED (-SkipBootstrap)" -ForegroundColor DarkYellow
}

# --- Step 2: pre-stage scripts as sqladmin ---
Write-Host ""
Write-Host "Step 2: deploying 00 -> 04 as sqladmin" -ForegroundColor Yellow

$prestage = @(
    '00_setup.sql',
    '01_schema.sql',
    '02_seed_corpus.sql',
    '02c_scale_corpus_multitenant.sql',   # clone to ~150k rows across 6 tenants + rebuild DiskANN
    '03_vector_indexes.sql',
    '03b_runbook_chunks.sql',             # chunk runbooks + embed + DiskANN on RunbookChunk
    '04a_proc_generate_mitigation.sql',
    '04b_diagnostic_procs.sql'
)

# 00_setup.sql runs against master (it CREATEs zavalivesitedb). The rest run against zavalivesitedb.
foreach ($script in $prestage) {
    $db = if ($script -eq '00_setup.sql') { 'master' } else { 'zavalivesitedb' }
    Invoke-SqlScript -Path (Join-Path $sqlDir $script) `
                     -User 'sqladmin' -Password $SqlAdminPassword -Database $db
}

# --- Step 3 (optional): on-stage scripts ---
if ($IncludeOnStage) {
    Write-Host ""
    Write-Host "Step 3: deploying 05 -> 07 as sqladmin (-IncludeOnStage)" -ForegroundColor Yellow
    $onstage = @(
        '05_create_incident.sql',
        '06_hybrid_search.sql',
        '07_log_timeline.sql'
    )
    foreach ($script in $onstage) {
        Invoke-SqlScript -Path (Join-Path $sqlDir $script) `
                         -User 'sqladmin' -Password $SqlAdminPassword -Database 'zavalivesitedb'
    }
}

Write-Host ""
Write-Host "Pre-stage deployment complete." -ForegroundColor Green
Write-Host "Connection going forward: $Server / sqladmin / <password from `$env:BRK223_SQLADMIN_PASSWORD> / TrustServerCertificate=Yes" -ForegroundColor Gray
