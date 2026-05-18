<#
.SYNOPSIS
  Tear down all OLD zavalivesite-* resources in zavalivesiterg before redeploying
  under the new zava-* naming (zavasqlserver / zavalivesitedb / zava-* hosting)
  on HS_PRMS_32 Hyperscale Premium-series.

.DESCRIPTION
  Enumerates every resource in $ResourceGroup whose name starts with 'zavalivesite'
  and deletes it. Slow deletes (APIM, SQL server) use --no-wait so the script
  returns quickly — the new deploy can run in parallel because the new names
  (zava-*) do not collide with the old (zavalivesite-*).

  Optionally purges soft-deleted Cognitive Services / APIM tombstones
  (not strictly required because new names differ; pass -PurgeSoftDeleted
  only if you want the zavalivesite-* names freed for future reuse).

  This script is NOT run automatically. Review the planned-delete output first,
  then re-run with -Confirm:$true (or -Force) to actually delete.

.PARAMETER ResourceGroup
  Resource group holding the resources. Default zavalivesiterg.

.PARAMETER Force
  Skip the confirmation prompt and proceed.

.PARAMETER PurgeSoftDeleted
  Also purge soft-deleted AOAI / CS / APIM tombstones for the zavalivesite-* names.

.EXAMPLE
  ./Reset-Stack.ps1
      Dry-run: lists what would be deleted, prompts for confirmation.

  ./Reset-Stack.ps1 -Force
      Deletes without prompting.
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup    = 'zavalivesiterg',
    [string] $Location         = 'eastus2',
    [switch] $Force,
    [switch] $PurgeSoftDeleted
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Section { param([string]$T) Write-Host ''; Write-Host ("=== {0} ===" -f $T) -ForegroundColor Cyan }
function Write-Step    { param([string]$M) Write-Host (" - {0}" -f $M) -ForegroundColor Gray }

Write-Section 'Pre-flight'
Write-Step ("Subscription : {0}" -f (az account show --query name -o tsv))
Write-Step ("ResourceGroup: {0}" -f $ResourceGroup)

# --- Discover -----------------------------------------------------------------
Write-Section 'Discover zavalivesite-* resources'

$allJson  = az resource list -g $ResourceGroup -o json
$resources = $allJson | ConvertFrom-Json | Where-Object { $_.name -like 'zavalivesite*' } |
    Select-Object name, type, id

if (-not $resources -or $resources.Count -eq 0) {
    Write-Host "No zavalivesite-* resources found in $ResourceGroup. Nothing to do." -ForegroundColor Green
    return
}

$resources | Sort-Object type, name | Format-Table type, name -AutoSize

# --- Confirm ------------------------------------------------------------------
if (-not $Force) {
    $ans = Read-Host "Delete the $($resources.Count) resources above? [y/N]"
    if ($ans -ne 'y' -and $ans -ne 'Y') {
        Write-Host 'Aborted.' -ForegroundColor Yellow
        return
    }
}

# --- Delete order (leaves before roots) ---------------------------------------
# 1. ACA apps (containerApps)
# 2. ACA env (managedEnvironments)
# 3. SWA (staticSites)
# 4. ACR (registries)
# 5. APIM (service) -- slow, --no-wait
# 6. AOAI + CS (accounts)
# 7. SQL server (cascades DB + firewall + admin) -- slow, --no-wait
$order = @(
    'Microsoft.App/containerApps',
    'Microsoft.App/managedEnvironments',
    'Microsoft.Web/staticSites',
    'Microsoft.ContainerRegistry/registries',
    'Microsoft.ApiManagement/service',
    'Microsoft.CognitiveServices/accounts',
    'Microsoft.Sql/servers'
)

Write-Section 'Delete'
foreach ($t in $order) {
    foreach ($r in ($resources | Where-Object { $_.type -eq $t })) {
        Write-Step ("delete --no-wait : {0}  ({1})" -f $r.name, $r.type)
        az resource delete --ids $r.id --no-wait 2>&1 | Out-Host
    }
}

# Anything else (role assignments, diagnostic settings, etc.) -- best effort
foreach ($r in ($resources | Where-Object { $order -notcontains $_.type })) {
    Write-Step ("delete --no-wait : {0}  ({1})" -f $r.name, $r.type)
    az resource delete --ids $r.id --no-wait 2>&1 | Out-Host
}

# --- Purge soft-deleted (optional) -------------------------------------------
if ($PurgeSoftDeleted) {
    Write-Section 'Purge soft-deleted Cognitive Services tombstones'
    foreach ($name in @('zavalivesite-aoai-vzew2f','zavalivesite-cs-vzew2f')) {
        Write-Step ("purge CS account: {0}" -f $name)
        az cognitiveservices account purge `
            --location $Location `
            --resource-group $ResourceGroup `
            --name $name 2>&1 | Out-Host
    }
}

Write-Host ''
Write-Host 'Deletes submitted with --no-wait. APIM + SQL server can take 30-45 minutes' -ForegroundColor Yellow
Write-Host 'to finish in the background. The NEW deploy uses zava-* names so it does' -ForegroundColor Yellow
Write-Host 'NOT need to wait. Proceed to:' -ForegroundColor Yellow
Write-Host '  ./Prep-Cloud.ps1' -ForegroundColor Cyan
Write-Host '  ./Prep-Cloud-Hosting.ps1' -ForegroundColor Cyan
