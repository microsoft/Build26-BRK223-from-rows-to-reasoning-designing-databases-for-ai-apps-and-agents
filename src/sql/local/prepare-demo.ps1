<#
.SYNOPSIS
    Deterministic, presenter-friendly prep for the BRK223 local demo.

.DESCRIPTION
    Uses only the validated local runtime scripts and adds explicit readiness
    gates so reboot-to-demo is repeatable.

    Flow:
      1. Teardown-LiveSite.ps1
      2. Start-AzureSqlContainer.ps1 (correctly uses -Port)
      3. Wait for SQL readiness
      4. Prepare-AiContainer.ps1
            5. Wait for in-container AI endpoint readiness
            6. Wait for SQL readiness (post-restart)
            7. deploy-prestage.ps1
            8. Reset-ForBeat2.ps1
            9. Warmup-Ai.ps1
         10. Verify-Build.ps1
         11. Start-LiveSite.ps1 (optional)

.PARAMETER ContainerName
    SQL container name. Default: azsql-zavalivesite.

.PARAMETER SqlPort
    SQL host port. Default: 14330.

.PARAMETER SqlImage
    SQL image. Resolution: -SqlImage, then BRK223_SQL_IMAGE, then -SqlImageFile.

.PARAMETER SqlImageFile
    Optional file containing the SQL image reference. Supports either a plain
    image-only line or a note format where the image appears on the line after:
      Current private image:

.PARAMETER SaPassword
    SA password. Resolution: -SaPassword, BRK223_SA_PASSWORD, then prompt.

.PARAMETER SqlAdminPassword
    sqladmin password. Resolution: -SqlAdminPassword, BRK223_SQLADMIN_PASSWORD,
    then prompt.

.PARAMETER PasswordFile
    Optional local password file. If provided and one or both passwords are
    missing, the script reads the next line after the marker:
      sqladmin / SA password:

.PARAMETER SkipStart
    Skip Start-LiveSite.ps1.

.EXAMPLE
    .\prepare-demo.ps1

.EXAMPLE
    .\prepare-demo.ps1 -PasswordFile ..\..\..\_remove-before-publish\local-passwords.txt
#>
[CmdletBinding()]
param(
    [string]$ContainerName = 'azsql-zavalivesite',
    [int]$SqlPort = 14330,
    [string]$SqlImage = '',
    [string]$SqlImageFile = '..\..\..\_remove-before-publish\private-sql-image orig.txt',
    [string]$SaPassword = $env:BRK223_SA_PASSWORD,
    [string]$SqlAdminPassword = $env:BRK223_SQLADMIN_PASSWORD,
    [string]$PasswordFile = '..\..\..\_remove-before-publish\local-passwords.txt',
    [switch]$SkipStart
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

. (Join-Path $PSScriptRoot 'Common.ps1')

function Write-Step {
    param([int]$Number, [string]$Name)
    Write-Host "`n=== Step $Number - $Name ===" -ForegroundColor Cyan
}

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

function Get-PasswordFromFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Password file not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path
    $marker = 'sqladmin / SA password:'
    $idx = [Array]::IndexOf($lines, $marker)
    if ($idx -lt 0 -or ($idx + 1) -ge $lines.Count) {
        throw "Could not find '$marker' followed by a password line in $Path"
    }

    $value = [string]$lines[$idx + 1]
    $value = $value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Password line after '$marker' is blank in $Path"
    }

    return $value
}

function Get-SqlImageFromFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "SQL image file not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path

    # Preferred note format in this repo: marker line, then image line.
    $marker = 'Current private image:'
    $idx = [Array]::IndexOf($lines, $marker)
    if ($idx -ge 0 -and ($idx + 1) -lt $lines.Count) {
        $candidate = [string]$lines[$idx + 1]
        $candidate = $candidate.Trim()
        if ($candidate -match '^[a-z0-9]+([._-][a-z0-9]+)*(\.[a-z0-9]+([._-][a-z0-9]+)*)+/.+:.+$') {
            return $candidate
        }
    }

    # Fallback: first line that looks like a registry image reference.
    foreach ($line in $lines) {
        $candidate = [string]$line
        $candidate = $candidate.Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if ($candidate.StartsWith('#')) {
            continue
        }
        if ($candidate -match '^[a-z0-9]+([._-][a-z0-9]+)*(\.[a-z0-9]+([._-][a-z0-9]+)*)+/.+:.+$') {
            return $candidate
        }
    }

    throw "Could not find a SQL image reference in file: $Path"
}

function Assert-DockerReady {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        $candidate = @(
            "$Env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
            "${Env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe"
        ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

        if (-not $candidate) {
            throw "Docker CLI not found. Install Docker Desktop ('winget install Docker.DockerDesktop')."
        }

        $env:Path = (Split-Path $candidate) + ';' + $env:Path
    }

    docker info *>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Docker engine: ready' -ForegroundColor DarkGray
        return
    }

    $desktop = @(
        "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${Env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    if (-not $desktop) {
        throw 'Docker engine is not running and Docker Desktop.exe was not found.'
    }

    Write-Host 'Docker engine is not running. Launching Docker Desktop...' -ForegroundColor Yellow
    Start-Process -FilePath $desktop | Out-Null

    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        docker info *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Docker engine: ready' -ForegroundColor DarkGray
            return
        }
    }

    throw 'Docker Desktop did not become ready within 3 minutes.'
}

function Wait-SqlReady {
    param(
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Password,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastErr = $null

    while ((Get-Date) -lt $deadline) {
        $out = Invoke-SqlsimQuery -Query 'SELECT 1' -Server $Server -User 'sa' -Password $Password -Quiet 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SQL is ready on $Server" -ForegroundColor Green
            return
        }
        $lastErr = $out
        Start-Sleep -Seconds 2
    }

    throw "SQL did not become ready on $Server within ${TimeoutSeconds}s. Last error: $lastErr"
}

function Wait-AiEndpointReady {
    param(
        [Parameter(Mandatory)] [string]$Container,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $code = docker exec -u root $Container sh -c "curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://localhost:8444/v1/models" 2>$null
        if ($LASTEXITCODE -eq 0 -and $code -match '^(200|404|405)$') {
            Write-Host "AI endpoint is ready in container '$Container' (HTTP $code)" -ForegroundColor Green
            return
        }
        Start-Sleep -Seconds 2
    }

    throw "AI endpoint did not become ready in container '$Container' within ${TimeoutSeconds}s"
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)] [scriptblock]$Action,
        [Parameter(Mandatory)] [string]$Name,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5
    )

    $attempt = 1
    while ($true) {
        try {
            & $Action
            return
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            Write-Host "[Retry] $Name attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "[Retry] waiting ${DelaySeconds}s before retry $($attempt + 1)/$MaxAttempts..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
    }
}

if ([string]::IsNullOrWhiteSpace($SqlImage)) {
    if (-not [string]::IsNullOrWhiteSpace($SqlImageFile)) {
        $SqlImage = Get-SqlImageFromFile -Path $SqlImageFile
    }
}
if ([string]::IsNullOrWhiteSpace($SqlImage)) {
    $SqlImage = [string]$env:BRK223_SQL_IMAGE
}
if ([string]::IsNullOrWhiteSpace($SqlImage)) {
    throw 'SqlImage required. Pass -SqlImage, set BRK223_SQL_IMAGE, or provide -SqlImageFile.'
}

if (([string]::IsNullOrWhiteSpace($SaPassword) -or [string]::IsNullOrWhiteSpace($SqlAdminPassword)) -and -not [string]::IsNullOrWhiteSpace($PasswordFile)) {
    $filePwd = Get-PasswordFromFile -Path $PasswordFile
    if ([string]::IsNullOrWhiteSpace($SaPassword)) {
        $SaPassword = $filePwd
    }
    if ([string]::IsNullOrWhiteSpace($SqlAdminPassword)) {
        $SqlAdminPassword = $filePwd
    }
}

if ([string]::IsNullOrWhiteSpace($SaPassword)) {
    $SaPassword = Read-SecretAsPlainText -Prompt 'Enter SA password (BRK223_SA_PASSWORD)'
}
if ([string]::IsNullOrWhiteSpace($SqlAdminPassword)) {
    $SqlAdminPassword = Read-SecretAsPlainText -Prompt 'Enter sqladmin password (BRK223_SQLADMIN_PASSWORD)'
}

$server = "localhost,$SqlPort"

Write-Host '=== prepare-demo.ps1 ===' -ForegroundColor Cyan
Write-Host "Container: $ContainerName  SQL: $server" -ForegroundColor DarkGray
Write-Host "Start LiveSite: $(-not $SkipStart)" -ForegroundColor DarkGray

Assert-DockerReady

Write-Step -Number 1 -Name 'Teardown existing app host/runtime'
& "$PSScriptRoot\Teardown-LiveSite.ps1"
if ($LASTEXITCODE -ne 0) {
    throw "Teardown-LiveSite.ps1 exited $LASTEXITCODE"
}

Write-Step -Number 2 -Name 'Start SQL container'
& "$PSScriptRoot\Start-AzureSqlContainer.ps1" `
    -Image $SqlImage `
    -ContainerName $ContainerName `
    -Port $SqlPort `
    -SaPassword $SaPassword
if ($LASTEXITCODE -ne 0) {
    throw "Start-AzureSqlContainer.ps1 exited $LASTEXITCODE"
}

Write-Step -Number 3 -Name 'Wait for SQL readiness'
Wait-SqlReady -Server $server -Password $SaPassword -TimeoutSeconds 180

Write-Step -Number 4 -Name 'Prepare AI services in container'
& "$PSScriptRoot\Prepare-AiContainer.ps1" -ContainerName $ContainerName
if ($LASTEXITCODE -ne 0) {
    throw "Prepare-AiContainer.ps1 exited $LASTEXITCODE"
}

Write-Step -Number 5 -Name 'Wait for AI endpoint readiness'
Wait-AiEndpointReady -Container $ContainerName -TimeoutSeconds 180

Write-Step -Number 6 -Name 'Wait for SQL readiness (post-AI restart)'
Wait-SqlReady -Server $server -Password $SaPassword -TimeoutSeconds 240

Write-Step -Number 7 -Name 'Deploy pre-stage schema and data'
Invoke-WithRetry -Name 'deploy-prestage.ps1' -MaxAttempts 3 -DelaySeconds 8 -Action {
    & "$PSScriptRoot\deploy-prestage.ps1" `
        -Server $server `
        -SaPassword $SaPassword `
        -SqlAdminPassword $SqlAdminPassword
    if ($LASTEXITCODE -ne 0) {
        throw "deploy-prestage.ps1 exited $LASTEXITCODE"
    }
}

Write-Step -Number 8 -Name 'Reset to pre-Beat-1 state'
& "$PSScriptRoot\Reset-ForBeat2.ps1" `
    -Server $server `
    -Password $SqlAdminPassword
if ($LASTEXITCODE -ne 0) {
    throw "Reset-ForBeat2.ps1 exited $LASTEXITCODE"
}

Write-Step -Number 9 -Name 'Warm AI models'
& "$PSScriptRoot\Warmup-Ai.ps1" -ContainerName $ContainerName
if ($LASTEXITCODE -ne 0) {
    throw "Warmup-Ai.ps1 exited $LASTEXITCODE"
}

Write-Step -Number 10 -Name 'Verify required prereqs'
& "$PSScriptRoot\Verify-Build.ps1" `
    -ContainerName $ContainerName `
    -SqlPort $SqlPort `
    -SaPassword $SaPassword
if ($LASTEXITCODE -ne 0) {
    throw "Verify-Build.ps1 exited $LASTEXITCODE"
}

if ($SkipStart) {
    Write-Step -Number 11 -Name 'Start LiveSite'
    Write-Host '  [SKIP] skipped (-SkipStart)' -ForegroundColor DarkYellow
}
else {
    Write-Step -Number 11 -Name 'Start LiveSite (AppHost + DAB + web)'
    $env:BRK223_SQLADMIN_PASSWORD = $SqlAdminPassword
    $env:BRK223_SQL_CONNECTION_STRING = "Server=host.docker.internal,$SqlPort;Database=zavalivesitedb;User Id=sqladmin;Password=$SqlAdminPassword;TrustServerCertificate=True;Encrypt=True;Command Timeout=180"

    Invoke-WithRetry -Name 'Start-LiveSite.ps1' -MaxAttempts 2 -DelaySeconds 5 -Action {
        & "$PSScriptRoot\Start-LiveSite.ps1"
        if ($LASTEXITCODE -ne 0) {
            throw "Start-LiveSite.ps1 exited $LASTEXITCODE"
        }
    }
}

Write-Host "`nEnvironment prep complete." -ForegroundColor Green
Write-Host 'Browser: http://localhost:8080' -ForegroundColor DarkGray
Write-Host 'Optional smoke: .\Test-AgentPath.ps1 -WithReset' -ForegroundColor DarkGray
