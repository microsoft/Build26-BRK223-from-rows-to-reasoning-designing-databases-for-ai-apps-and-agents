<#
.SYNOPSIS
    Targeted cleanup + redeploy of the single mitigation proc.

.DESCRIPTION
    1. Drop legacy procs usp_GenerateMitigation_AoaiDirect /
       usp_GenerateMitigation_AoaiGateway and the legacy column
       dbo.Incident.ProposedMitigation_v2 (idempotent).
    2. Redeploy dbo.usp_GenerateMitigation from
       sqlscripts/04a_proc_generate_mitigation.sql (gateway-default).
    3. EXEC the proc against IncidentId 5012.
    4. Verify ProposedMitigation is populated.

    Does NOT touch schema, corpus, vector indexes, or external models.
    Use Prep-Cloud.ps1 for a full stand-up.
#>
[CmdletBinding()]
param(
    [string]$Server         = 'zavasqlserver-vzew2f.database.windows.net',
    [string]$Database       = 'zavalivesitedb',
    [string]$ApimHost       = 'zava-apim-vzew2f.azure-api.net',
    [string]$ChatDeployment = 'gpt-5-4-mini',
    [string]$AoaiApiVersion = '2024-10-21',
    [int]   $IncidentId     = 5012
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Get-Sqlsim {
    $candidates = @(
        $env:SQLSIM_PATH,
        'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe',
        (Join-Path $PSScriptRoot '..\local\utilities\sqlsim.exe')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path $c).Path } }
    $cmd = Get-Command sqlsim -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'sqlsim not found.'
}

function Invoke-Inline {
    param([string]$Body, [string]$Label, [int]$Timeout = 120)
    $tmp = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), '.sql')
    try {
        $preamble = "SET QUOTED_IDENTIFIER ON;`r`nSET ANSI_NULLS ON;`r`nSET ANSI_PADDING ON;`r`nSET ANSI_WARNINGS ON;`r`nSET ARITHABORT ON;`r`nSET CONCAT_NULL_YIELDS_NULL ON;`r`nSET NUMERIC_ROUNDABORT OFF;`r`nGO`r`n"
        Set-Content -LiteralPath $tmp -Value ($preamble + $Body) -Encoding UTF8 -NoNewline
        & $Script:Sqlsim -S $Server -d $Database -T $Script:Token -N m -l 30 -t $Timeout -stoponerror -i $tmp | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "$Label failed (exit $LASTEXITCODE)" }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

$Script:Sqlsim = Get-Sqlsim
Write-Host "[INFO] sqlsim: $Script:Sqlsim" -ForegroundColor Gray

$Script:Token = (& az account get-access-token --resource 'https://database.windows.net' --query accessToken -o tsv).Trim()
if (-not $Script:Token) { throw 'no token from az account get-access-token' }
Write-Host "[INFO] token length: $($Script:Token.Length)" -ForegroundColor Gray

# ----- Step 1 — cleanup ----------------------------------------------------
Write-Host "`n=== Step 1 — drop legacy procs + _v2 column ===" -ForegroundColor Cyan
$cleanup = @'
IF OBJECT_ID(N'dbo.usp_GenerateMitigation_AoaiDirect', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_GenerateMitigation_AoaiDirect;
    PRINT '>>> dropped usp_GenerateMitigation_AoaiDirect';
END
ELSE PRINT '>>> usp_GenerateMitigation_AoaiDirect not present';

IF OBJECT_ID(N'dbo.usp_GenerateMitigation_AoaiGateway', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_GenerateMitigation_AoaiGateway;
    PRINT '>>> dropped usp_GenerateMitigation_AoaiGateway';
END
ELSE PRINT '>>> usp_GenerateMitigation_AoaiGateway not present';

IF COL_LENGTH('dbo.Incident', 'ProposedMitigation_v2') IS NOT NULL
BEGIN
    ALTER TABLE dbo.Incident DROP COLUMN ProposedMitigation_v2;
    PRINT '>>> dropped column ProposedMitigation_v2';
END
ELSE PRINT '>>> ProposedMitigation_v2 not present';
GO
'@
Invoke-Inline -Body $cleanup -Label 'cleanup' -Timeout 60

# ----- Step 2 — redeploy proc ---------------------------------------------
Write-Host "`n=== Step 2 — redeploy dbo.usp_GenerateMitigation ===" -ForegroundColor Cyan
$procFile = Join-Path $PSScriptRoot 'sqlscripts\04a_proc_generate_mitigation.sql'
$raw = Get-Content -Raw -LiteralPath $procFile
$lines = $raw -split "(`r`n|`n)"
$kept  = $lines | Where-Object { $_ -notmatch '^\s*:(setvar|on\s+error)\b' }
$text  = -join $kept
$text  = $text.Replace('$(ApimHost)',       $ApimHost)
$text  = $text.Replace('$(ChatDeployment)', $ChatDeployment)
$text  = $text.Replace('$(AoaiApiVersion)', $AoaiApiVersion)
Invoke-Inline -Body $text -Label 'redeploy proc' -Timeout 120

# ----- Step 3 — exec proc -------------------------------------------------
Write-Host "`n=== Step 3 — EXEC usp_GenerateMitigation @IncidentId = $IncidentId ===" -ForegroundColor Cyan
Invoke-Inline -Body "EXEC dbo.usp_GenerateMitigation @IncidentId = $IncidentId;`r`nGO`r`n" -Label 'exec' -Timeout 240

# ----- Step 4 — verify ----------------------------------------------------
Write-Host "`n=== Step 4 — verify ProposedMitigation populated ===" -ForegroundColor Cyan
& $Script:Sqlsim -S $Server -d $Database -T $Script:Token -N m -l 30 -t 30 `
    -Q "SET NOCOUNT ON; SELECT IncidentId, summary = JSON_VALUE(ProposedMitigation,'$.summary'), len = LEN(CAST(ProposedMitigation AS nvarchar(max))) FROM dbo.Incident WHERE IncidentId = $IncidentId;" | Out-Host

Write-Host "`n[OK] Cleanup + redeploy complete." -ForegroundColor Green
