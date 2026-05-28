<#
.SYNOPSIS
    One-command environment prep for the BRK223 local demo.

.DESCRIPTION
    This is the single entrypoint for presenters. It is idempotent and
    sequences the existing scripts so you can run one command on both fresh
    and already-prepared machines.

    Flow:
      1. Build.ps1                  (install/provision/repair as needed)
      2. deploy-prestage.ps1        (drop/recreate + seed database)
      3. Reset-ForBeat2.ps1         (rewind to pre-Beat-1 state)
      4. Warmup-Ai.ps1              (preload chat + embedding models)
      5. Verify-Build.ps1           (required health checks)
      6. Start-LiveSite.ps1         (optional; starts AppHost + DAB + web)

    This script intentionally re-runs deploy-prestage to guarantee a clean
    database every time, even if zavalivesitedb already exists.

.PARAMETER ContainerName
    SQL container name. Default: azsql-zavalivesite.

.PARAMETER SqlPort
    SQL host port. Default: 14330.

.PARAMETER SaPassword
    SA password. Default: $env:BRK223_SA_PASSWORD.

.PARAMETER SqlAdminPassword
    sqladmin password. Default: $env:BRK223_SQLADMIN_PASSWORD.

.PARAMETER SqlImage
    SQL image reference. Resolution: -SqlImage, then $env:BRK223_SQL_IMAGE.

.PARAMETER SkipStart
    Do not run Start-LiveSite.ps1.

.EXAMPLE
    $env:BRK223_SA_PASSWORD = '<sa pwd>'
    $env:BRK223_SQLADMIN_PASSWORD = '<sqladmin pwd>'
    $env:BRK223_SQL_IMAGE = '<private-preview-image-from-session-owner>'
    .\Prepare-DemoEnvironment.ps1
#>
[CmdletBinding()]
param(
    [string]$ContainerName = 'azsql-zavalivesite',
    [int]$SqlPort = 14330,
    [securestring]$SaCredential,
    [securestring]$SqlAdminCredential,
    [string]$SaSecret = $env:BRK223_SA_PASSWORD,
    [string]$SqlAdminSecret = $env:BRK223_SQLADMIN_PASSWORD,
    [string]$SqlImage = '',
    [switch]$SkipStart
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Read-SecretAsPlainText {
    param([Parameter(Mandatory)] [string]$Prompt)

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Convert-PasswordInputToPlainText {
    param(
        [Parameter(ValueFromPipeline)] $Value,
        [Parameter(Mandatory)] [string]$Prompt
    )

    if ($Value -is [securestring]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return Read-SecretAsPlainText -Prompt $Prompt
    }

    return $text
}

function Resolve-SqlImage {
    param([string]$CurrentValue)

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue
    }

    $defaultImage = [string]$env:BRK223_SQL_IMAGE
    if ([string]::IsNullOrWhiteSpace($defaultImage)) {
        $entered = Read-Host -Prompt 'Enter SQL image (required)'
    }
    else {
        $entered = Read-Host -Prompt "Enter SQL image (press Enter to use BRK223_SQL_IMAGE: $defaultImage)"
        if ([string]::IsNullOrWhiteSpace($entered)) {
            return $defaultImage
        }
    }

    return $entered
}

function Maybe-PersistSqlImage {
    param([Parameter(Mandatory)] [string]$ResolvedImage)

    if ([string]::IsNullOrWhiteSpace($ResolvedImage)) {
        return
    }

    if (-not $ResolvedImage.StartsWith('sqlbuilds.azurecr.io/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    if ($env:BRK223_SQL_IMAGE -eq $ResolvedImage) {
        return
    }

    $persistChoice = Read-Host -Prompt 'Persist BRK223_SQL_IMAGE for future terminals (User scope)? [Y/n]'
    if (-not [string]::IsNullOrWhiteSpace($persistChoice) -and $persistChoice -notmatch '^(y|yes)$') {
        return
    }

    [Environment]::SetEnvironmentVariable('BRK223_SQL_IMAGE', $ResolvedImage, 'User')
    $env:BRK223_SQL_IMAGE = $ResolvedImage
    Write-Host "Saved BRK223_SQL_IMAGE (User): $ResolvedImage" -ForegroundColor DarkGray
}

$SaPassword = if ($null -ne $SaCredential) {
    Convert-PasswordInputToPlainText -Value $SaCredential -Prompt 'Enter SA password (BRK223_SA_PASSWORD)'
} else {
    Convert-PasswordInputToPlainText -Value $SaSecret -Prompt 'Enter SA password (BRK223_SA_PASSWORD)'
}

$SqlAdminPassword = if ($null -ne $SqlAdminCredential) {
    Convert-PasswordInputToPlainText -Value $SqlAdminCredential -Prompt 'Enter sqladmin password (BRK223_SQLADMIN_PASSWORD)'
} else {
    Convert-PasswordInputToPlainText -Value $SqlAdminSecret -Prompt 'Enter sqladmin password (BRK223_SQLADMIN_PASSWORD)'
}

$SqlImage = Resolve-SqlImage -CurrentValue $SqlImage
Maybe-PersistSqlImage -ResolvedImage $SqlImage

if ([string]::IsNullOrWhiteSpace($SaPassword)) {
    throw 'SaPassword required. Pass -SaPassword, set $env:BRK223_SA_PASSWORD, or enter when prompted.'
}
if ([string]::IsNullOrWhiteSpace($SqlAdminPassword)) {
    throw 'SqlAdminPassword required. Pass -SqlAdminPassword, set $env:BRK223_SQLADMIN_PASSWORD, or enter when prompted.'
}
if ([string]::IsNullOrWhiteSpace($SqlImage)) {
    throw 'SqlImage required. Pass -SqlImage, set $env:BRK223_SQL_IMAGE, or enter when prompted.'
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)] [int]$Number,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [scriptblock]$Action
    )

    Write-Host "`n=== Step $Number - $Name ===" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Action
    $sw.Stop()
    Write-Host "  [OK] step $Number completed in $([int]$sw.Elapsed.TotalSeconds)s" -ForegroundColor Green
}

Write-Host '=== Prepare-DemoEnvironment.ps1 ===' -ForegroundColor Cyan
Write-Host "Container: $ContainerName  SQL: localhost,$SqlPort" -ForegroundColor DarkGray
Write-Host "Start LiveSite: $(-not $SkipStart)" -ForegroundColor DarkGray

Invoke-Step -Number 1 -Name 'Build bootstrap (install/detect/provision)' -Action {
    & "$PSScriptRoot\Build.ps1" `
        -ContainerName $ContainerName `
        -SqlPort $SqlPort `
        -SaPassword $SaPassword `
        -SqlAdminPassword $SqlAdminPassword `
        -SqlImage $SqlImage
    if ($LASTEXITCODE -ne 0) {
        throw "Build.ps1 exited $LASTEXITCODE"
    }
}

Invoke-Step -Number 2 -Name 'Database reset + pre-stage (drop/recreate + seed)' -Action {
    & "$PSScriptRoot\deploy-prestage.ps1" `
        -Server "localhost,$SqlPort" `
        -SaPassword $SaPassword `
        -SqlAdminPassword $SqlAdminPassword
    if ($LASTEXITCODE -ne 0) {
        throw "deploy-prestage.ps1 exited $LASTEXITCODE"
    }
}

Invoke-Step -Number 3 -Name 'Rewind to pre-Beat-1 state' -Action {
    & "$PSScriptRoot\Reset-ForBeat2.ps1" `
        -Server "localhost,$SqlPort" `
        -Password $SqlAdminPassword
    if ($LASTEXITCODE -ne 0) {
        throw "Reset-ForBeat2.ps1 exited $LASTEXITCODE"
    }
}

Invoke-Step -Number 4 -Name 'Warm AI models' -Action {
    & "$PSScriptRoot\Warmup-Ai.ps1" -ContainerName $ContainerName
    if ($LASTEXITCODE -ne 0) {
        throw "Warmup-Ai.ps1 exited $LASTEXITCODE"
    }
}

Invoke-Step -Number 5 -Name 'Verify required prereqs' -Action {
    & "$PSScriptRoot\Verify-Build.ps1" `
        -ContainerName $ContainerName `
        -SqlPort $SqlPort `
        -SaPassword $SaPassword
    if ($LASTEXITCODE -ne 0) {
        throw "Verify-Build.ps1 exited $LASTEXITCODE"
    }
}

if ($SkipStart) {
    Write-Host "`n=== Step 6 - Start-LiveSite.ps1 ===" -ForegroundColor Cyan
    Write-Host '  [SKIP] skipped (-SkipStart)' -ForegroundColor DarkYellow
} else {
    Invoke-Step -Number 6 -Name 'Start LiveSite (AppHost + DAB + web)' -Action {
        & "$PSScriptRoot\Start-LiveSite.ps1"
        if ($LASTEXITCODE -ne 0) {
            throw "Start-LiveSite.ps1 exited $LASTEXITCODE"
        }
    }
}

Write-Host "`nEnvironment prep complete." -ForegroundColor Green
Write-Host 'Browser: http://localhost:8080/?dab=local' -ForegroundColor DarkGray
Write-Host 'Optional smoke: .\Test-AgentPath.ps1 -WithReset' -ForegroundColor DarkGray
