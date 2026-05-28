<#
.SYNOPSIS
  BRK223 — Stand up the Azure-hosted Blazor + DAB lift-and-shift of the
  laptop demo.

.DESCRIPTION
  Sits ON TOP OF Prep-Cloud.ps1. Assumes that script has already provisioned
  Hyperscale, AOAI, APIM, Content Safety and that all SQL objects + 5012
  data are loaded.

  This script adds the hosting layer:

    1. Deploy hosting.bicep            → ACR, ACA env, ACA DAB app, SWA.
    2. az acr build                    → cloud-side Docker build of the DAB
                                         image from hosting/dab/.
    3. Update ACA revision             → pick up the freshly-built tag.
    4. SQL grants for the ACA MI       → grant_aca_mi.sql via sqlsim.
    5. Publish Blazor (Release)        → dotnet publish + write
                                         appsettings.Production.json with
                                         the ACA DAB FQDN.
    6. Deploy Blazor wwwroot to SWA    → swa CLI.
    7. Smoke test                      → REST GET /api/Incident, MCP GET
                                         /mcp/, SWA root.

  Every step is idempotent. A second run re-deploys, re-builds, re-uploads,
  but converges on the same state.

.PARAMETER ResourceGroup
  Resource group provisioned by Prep-Cloud.ps1. Default: zavalivesiterg.

.PARAMETER NameSuffix
  6-char suffix on every resource name. Default: vzew2f.
  Must match the suffix used in Prep-Cloud.ps1.

.PARAMETER SkipBuild
  Skip the ACR image build (use when you've already pushed `latest`).

.PARAMETER SkipBlazor
  Skip Blazor publish + SWA upload (useful when iterating on DAB only).

.PARAMETER WhatIf
  Print the plan and stop.

.NOTES
  Tooling required:
    - Azure CLI 2.60+ with `staticwebapp` extension (auto-installed if missing).
    - .NET 9 SDK for dotnet publish.
    - swa CLI (npm install -g @azure/static-web-apps-cli) — auto-installed.
    - sqlsim at C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe.
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup = 'zavalivesiterg',
    [string] $NameSuffix    = 'vzew2f',
    [string] $Location      = 'eastus2',
    [string] $SqlServerName = '',
    [string] $SqlDatabase   = 'zavalivesitedb',
    [switch] $SkipBuild,
    [switch] $SkipBlazor,
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# PowerShell 7+: prevent native-command stderr (like Bicep warnings) from
# terminating the script under -ErrorAction Stop.
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($SqlServerName)) {
    $SqlServerName = "zavasqlserver-$NameSuffix"
}

# --- Paths -------------------------------------------------------------------
$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BicepFile    = Join-Path $ScriptRoot 'bicep\hosting.bicep'
$DabContext   = Join-Path $ScriptRoot 'hosting\dab'           # Dockerfile + dab-config.json
$GrantSql     = Join-Path $ScriptRoot 'hosting\sql\grant_aca_mi.sql'
$BlazorProj   = Resolve-Path (Join-Path $ScriptRoot '..\local\dotnet\Web\ZavaLiveSite.Web.csproj')
$BlazorPub    = Join-Path $ScriptRoot 'hosting\blazor-publish'

# Reuse the local Get-Sqlsim resolver (bundled utilities\sqlsim.exe is the
# preferred path; $env:SQLSIM_PATH wins if set).
. (Join-Path $ScriptRoot '..\local\Common.ps1')
$Sqlsim       = Get-Sqlsim

function Write-Section { param([string]$Title) Write-Host ''; Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan }
function Write-Step    { param([string]$Msg)   Write-Host (" - {0}" -f $Msg) -ForegroundColor Gray }

# --- Pre-flight --------------------------------------------------------------
Write-Section 'Pre-flight'

if (-not (Test-Path $BicepFile)) { throw "Missing $BicepFile" }
if (-not (Test-Path $DabContext)) { throw "Missing $DabContext" }
if (-not (Test-Path $GrantSql))   { throw "Missing $GrantSql" }
if (-not $SkipBlazor -and -not (Test-Path $BlazorProj)) { throw "Missing $BlazorProj" }
if (-not (Test-Path $Sqlsim))     { throw "Missing $Sqlsim (set `$env:SQLSIM_PATH or drop sqlsim.exe in ..\local\utilities\)" }
Write-Step "sqlsim: $Sqlsim"

Write-Step "az login subscription:"
az account show --query 'name' -o tsv

$sqlServerFqdn = "$SqlServerName.database.windows.net"
Write-Step "Target SQL: $sqlServerFqdn / $SqlDatabase"

if ($WhatIf) {
    Write-Host "`n-WhatIf: stopping before deployment." -ForegroundColor Yellow
    return
}

# --- 1. Pre-create ACR + build image (so bicep can reference it directly) ---
# Bicep's container app references the DAB image. If the image is not in ACR
# at the time of bicep deploy, ACA revision provisioning loops on ImagePull
# until it times out ("Operation expired"). Pre-build to break the chicken-egg.
$acrName  = ('zavaacr{0}' -f $NameSuffix)
$acrLogin = "$acrName.azurecr.io"
$dabImage = "$acrLogin/zava-dab:latest"

Write-Section "1. Pre-create ACR + build DAB image"
Write-Step "ACR name: $acrName"
az acr create -g $ResourceGroup -n $acrName --sku Basic --admin-enabled false --only-show-errors -o none
if ($LASTEXITCODE -ne 0) { throw "az acr create exited $LASTEXITCODE" }

if (-not $SkipBuild) {
    Push-Location $DabContext
    try {
        az acr build --registry $acrName --image "zava-dab:latest" --file Dockerfile . | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "az acr build exited $LASTEXITCODE" }
    } finally { Pop-Location }
} else {
    Write-Host "  (build skipped — assuming zava-dab:latest already in $acrName)" -ForegroundColor Yellow
}

# --- 2. Bicep deploy --------------------------------------------------------
Write-Section '2. Deploy hosting.bicep'

$deployName = "zava-hosting-{0:yyyyMMddHHmm}" -f (Get-Date)
$deployJson = az deployment group create `
    --resource-group $ResourceGroup `
    --name $deployName `
    --template-file $BicepFile `
    --parameters nameSuffix=$NameSuffix sqlServerFqdn=$sqlServerFqdn sqlDatabaseName=$SqlDatabase location=$Location dabImage=$dabImage `
    --only-show-errors `
    -o json
if ($LASTEXITCODE -ne 0) {
    throw "az deployment group create exited $LASTEXITCODE"
}
$deploy = $deployJson | ConvertFrom-Json

$acrName       = $deploy.properties.outputs.acrName.value
$acrLogin      = $deploy.properties.outputs.acrLoginServer.value
$acaDabName    = $deploy.properties.outputs.acaDabName.value
$acaDabFqdn    = $deploy.properties.outputs.acaDabFqdn.value
$acaPrincipal  = $deploy.properties.outputs.acaDabPrincipalId.value
$swaName       = $deploy.properties.outputs.swaName.value
$swaHostname   = $deploy.properties.outputs.swaDefaultHostname.value

Write-Step "ACR:        $acrLogin"
Write-Step "ACA DAB:    https://$acaDabFqdn"
Write-Step "ACA MI:     $acaPrincipal"
Write-Step "SWA:        https://$swaHostname"

# --- 3. Refresh ACA revision -------------------------------------------------
Write-Section '3. Restart ACA revision (force pull latest image)'
az containerapp revision restart `
    --resource-group $ResourceGroup `
    --name $acaDabName `
    --revision (az containerapp revision list -g $ResourceGroup -n $acaDabName --query '[0].name' -o tsv) `
    | Out-Null
Write-Step "ACA revision restarted."

# --- 4. SQL grants -----------------------------------------------------------
Write-Section "4. Grant ACA MI on SQL ($acaDabName)"

# Wait briefly for AAD to propagate the new principal before CREATE USER.
Write-Step "Waiting 20s for AAD to propagate the new ACA principal..."
Start-Sleep -Seconds 20

$sqlToken = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv

# sqlsim does not implement sqlcmd-style :setvar / -v substitution. Pre-render
# the grant script into a temp file with $(AcaAppName) / $(DatabaseName)
# replaced inline, then feed it to sqlsim as a regular .sql file.
$grantRendered = [IO.Path]::Combine([IO.Path]::GetTempPath(), "grant_aca_mi.$([guid]::NewGuid().ToString('N')).sql")
$grantText = Get-Content -Raw -Path $GrantSql
$grantText = $grantText -replace '\$\(AcaAppName\)',  $acaDabName
$grantText = $grantText -replace '\$\(DatabaseName\)', $SqlDatabase
# Strip the USE — already scoped by the -d connection on Azure SQL.
$grantText = $grantText -replace '(?im)^\s*USE\s+\[[^\]]+\]\s*;\s*$', '-- USE stripped for Azure SQL'
# Strip sqlcmd-only directives that sqlsim doesn't understand.
$grantText = $grantText -replace '(?im)^\s*:on\s+error\s+\w+\s*$', '-- :on error stripped'
Set-Content -Path $grantRendered -Value $grantText -Encoding UTF8
Write-Step "Rendered grant script: $grantRendered"

# sqlsim invocation pattern documented in C:\bwsql\.github\skills\sqlsim\SKILL.md
& $Sqlsim `
    -S "$sqlServerFqdn" `
    -d "$SqlDatabase" `
    -T "$sqlToken" `
    -N m `
    -l 30 `
    -t 60 `
    -stoponerror `
    -i $grantRendered
if ($LASTEXITCODE -ne 0) { throw "Grant script failed (exit $LASTEXITCODE)." }
Remove-Item -Force $grantRendered -ErrorAction SilentlyContinue
Write-Step "Grants applied."

# --- 5. Publish Blazor + write cloud appsettings -----------------------------
if (-not $SkipBlazor) {
    Write-Section '5. dotnet publish Blazor'

    if (Test-Path $BlazorPub) { Remove-Item -Recurse -Force $BlazorPub }
    dotnet publish $BlazorProj -c Release -o $BlazorPub --nologo -v minimal | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed." }

    $wwwroot = Join-Path $BlazorPub 'wwwroot'
    if (-not (Test-Path $wwwroot)) { throw "Publish output missing wwwroot at $wwwroot" }

    # Bake the cloud DAB URL into the SWA-hosted Blazor.
    $cloudAppSettings = @{
        DabBaseUrl = "https://$acaDabFqdn"
    } | ConvertTo-Json -Depth 4

    $settingsPath = Join-Path $wwwroot 'appsettings.Production.json'
    [IO.File]::WriteAllText($settingsPath, $cloudAppSettings, [Text.UTF8Encoding]::new($false))
    Write-Step "Wrote $settingsPath"

    # --- 6. Deploy to SWA ----------------------------------------------------
    Write-Section '6. Deploy Blazor to Static Web App'

    # Ensure SWA CLI is present (npm global). We don't fail if npm is
    # missing — fall back to `az staticwebapp` PUT via deployment token.
    $swaCli = Get-Command swa -ErrorAction SilentlyContinue
    if (-not $swaCli) {
        Write-Step "swa CLI not found; installing via npm..."
        npm install -g @azure/static-web-apps-cli | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Failed to install @azure/static-web-apps-cli (npm)." }
    }

    $swaToken = az staticwebapp secrets list `
        --name $swaName --resource-group $ResourceGroup `
        --query 'properties.apiKey' -o tsv
    if (-not $swaToken) { throw "Could not read SWA deployment token." }

    & swa deploy $wwwroot --deployment-token $swaToken --env production | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "swa deploy failed." }
    Write-Step "Blazor published to https://$swaHostname"
} else {
    Write-Host "  (Blazor publish/deploy skipped)" -ForegroundColor Yellow
}

# --- 7. Smoke test -----------------------------------------------------------
Write-Section '7. Smoke test'

function Probe {
    param([string]$Url, [int]$ExpectedStatus = 200)
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
        $ok = ($resp.StatusCode -eq $ExpectedStatus)
        $color = if ($ok) { 'Green' } else { 'Yellow' }
        Write-Host ("  {0,-5} {1} -> {2}" -f $resp.StatusCode, $Url, ($(if($ok){'OK'}else{'mismatch'}))) -ForegroundColor $color
    } catch {
        Write-Host ("  ERR   {0} -> {1}" -f $Url, $_.Exception.Message) -ForegroundColor Red
    }
}

Probe "https://$acaDabFqdn/api/Incident/IncidentId/5012"
Probe "https://$acaDabFqdn/mcp"
if (-not $SkipBlazor) { Probe "https://$swaHostname/" }

# --- Summary -----------------------------------------------------------------
Write-Section 'Summary'
Write-Host ("  Blazor (SWA):       https://{0}/" -f $swaHostname)               -ForegroundColor Green
Write-Host ("  DAB REST (ACA):     https://{0}/api/Incident" -f $acaDabFqdn)    -ForegroundColor Green
Write-Host ("  DAB MCP (ACA):      https://{0}/mcp"          -f $acaDabFqdn)    -ForegroundColor Green
Write-Host ("  SQL server:         {0}"                       -f $sqlServerFqdn) -ForegroundColor Green
Write-Host ''
Write-Host '  Next: copy hosting/mcp.cloud.json into .vscode/mcp.json and reload VS Code.' -ForegroundColor Gray
