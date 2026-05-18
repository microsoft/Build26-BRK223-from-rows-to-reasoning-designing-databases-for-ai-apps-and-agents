<#
.SYNOPSIS
  Tear down ONLY the BRK223 hosting layer (ACR + ACA env + ACA DAB + SWA).

.DESCRIPTION
  Leaves the base stack intact (Hyperscale, AOAI, APIM, Content Safety) so
  cost is back to "just the SQL + AOAI base" when the demo isn't being
  rehearsed.

  Idempotent: missing resources are skipped silently.

.PARAMETER ResourceGroup
  Resource group. Default: zavalivesiterg.

.PARAMETER NameSuffix
  6-char suffix. Default: vzew2f.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $ResourceGroup = 'zavalivesiterg',
    [string] $NameSuffix    = 'vzew2f'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$acrName    = "zavaacr$NameSuffix"
$acaDabName = "zava-dab-$NameSuffix"
$acaEnvName = "zava-aca-env-$NameSuffix"
$swaName    = "zava-web-$NameSuffix"

function Remove-IfExists {
    param([string]$Kind, [scriptblock]$ExistsCheck, [scriptblock]$Delete, [string]$Name)
    $exists = & $ExistsCheck 2>$null
    if ($exists) {
        if ($PSCmdlet.ShouldProcess($Name, "Delete $Kind")) {
            Write-Host "  Deleting $Kind $Name..." -ForegroundColor Yellow
            & $Delete | Out-Null
        }
    } else {
        Write-Host "  Skip   $Kind $Name (not found)" -ForegroundColor Gray
    }
}

Write-Host "Tearing down hosting layer in $ResourceGroup..." -ForegroundColor Cyan

Remove-IfExists -Kind 'ACA app' -Name $acaDabName `
    -ExistsCheck { az containerapp show -g $ResourceGroup -n $acaDabName --query name -o tsv } `
    -Delete      { az containerapp delete -g $ResourceGroup -n $acaDabName --yes }

Remove-IfExists -Kind 'ACA env' -Name $acaEnvName `
    -ExistsCheck { az containerapp env show -g $ResourceGroup -n $acaEnvName --query name -o tsv } `
    -Delete      { az containerapp env delete -g $ResourceGroup -n $acaEnvName --yes }

Remove-IfExists -Kind 'SWA' -Name $swaName `
    -ExistsCheck { az staticwebapp show -g $ResourceGroup -n $swaName --query name -o tsv } `
    -Delete      { az staticwebapp delete -g $ResourceGroup -n $swaName --yes }

Remove-IfExists -Kind 'ACR' -Name $acrName `
    -ExistsCheck { az acr show -g $ResourceGroup -n $acrName --query name -o tsv } `
    -Delete      { az acr delete -g $ResourceGroup -n $acrName --yes }

Write-Host "`nHosting layer torn down. Base stack (SQL/AOAI/APIM/CS) untouched." -ForegroundColor Green
