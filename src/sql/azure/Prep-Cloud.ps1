<#
.SYNOPSIS
    Idempotent end-to-end stand-up of the BRK223 Azure variant.

.DESCRIPTION
    Counterpart to local/Prep-Demo.ps1. Targets the Azure stack that Bicep
    deploys (Hyperscale + AOAI + APIM + Content Safety + role assignments).
    Run anytime before showtime; safe to re-run.

    Steps:
        1. Resolve deployment outputs from `az deployment group show
           --name zavalivesite-main -g <rg>` (sqlServerFqdn, aoaiEndpoint,
           apimGatewayUrl). With -ReDeploy, re-runs `az deployment group
           create` first.
        2. Add a SQL firewall rule for the current public IP (idempotent).
        3. Acquire an AAD access token (audience database.windows.net) and
           use it to drive sqlsim against the Hyperscale DB zavalivesitedb.
        4. Materialize Azure variants of the local SQL scripts on the fly:
             - 01_schema.sql       : OllamaMxbai -> AoaiTextEmbed3Small,
                                     vector(1024) -> vector(1536),
                                     CREATE EXTERNAL MODEL OllamaMxbai
                                     block stripped (the AOAI EXTERNAL MODEL
                                     is created in 03_external_model.sql).
             - 02_seed_corpus.sql  : same model + vector rewrites.
             - 03_vector_indexes.sql, 04b_diagnostic_procs.sql : reused
                                     verbatim.
             - 05_create_incident.sql : model rewrite.
           For Azure-side scripts (03_external_model, 04a_direct,
           04a_gateway) we substitute $(AoaiHost), $(ApimHost),
           $(ChatDeployment), $(EmbedDeployment), $(AoaiApiVersion) directly
           in PowerShell (sqlsim does not interpret :setvar / $(VAR)).
        5. Deploy in order against zavalivesitedb:
             0  inline ALTER DATABASE SCOPED CONFIGURATION PREVIEW_FEATURES ON
             1  materialized 01_schema
             2  azure 03_external_model        (DSCs + AoaiTextEmbed3Small)
             3  materialized 02_seed_corpus    (~300 archive + 20 runbook rows)
             4  local 03_vector_indexes        (DiskANN)
             5  local 04b_diagnostic_procs
             6  azure 04a_proc_generate_mitigation.sql  (usp_GenerateMitigation, gateway-default)
             7  materialized 05_create_incident (row 5012)
             8  EXEC usp_GenerateMitigation @IncidentId = 5012
             9  SELECT verify ProposedMitigation is populated.

    Auth model: SQL logical-server system MI + APIM system MI both have
    `Cognitive Services User` on AOAI. The proc body uses DATABASE SCOPED
    CREDENTIAL with IDENTITY='Managed Identity' so no keys are ever stored.
    Cloud is gateway-only: Hyperscale -> APIM -> AOAI.

    Hard rules:
      * Never wrap a single DML in BEGIN TRAN.
      * Never use `EXTERNAL MODEL` for chat completions (only EMBEDDINGS).
      * Never bypass the firewall by opening 0.0.0.0/0 here.

.PARAMETER ResourceGroup
    Target resource group. Default: zavalivesiterg.

.PARAMETER DeploymentName
    Bicep deployment name. Default: zavalivesite-main.

.PARAMETER DatabaseName
    Hyperscale database name. Default: zavalivesitedb.

.PARAMETER ChatDeployment
    AOAI chat-completions deployment name. Default: gpt-5-4-mini.

.PARAMETER EmbedDeployment
    AOAI embeddings deployment name. Default: text-embedding-3-small.

.PARAMETER AoaiApiVersion
    AOAI API version used in URLs. Default: 2024-10-21.

.PARAMETER ReDeploy
    Re-run `az deployment group create` before reading outputs. Default: off.

.PARAMETER SkipFirewall
    Don't add a firewall rule for the current public IP (use when on a VPN
    that already has connectivity or when running from an Azure VM).

.PARAMETER SkipDeploy
    Don't run any SQL scripts; just print the resolved outputs. Useful for
    capturing the values into other tooling.

.EXAMPLE
    .\Prep-Cloud.ps1
    Resolve outputs, add firewall rule, deploy schema/corpus, run the proc.

.EXAMPLE
    .\Prep-Cloud.ps1 -ReDeploy
    Re-run Bicep, then everything else.

.EXAMPLE
    .\Prep-Cloud.ps1 -SkipDeploy
    Just print the connection details (debug helper).
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup    = 'zavalivesiterg',
    [string]$DeploymentName   = 'zava-main',
    [string]$DatabaseName     = 'zavalivesitedb',
    [string]$ChatDeployment   = 'gpt-5-4-mini',
    [string]$EmbedDeployment  = 'text-embedding-3-small',
    [string]$AoaiApiVersion   = '2024-10-21',
    [switch]$ReDeploy,
    [switch]$SkipFirewall,
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
Set-Location $PSScriptRoot

function Write-Step { param($n, $m) Write-Host "`n=== Step $n - $m ===" -ForegroundColor Cyan }
function Write-Ok   { param($m)   Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Info { param($m)   Write-Host "  [INFO] $m" -ForegroundColor Gray }
function Write-Warn2{ param($m)   Write-Host "  [WARN] $m" -ForegroundColor Yellow }

# --- Get-Sqlsim (mirrors local/Common.ps1 resolution order) -----------------
function Get-Sqlsim {
    if ($env:SQLSIM_PATH -and (Test-Path -LiteralPath $env:SQLSIM_PATH)) {
        return $env:SQLSIM_PATH
    }
    $bundled = Join-Path $PSScriptRoot '..\local\utilities\sqlsim.exe'
    if (Test-Path -LiteralPath $bundled) { return (Resolve-Path $bundled).Path }
    $cmd = Get-Command sqlsim -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $devPath = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe'
    if (Test-Path -LiteralPath $devPath) { return $devPath }
    throw "sqlsim not found. Set `$env:SQLSIM_PATH or add sqlsim to PATH."
}

# Standard SET preamble — matches local/Common.ps1. sqlsim/sqlcmd default
# QUOTED_IDENTIFIER / ANSI_NULLS OFF; JSON / filtered indexes fail Msg 1934
# without these.
$Script:SqlPreamble = @'
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO
'@

# Run a SQL script against the Azure SQL database using sqlsim with an AAD
# access token. $Body is the *already-mutated* SQL text (string). Prepends
# the SET preamble. Throws on non-zero exit.
function Invoke-AzSqlScriptText {
    param(
        [Parameter(Mandatory)] [string]$Body,
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Database,
        [Parameter(Mandatory)] [string]$AccessToken,
        [string]$Label = 'inline',
        [int]$QueryTimeoutSeconds = 600
    )
    $sqlsim = Get-Sqlsim
    $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.sql')
    try {
        $full = $Script:SqlPreamble + "`r`n" + $Body
        Set-Content -LiteralPath $tmp -Value $full -Encoding UTF8 -NoNewline

        $sqlsimArgs = @(
            '-S', $Server,
            '-d', $Database,
            '-T', $AccessToken,
            '-N', 'm',
            '-l', 30,
            '-t', $QueryTimeoutSeconds,
            '-stoponerror',
            '-i', $tmp
        )
        & $sqlsim @sqlsimArgs | Out-Host
        $code = $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
    if ($code -ne 0) { throw "sqlsim exited $code for $Label" }
}

# Inline -Q one-shot. Returns raw stdout. Caller checks $LASTEXITCODE.
function Invoke-AzSqlQuery {
    param(
        [Parameter(Mandatory)] [string]$Query,
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Database,
        [Parameter(Mandatory)] [string]$AccessToken
    )
    $sqlsim = Get-Sqlsim
    & $sqlsim -S $Server -d $Database -T $AccessToken -N m -l 30 -Q $Query 2>&1
}

# Read a .sql file, strip sqlcmd-only directives sqlsim doesn't parse,
# substitute $(VAR) tokens with the provided hashtable.
function Resolve-SqlTemplate {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [hashtable]$Vars = @{}
    )
    if (-not (Test-Path -LiteralPath $Path)) { throw "Script not found: $Path" }
    $raw = Get-Content -Raw -LiteralPath $Path

    # Strip sqlcmd directives sqlsim doesn't understand.
    # ':setvar Name "value"' — drop the line.
    # ':on error exit'       — drop the line.
    $lines = $raw -split "(`r`n|`n)"
    $kept = $lines | Where-Object { $_ -notmatch '^\s*:(setvar|on\s+error)\b' }
    $text = -join $kept

    # Substitute $(VAR) tokens.
    foreach ($k in $Vars.Keys) {
        $text = $text.Replace("`$($k)", $Vars[$k])
    }
    return $text
}

# Materialize the local 01_schema.sql for Azure:
#   * Drop the CREATE EXTERNAL MODEL OllamaMxbai block (created separately
#     against AOAI in 03_external_model.sql).
#   * Rename OllamaMxbai -> AoaiTextEmbed3Small (USE MODEL references).
#   * Widen vector(1024) -> vector(1536).
function Get-AzureMutatedSchema {
    param([Parameter(Mandatory)] [string]$Path)

    $raw = Get-Content -Raw -LiteralPath $Path

    # Remove the IF EXISTS DROP EXTERNAL MODEL OllamaMxbai + CREATE EXTERNAL
    # MODEL OllamaMxbai block. It's bounded by:
    #   'IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N''OllamaMxbai'')'
    # through the next 'PRINT ''  EXTERNAL MODEL OllamaMxbai created' line + GO.
    # Use a non-greedy regex on a single multiline string.
    $pattern = "(?s)IF EXISTS \(SELECT 1 FROM sys\.external_models WHERE name = N'OllamaMxbai'\).*?EXTERNAL MODEL OllamaMxbai created.*?\r?\nGO\r?\n"
    $raw = [regex]::Replace($raw, $pattern, "-- (local OllamaMxbai EXTERNAL MODEL block stripped by Prep-Cloud.ps1; see 03_external_model.sql for the AOAI equivalent)`r`nGO`r`n")

    # Model + width rewrites.
    $raw = $raw -replace 'OllamaMxbai',  'AoaiTextEmbed3Small'
    $raw = $raw -replace 'vector\(1024\)', 'vector(1536)'

    # Azure SQL does not support USE to switch databases. Strip the local USE.
    $raw = $raw -replace '(?im)^\s*USE\s+zavalivesitedb\s*;\s*$', '-- USE zavalivesitedb stripped by Prep-Cloud.ps1 (Azure SQL connection already scoped).'

    return $raw
}

# Same model + width rewrites for the corpus / incident scripts.
function Get-AzureMutatedScript {
    param([Parameter(Mandatory)] [string]$Path)
    $raw = Get-Content -Raw -LiteralPath $Path
    $raw = $raw -replace 'OllamaMxbai',  'AoaiTextEmbed3Small'
    $raw = $raw -replace 'vector\(1024\)', 'vector(1536)'
    $raw = $raw -replace '(?im)^\s*USE\s+zavalivesitedb\s*;\s*$', '-- USE zavalivesitedb stripped by Prep-Cloud.ps1 (Azure SQL connection already scoped).'
    return $raw
}

#=============================================================================
# Step 1 — resolve / re-run Bicep
#=============================================================================
Write-Step 1 'Resolve Bicep deployment outputs'

if ($ReDeploy) {
    $bicepDir = Join-Path $PSScriptRoot 'bicep'

    # Required deploy-time values come from env vars so no PII / object ids
    # land in source control.
    $publisherEmail = $env:BRK223_PUBLISHER_EMAIL
    $aadAdminLogin  = $env:BRK223_SQL_AAD_ADMIN_LOGIN
    $aadAdminOid    = $env:BRK223_SQL_AAD_ADMIN_OBJECT_ID

    if ([string]::IsNullOrEmpty($publisherEmail)) {
        throw 'Set $env:BRK223_PUBLISHER_EMAIL before -ReDeploy (APIM publisherEmail).'
    }
    if ([string]::IsNullOrEmpty($aadAdminLogin)) {
        throw 'Set $env:BRK223_SQL_AAD_ADMIN_LOGIN before -ReDeploy (UPN of SQL AAD admin).'
    }
    if ([string]::IsNullOrEmpty($aadAdminOid)) {
        throw 'Set $env:BRK223_SQL_AAD_ADMIN_OBJECT_ID before -ReDeploy (object id of SQL AAD admin).'
    }

    Write-Info "Running az deployment group create (-ReDeploy)..."
    & az deployment group create `
        -g $ResourceGroup `
        -n $DeploymentName `
        -f (Join-Path $bicepDir 'main.bicep') `
        -p "@$(Join-Path $bicepDir 'params.json')" `
        -p "publisherEmail=$publisherEmail" `
        -p "sqlAadAdminLogin=$aadAdminLogin" `
        -p "sqlAadAdminObjectId=$aadAdminOid" `
        --only-show-errors `
        -o none
    if ($LASTEXITCODE -ne 0) { throw "az deployment group create exited $LASTEXITCODE" }
    Write-Ok 'Bicep deployment succeeded.'
}

$outJson = & az deployment group show -g $ResourceGroup -n $DeploymentName --query 'properties.outputs' -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $outJson) {
    throw "Could not read deployment '$DeploymentName' in RG '$ResourceGroup'. Run with -ReDeploy first."
}
$out = $outJson | ConvertFrom-Json

$sqlFqdn      = $out.sqlServerFqdn.value
$aoaiEndpoint = $out.aoaiEndpoint.value       # https://...openai.azure.com/
$apimGateway  = $out.apimGatewayUrl.value     # https://....azure-api.net
$AoaiHost     = ([uri]$aoaiEndpoint).Host
$ApimHost     = ([uri]$apimGateway).Host

# sqlServerFqdn might be reported with the .database.windows.net suffix only
# (no scheme). Normalize for sqlsim -S.
$sqlServerForSqlsim = if ($sqlFqdn -match '^https?://') { ([uri]$sqlFqdn).Host } else { $sqlFqdn }

Write-Info "SQL server : $sqlServerForSqlsim"
Write-Info "AOAI host  : $AoaiHost"
Write-Info "APIM host  : $ApimHost"
Write-Info "Chat depl. : $ChatDeployment"
Write-Info "Embed depl.: $EmbedDeployment"
Write-Info "AOAI api   : $AoaiApiVersion"

if ($SkipDeploy) { Write-Warn2 '-SkipDeploy set; exiting after outputs.'; return }

#=============================================================================
# Step 2 — firewall rule for current public IP
#=============================================================================
Write-Step 2 'SQL firewall — allow current public IP'

if ($SkipFirewall) {
    Write-Info 'Skipped (-SkipFirewall).'
} else {
    $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim()
    if (-not ($myIp -match '^\d{1,3}(\.\d{1,3}){3}$')) {
        throw "Couldn't resolve current public IP (got '$myIp')."
    }
    $serverShort = $sqlServerForSqlsim.Split('.')[0]
    $ruleName    = "BobDevbox-$($myIp.Replace('.', '-'))"
    Write-Info "Public IP $myIp -> firewall rule '$ruleName'"
    & az sql server firewall-rule create `
        --resource-group $ResourceGroup `
        --server $serverShort `
        --name $ruleName `
        --start-ip-address $myIp `
        --end-ip-address   $myIp `
        --only-show-errors -o none 2>$null
    # Update path in case the rule already existed (different IP previously).
    if ($LASTEXITCODE -ne 0) {
        & az sql server firewall-rule update `
            --resource-group $ResourceGroup `
            --server $serverShort `
            --name $ruleName `
            --start-ip-address $myIp `
            --end-ip-address   $myIp `
            --only-show-errors -o none
    }
    Write-Ok 'Firewall rule in place.'
}

#=============================================================================
# Step 3 — AAD access token for Azure SQL
#=============================================================================
Write-Step 3 'Acquire AAD access token (audience: database.windows.net)'

$accessToken = (& az account get-access-token --resource 'https://database.windows.net' --query accessToken -o tsv).Trim()
if (-not $accessToken) { throw 'az account get-access-token returned empty.' }
Write-Ok "Token acquired (length $($accessToken.Length))."

#=============================================================================
# Step 4 — sanity probe
#=============================================================================
Write-Step 4 'Probe: SELECT @@VERSION'

$probe = Invoke-AzSqlQuery -Query "SELECT TOP 1 LEFT(@@VERSION, 80) AS ver;" -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken
if ($LASTEXITCODE -ne 0) { $probe | Out-Host; throw "Probe failed (sqlsim exit $LASTEXITCODE)." }
$probe | Where-Object { $_ -match 'Microsoft' } | Select-Object -First 1 | ForEach-Object { Write-Info $_.Trim() }
Write-Ok 'Connected to Hyperscale.'

#=============================================================================
# Step 5 — deploy schema/corpus/procs
#=============================================================================
Write-Step 5 'Deploy schema, corpus, procs (in order)'

$localScripts = Join-Path $PSScriptRoot '..\local\sqlscripts'
$azureScripts = Join-Path $PSScriptRoot 'sqlscripts'

$tplVars = @{
    AoaiHost        = $AoaiHost
    ApimHost        = $ApimHost
    ChatDeployment  = $ChatDeployment
    EmbedDeployment = $EmbedDeployment
    AoaiApiVersion  = $AoaiApiVersion
}

# 5.0  Preview features ON for this DB (no-op on hot deploys; cheap).
Write-Info '5.0  ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON'
Invoke-AzSqlScriptText `
    -Body "ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;`r`nGO`r`n" `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label 'preview_features'

# 5.0a Database master key — prerequisite for DATABASE SCOPED CREDENTIAL.
#      Azure SQL DB accepts CREATE MASTER KEY with no password (system-managed).
Write-Info '5.0a CREATE MASTER KEY (idempotent)'
Invoke-AzSqlScriptText `
    -Body @"
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY;
GO
"@ `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label 'master_key'

# 5.1  EXTERNAL MODEL + DSCs MUST come before schema, because
#      usp_HybridSearch in 01_schema references AoaiTextEmbed3Small
#      and SQL validates EXTERNAL MODEL references at CREATE PROCEDURE time.
Write-Info '5.1  azure 03_external_model.sql (DSCs + AoaiTextEmbed3Small + smoke test)'
$emBody = Resolve-SqlTemplate -Path (Join-Path $azureScripts '03_external_model.sql') -Vars $tplVars
Invoke-AzSqlScriptText -Body $emBody `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label '03_external_model'

# 5.2  Schema (materialized — strip local EXTERNAL MODEL, rewrite model+width)
Write-Info '5.2  01_schema.sql  (mutated: OllamaMxbai -> AoaiTextEmbed3Small, vector 1024 -> 1536)'
$schemaBody = Get-AzureMutatedSchema -Path (Join-Path $localScripts '01_schema.sql')
Invoke-AzSqlScriptText -Body $schemaBody `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label '01_schema'

# 5.3  Seed corpus (mutated; ~300 archive + 20 runbook embeddings via AOAI)
Write-Info '5.3  02_seed_corpus.sql  (mutated; calls AOAI text-embedding-3-small ~320x)'
$seedBody = Get-AzureMutatedScript -Path (Join-Path $localScripts '02_seed_corpus.sql')
Invoke-AzSqlScriptText -Body $seedBody `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label '02_seed_corpus' -QueryTimeoutSeconds 1800

# 5.4  Vector indexes (reused verbatim)
Write-Info '5.4  03_vector_indexes.sql  (verbatim, USE stripped)'
$viBody = Get-Content -Raw -LiteralPath (Join-Path $localScripts '03_vector_indexes.sql')
$viBody = $viBody -replace '(?im)^\s*USE\s+zavalivesitedb\s*;\s*$', '-- USE zavalivesitedb stripped by Prep-Cloud.ps1.'
Invoke-AzSqlScriptText -Body $viBody `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label '03_vector_indexes'

# 5.5  Diagnostic procs (reused verbatim — no AI deps)
Write-Info '5.5  04b_diagnostic_procs.sql  (verbatim, USE stripped)'
$dxBody = Get-Content -Raw -LiteralPath (Join-Path $localScripts '04b_diagnostic_procs.sql')
$dxBody = $dxBody -replace '(?im)^\s*USE\s+zavalivesitedb\s*;\s*$', '-- USE zavalivesitedb stripped by Prep-Cloud.ps1.'
Invoke-AzSqlScriptText -Body $dxBody `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label '04b_diagnostic_procs'

# 5.6  usp_GenerateMitigation (gateway-default, lift-and-shift name).
#      Same proc name as the local Ollama proc; writes ProposedMitigation;
#      cloud always goes through APIM.
Write-Info '5.6  azure 04a_proc_generate_mitigation.sql  (usp_GenerateMitigation, gateway)'
$liftBody = Resolve-SqlTemplate -Path (Join-Path $azureScripts '04a_proc_generate_mitigation.sql') -Vars $tplVars
Invoke-AzSqlScriptText -Body $liftBody `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label '04a_proc'

# 5.8  Row 5012 (mutated — uses AoaiTextEmbed3Small for the inline embedding)
Write-Info '5.8  05_create_incident.sql  (mutated; inserts IncidentId 5012)'
$incidentBody = Get-AzureMutatedScript -Path (Join-Path $localScripts '05_create_incident.sql')
Invoke-AzSqlScriptText -Body $incidentBody `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label '05_create_incident'

Write-Ok 'All scripts deployed.'

#=============================================================================
# Step 6 — execute the mitigation proc
#=============================================================================
Write-Step 6 'Execute usp_GenerateMitigation against IncidentId 5012'

Invoke-AzSqlScriptText `
    -Body "EXEC dbo.usp_GenerateMitigation @IncidentId = 5012;`r`nGO`r`n" `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken `
    -Label 'exec_mitigation' -QueryTimeoutSeconds 240

#=============================================================================
# Step 7 — verify ProposedMitigation is populated
#=============================================================================
Write-Step 7 'Verify ProposedMitigation populated for 5012'

$verify = Invoke-AzSqlQuery `
    -Query @"
SET NOCOUNT ON;
SELECT TOP 1
    IncidentId,
    summary = JSON_VALUE(ProposedMitigation, '$.summary'),
    len     = LEN(CAST(ProposedMitigation AS nvarchar(max)))
FROM dbo.Incident
WHERE IncidentId = 5012;
"@ `
    -Server $sqlServerForSqlsim -Database $DatabaseName -AccessToken $accessToken
if ($LASTEXITCODE -ne 0) { $verify | Out-Host; throw 'Verify query failed.' }
$verify | Out-Host

Write-Ok 'BRK223 cloud stack ready.'
Write-Host ''
Write-Host '  SQL FQDN  : ' -NoNewline; Write-Host $sqlServerForSqlsim -ForegroundColor Green
Write-Host '  AOAI host : ' -NoNewline; Write-Host $AoaiHost           -ForegroundColor Green
Write-Host '  APIM host : ' -NoNewline; Write-Host $ApimHost           -ForegroundColor Green
Write-Host ''
