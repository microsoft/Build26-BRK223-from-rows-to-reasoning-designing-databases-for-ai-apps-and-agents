<#
.SYNOPSIS
    One-shot bootstrap for the BRK223 demo on a clean Windows machine.

.DESCRIPTION
    Idempotent. Stands up everything required to run the BRK223 demo from a
    freshly-imaged box (Edge + winget present). Each step probes "is it
    already done?" before doing work, so re-running is safe. Fails loud on
    anything it can't fix automatically. Exit 0 = ready to run
    Verify-Build.ps1 -> Start-LiveSite.ps1 -> demo.

    Pipeline (each step skippable via -Skip* if already known good):

      1. Verify Windows + PowerShell 7.x.
      2. Docker Desktop (winget) + auto-launch the engine and wait.
      3. Node.js LTS (winget OpenJS.NodeJS.LTS).
      4. .NET 10 SDK (winget Microsoft.DotNet.SDK.10).
      5. sqlsim probe (resolved via Get-Sqlsim - PATH, $env:SQLSIM_PATH, or repo dev path).
      6. Azure CLI (winget Microsoft.AzureCLI) + interactive `az login`
         if not already signed in. Only required when -SqlImage points at an
         *.azurecr.io registry; harmless otherwise.
      7. DAB container image pulled
         (mcr.microsoft.com/azure-databases/data-api-builder:2.0.0-rc).
      8. GitHub Copilot CLI (npm i -g @github/copilot) + interactive
         `copilot login` if not already authenticated.
      9. If azsql-zavalivesite doesn't exist, call Start-AzureSqlContainer.ps1
         to pull the SQL image (resolved via -SqlImage or `$env:BRK223_SQL_IMAGE).
         If the image is hosted on an *.azurecr.io registry, that script will
         do an `az acr login --expose-token` first; otherwise it skips the
         `az` step entirely.
     10. Pull / verify Ollama models loaded inside the container
         (Prepare-AiContainer.ps1).
     11. Restore SQL state (deploy-prestage.ps1) if dbo.IncidentArchive is
         empty. Skip if already seeded (~301 rows).
     12. dotnet restore + dotnet build for dotnet/AppHost and dotnet/Web
         so the first Start-LiveSite.ps1 doesn't pay cold-build cost.

    Only one manual step the script CANNOT do is printed at the end:
      - Enable Anthropic Claude Opus 4.7 at
        https://github.com/settings/copilot/features
        (web checkbox tied to your GitHub account; no API to flip it).

.PARAMETER ContainerName
    SQL container name. Default: azsql-zavalivesite.

.PARAMETER SqlPort
    Host port for SQL. Default: 14330 (avoids Windows MSSQLSERVER DAC on 1434).

.PARAMETER SaPassword
    SA password for the container. Default: Password1 (test-only).

.PARAMETER SqlAdminPassword
    Password for the sqladmin login deploy-prestage.ps1 creates.
    Default: StrongPassw0rd.

.PARAMETER SqlImage
    SQL container image to pull. No built-in default. Resolution order:
      1. -SqlImage value if non-empty
      2. $env:BRK223_SQL_IMAGE if set
      3. Script errors out with usage examples.
    Use 'mcr.microsoft.com/mssql/server:2025-latest' for the public SQL
    Server 2025 image, or the private Microsoft 'sqlbuilds.azurecr.io/...'
    image for the Azure SQL preview.

.PARAMETER DabImage
    DAB container image:tag. Default matches dotnet/AppHost/apphost.cs.

.PARAMETER SkipWinget
    Skip all winget install probes (steps 2-5). Use when you've installed the
    tools manually and just want the SQL/AI/dotnet bring-up.

.PARAMETER SkipAi
    Skip step 10 (Prepare-AiContainer.ps1).

.PARAMETER SkipDeploy
    Skip step 11 (deploy-prestage.ps1).

.PARAMETER SkipDotnet
    Skip step 12 (dotnet restore + build).

.PARAMETER Fast
    Convenience flag: implies -SkipWinget -SkipAi -SkipDeploy -SkipDotnet.
    Runs only the cheap probes (steps 1, 6 az session, 7, 9, 10) so you can
    verify a known-good machine is still healthy in a few seconds. Does NOT
    rebuild or change anything. Mutually exclusive with -Force.

.PARAMETER Force
    Tear down and rebuild everything that this script owns. Specifically:
      * Step 7  - re-pull DAB image (docker pull, gets latest of same tag).
      * Step 9  - re-pull SQL image.
      * Step 10 - docker rm -f the container, then recreate via
                  Start-AzureSqlContainer.ps1.
      * Step 11 - re-run Prepare-AiContainer.ps1 unconditionally
                  (reinstalls Ollama + Caddy, re-pulls models, retrusts CA).
      * Step 12 - re-run deploy-prestage.ps1 unconditionally
                  (00_setup.sql drops + recreates zavalivesitedb anyway, ~1-3 min).
      * Step 13 - dotnet build --no-incremental.
    Does NOT touch the OS-level winget installs (Docker / Node / .NET / az / copilot CLI)
    az) - re-running winget on already-installed tools is a no-op and a waste
    of time. If you actually need to upgrade those, use winget upgrade
    manually. Mutually exclusive with -Fast.

.EXAMPLE
    .\Build.ps1
    Idempotent bootstrap from a clean OR warm machine. Skips work where
    probes show the artifact already exists.

.EXAMPLE
    .\Build.ps1 -Fast
    Probes-only sanity check on a machine you know is good. ~10-30 s.

.EXAMPLE
    .\Build.ps1 -Force
    Nuke and rebuild the demo state from scratch (image pulls + container
    recreate + AI reinstall + SQL redeploy + dotnet clean build). Use after
    a corrupted state or a SQL image bump. ~10-15 min.

.EXAMPLE
    .\Build.ps1 -SkipWinget -SkipAi
    Just rebuild the SQL container + redeploy SQL state + warm dotnet build.
#>
[CmdletBinding()]
param(
    [string]$ContainerName    = 'azsql-zavalivesite',
    [int]$SqlPort             = 14330,
    [string]$SaPassword       = 'Password1',
    [string]$SqlAdminPassword = 'StrongPassw0rd',
    [string]$SqlImage         = '',
    [string]$DabImage         = 'mcr.microsoft.com/azure-databases/data-api-builder:2.0.0-rc',
    [switch]$SkipWinget,
    [switch]$SkipAi,
    [switch]$SkipDeploy,
    [switch]$SkipDotnet,
    [switch]$Fast,
    [switch]$Force,
    [ValidateSet('auto','on','off')]
    [string]$Gpu = 'auto'
)

$ErrorActionPreference = 'Stop'
$script:Failed = @()

# --- Resolve SQL image: -SqlImage > $env:BRK223_SQL_IMAGE > error ----------
if (-not $SqlImage) { $SqlImage = $env:BRK223_SQL_IMAGE }
if (-not $SqlImage) {
    throw @"
No SQL image specified. Pass -SqlImage or set `$env:BRK223_SQL_IMAGE.
Examples:
  -SqlImage 'mcr.microsoft.com/mssql/server:2025-latest'                                    # public SQL Server 2025
  -SqlImage 'sqlbuilds.azurecr.io/mssql-p-adhoc/.../developer-edition:<tag>'                # private Azure SQL preview (Microsoft only)
See the BRK223 README for the differences between the two.
"@
}

# Common helpers (Get-Sqlsim, Invoke-SqlsimQuery, Invoke-SqlsimScript, SET preamble).
. (Join-Path $PSScriptRoot 'Common.ps1')

if ($Fast -and $Force) {
    throw '-Fast and -Force are mutually exclusive.'
}
if ($Fast) {
    $SkipWinget = $true
    $SkipAi     = $true
    $SkipDeploy = $true
    $SkipDotnet = $true
    Write-Host '=== Build.ps1 -Fast: probes only, no work will be done ===' -ForegroundColor Cyan
}
if ($Force) {
    Write-Host '=== Build.ps1 -Force: rebuilding container / AI / SQL state / dotnet from scratch ===' -ForegroundColor Yellow
}

function Write-Step  { param($m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Info  { param($m) Write-Host "  [INFO] $m" -ForegroundColor DarkGray }
function Write-Warn2 { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Fail  { param($m) Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failed += $m }

function Refresh-Path {
    $Env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
}

function Test-WingetPackage {
    param([string]$Id)
    # winget list returns 0 with the row when installed, 1 when not.
    $out = winget list --id $Id --exact --accept-source-agreements 2>&1
    return ($LASTEXITCODE -eq 0 -and ($out -join "`n") -match [regex]::Escape($Id))
}

function Install-WingetPackage {
    param([string]$Id, [string]$DisplayName = $Id)
    if (Test-WingetPackage -Id $Id) {
        Write-Ok "$DisplayName already installed (winget id $Id)"
        return $true
    }
    Write-Warn2 "$DisplayName not installed - winget install $Id"
    winget install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Fail "winget install $Id failed (exit $LASTEXITCODE)"; return $false }
    Refresh-Path
    Write-Ok "$DisplayName installed"
    return $true
}

# Refresh PATH so freshly-installed CLIs are visible immediately.
Refresh-Path

# --- 1. Windows + PowerShell 7.x ---------------------------------------------
Write-Step '1. Windows + PowerShell 7.x'
if (-not $IsWindows -and ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.Platform -eq 'Unix')) {
    Write-Fail "Build.ps1 supports Windows only."
} else {
    Write-Ok ("OS    : {0}" -f (Get-CimInstance Win32_OperatingSystem).Caption)
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Fail ("PowerShell 7.x required (running {0}). Install: winget install Microsoft.PowerShell" -f $PSVersionTable.PSVersion)
} else {
    Write-Ok ("pwsh  : {0}" -f $PSVersionTable.PSVersion)
}
if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 2. Docker Desktop -------------------------------------------------------
Write-Step '2. Docker Desktop'
if ($SkipWinget) {
    Write-Info 'SkipWinget set - assuming Docker Desktop already installed.'
} else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail 'winget not on PATH. Install App Installer from the Microsoft Store.'
    } else {
        Install-WingetPackage -Id 'Docker.DockerDesktop' -DisplayName 'Docker Desktop' | Out-Null
    }
}
if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# Make docker visible in this session if it just got installed.
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    $candidate = "$Env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
    if (Test-Path $candidate) { $Env:Path = (Split-Path $candidate) + ';' + $Env:Path }
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
}
if (-not $dockerCmd) {
    Write-Fail 'docker not on PATH after install. Open a new shell and re-run.'
} else {
    docker info *>$null
    if ($LASTEXITCODE -ne 0) {
        $desktop = @(
            "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
            "${Env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
        ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if (-not $desktop) {
            Write-Fail 'Docker engine not running and Docker Desktop.exe not found.'
        } else {
            Write-Warn2 'Docker engine not running - launching Docker Desktop and waiting (up to 5 min)...'
            Write-Warn2 '*** First-run only: a Docker Desktop window may open asking you to accept the license / sign in. Complete it; this script will keep waiting. ***'
            Start-Process -FilePath $desktop | Out-Null
            $deadline = (Get-Date).AddMinutes(5)
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 5
                docker info *>$null
                if ($LASTEXITCODE -eq 0) { break }
            }
            docker info *>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Fail 'Docker Desktop did not become ready within 5 minutes. Finish first-run setup and re-run Build.ps1.'
            } else {
                Write-Ok 'Docker engine ready (auto-started).'
            }
        }
    } else {
        Write-Ok ("docker engine ready ({0})" -f (docker --version))
    }
}
if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 3. Node.js LTS ----------------------------------------------------------
Write-Step '3. Node.js LTS'
if ($SkipWinget) {
    Write-Info 'SkipWinget set - assuming Node.js already installed.'
} else {
    Install-WingetPackage -Id 'OpenJS.NodeJS.LTS' -DisplayName 'Node.js LTS' | Out-Null
}
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Ok ("node {0}" -f (& node --version))
} else {
    Write-Fail 'node not on PATH after install. Open a new shell and re-run.'
}

# --- 4. .NET 10 SDK ----------------------------------------------------------
Write-Step '4. .NET 10 SDK'
if ($SkipWinget) {
    Write-Info 'SkipWinget set - assuming .NET 10 SDK already installed.'
} else {
    Install-WingetPackage -Id 'Microsoft.DotNet.SDK.10' -DisplayName '.NET 10 SDK' | Out-Null
}
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    $sdks = (& dotnet --list-sdks) -split "`r?`n" | Where-Object { $_ -match '^10\.' }
    if ($sdks) { Write-Ok ("dotnet SDK present: {0}" -f ($sdks -join '; ')) }
    else       { Write-Fail 'dotnet on PATH but no 10.x SDK installed.' }
} else {
    Write-Fail 'dotnet not on PATH after install. Open a new shell and re-run.'
}

# --- 5. sqlsim probe ---------------------------------------------------------
Write-Step '5. sqlsim'
try {
    $sqlsimPath = Get-Sqlsim
    Write-Ok "sqlsim: $sqlsimPath"
} catch {
    Write-Fail $_.Exception.Message
}

if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 6. Azure CLI + az login -------------------------------------------------
Write-Step '6. Azure CLI + az login (needed for ACR pull of the SQL image)'
if ($SkipWinget) {
    Write-Info 'SkipWinget set - assuming Azure CLI already installed.'
} else {
    Install-WingetPackage -Id 'Microsoft.AzureCLI' -DisplayName 'Azure CLI' | Out-Null
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Fail 'az not on PATH after install. Open a new shell and re-run.'
} else {
    $acct = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $acct) {
        Write-Warn2 'Not signed in to Azure - launching `az login` (browser device flow). Complete sign-in, then this script continues.'
        az login --output none
        $acct = az account show --output json 2>$null | ConvertFrom-Json
    }
    if (-not $acct) { Write-Fail 'az login did not produce an authenticated session.' }
    else            { Write-Ok ("az logged in: {0} ({1})" -f $acct.user.name, $acct.name) }
}
if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 7. DAB container image --------------------------------------------------
Write-Step "7. DAB container image ($DabImage)"
$dabPresent = (docker image inspect $DabImage 2>$null | Out-String).Trim()
if ($dabPresent -and -not $Force) {
    Write-Ok "DAB image already pulled."
} else {
    if ($Force -and $dabPresent) { Write-Warn2 '-Force: re-pulling DAB image to refresh tag ...' }
    else                         { Write-Warn2 "Pulling $DabImage ..." }
    docker pull $DabImage | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Fail "docker pull $DabImage failed." }
    else { Write-Ok 'DAB image pulled.' }
}

# --- 8. GitHub Copilot CLI + copilot login -----------------------------------
Write-Step '8. GitHub Copilot CLI + copilot login'
$copilotPath = "$Env:APPDATA\npm\copilot.cmd"
if (-not (Test-Path $copilotPath)) {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Fail 'npm not on PATH; cannot install copilot CLI.'
    } else {
        Write-Warn2 'Installing @github/copilot globally via npm ...'
        & npm install -g '@github/copilot' | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Fail 'npm i -g @github/copilot failed.' }
        elseif (-not (Test-Path $copilotPath)) { Write-Fail 'copilot CLI install reported success but copilot.cmd not found.' }
    }
}
if ((Test-Path $copilotPath) -and $script:Failed.Count -eq 0) {
    Write-Ok ("copilot CLI present ({0})" -f $copilotPath)
    # Probe auth: a tiny prompt that needs a token to work.
    $authProbe = & $copilotPath -p 'PONG only' --allow-all-tools --output-format text 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $authProbe -match 'login|unauthor|forbidden|401|403') {
        Write-Warn2 'copilot CLI not authenticated - launching `copilot login` (device flow, browser). Complete sign-in, then this script continues.'
        & $copilotPath login
        if ($LASTEXITCODE -ne 0) { Write-Fail 'copilot login exited non-zero.' }
        else { Write-Ok 'copilot login completed.' }
    } else {
        Write-Ok 'copilot CLI authenticated.'
    }
}

# --- 9. Azure SQL container image -------------------------------------------
Write-Step "9. Azure SQL container image ($SqlImage)"
$sqlImagePresent = (docker image inspect $SqlImage 2>$null | Out-String).Trim()
if ($sqlImagePresent -and -not $Force) {
    Write-Ok 'SQL image already pulled.'
} elseif ($Force -and $sqlImagePresent) {
    Write-Warn2 '-Force: Start-AzureSqlContainer.ps1 will re-pull the SQL image in step 10 (always pulls).'
} else {
    Write-Info 'SQL image not local; Start-AzureSqlContainer.ps1 will pull it via ACR token in step 10.'
}

if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 10. azsql-zavalivesite container ---------------------------------------------
Write-Step "10. Container '$ContainerName' on port $SqlPort"
$exists = docker ps -a --filter "name=^/$ContainerName$" --format '{{.ID}}'
if ($exists -and $Force) {
    Write-Warn2 "-Force: docker rm -f $ContainerName (will recreate) ..."
    docker rm -f $ContainerName | Out-Null
    $exists = $null
}
if ($exists) {
    $running = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
    if ($running -ne 'true') {
        Write-Warn2 "Container exists but stopped - docker start ..."
        docker start $ContainerName | Out-Null
        Start-Sleep -Seconds 3
    }
    Write-Ok "Container '$ContainerName' running (skipping create)."
} else {
    Write-Warn2 "Container '$ContainerName' missing - calling Start-AzureSqlContainer.ps1 ..."
    $startScript = Join-Path $PSScriptRoot 'Start-AzureSqlContainer.ps1'
    if (-not (Test-Path $startScript)) { Write-Fail "Missing $startScript" }
    else {
        & $startScript -ContainerName $ContainerName -Port $SqlPort -SaPassword $SaPassword -Image $SqlImage -Gpu $Gpu
        if ($LASTEXITCODE -ne 0) { Write-Fail "Start-AzureSqlContainer.ps1 exited $LASTEXITCODE" }
        else { Write-Ok 'Container created + started.' }
    }
}

# Wait for SQL to answer.
if ($script:Failed.Count -eq 0) {
    Write-Info 'Waiting for SQL to respond (up to 90s) ...'
    $deadline = (Get-Date).AddSeconds(90); $ready = $false
    while ((Get-Date) -lt $deadline) {
        Invoke-SqlsimQuery -Query 'SELECT 1' -Server "localhost,$SqlPort" -User sa -Password $SaPassword -Quiet *>$null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 3
    }
    if ($ready) { Write-Ok "SQL responding on localhost,$SqlPort" }
    else        { Write-Fail "SQL did not respond on localhost,$SqlPort within 90s." }
}

if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 11. Ollama + Caddy + models inside container ----------------------------
if ($SkipAi) {
    Write-Step '11. Ollama + Caddy + models -- SKIPPED (-SkipAi)'
} else {
    Write-Step "11. Ollama + Caddy + models inside '$ContainerName'"
    # Probe both processes; if both up AND both models present, skip Prepare-AiContainer.
    $ollamaPid = (docker exec -u root $ContainerName pgrep -f 'ollama serve' 2>$null) -join ''
    $caddyPid  = (docker exec -u root $ContainerName pgrep -f 'caddy run'    2>$null) -join ''
    $models = ''
    if ($ollamaPid) {
        $models = (docker exec -u root $ContainerName sh -c "curl -s http://localhost:11434/api/tags" 2>$null) -as [string]
    }
    $hasEmbed = $models -match 'mxbai-embed-large'
    $hasChat  = $models -match 'phi4-mini'

    if ($ollamaPid -and $caddyPid -and $hasEmbed -and $hasChat -and -not $Force) {
        Write-Ok "Ollama PID $ollamaPid, Caddy PID $caddyPid, both models present - skipping Prepare-AiContainer.ps1"
    } else {
        if ($Force) {
            Write-Warn2 '-Force: re-running Prepare-AiContainer.ps1 unconditionally ...'
        } else {
            Write-Warn2 ("Need to (re)prepare AI container - ollama:{0} caddy:{1} mxbai:{2} phi4:{3}" -f `
                [bool]$ollamaPid, [bool]$caddyPid, $hasEmbed, $hasChat)
        }
        $prep = Join-Path $PSScriptRoot 'Prepare-AiContainer.ps1'
        if (-not (Test-Path $prep)) { Write-Fail "Missing $prep" }
        else {
            & $prep -ContainerName $ContainerName
            if ($LASTEXITCODE -ne 0) { Write-Fail "Prepare-AiContainer.ps1 exited $LASTEXITCODE" }
            else { Write-Ok 'AI container prepared.' }
        }
    }
}

if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 12. SQL state (deploy-prestage.ps1) -------------------------------------
if ($SkipDeploy) {
    Write-Step '12. SQL state -- SKIPPED (-SkipDeploy)'
} else {
    Write-Step "12. SQL state (zavalivesitedb schema + corpus on localhost,$SqlPort)"
    # Probe: does zavalivesitedb.dbo.IncidentArchive already have ~301 rows?
    # sqlsim -q -Q with a grep-friendly marker; parse the count from stdout.
    $rows = 0
    try {
        $probeOut = Invoke-SqlsimQuery -Query 'SET NOCOUNT ON; SELECT CONCAT(''ROWCOUNT='', COUNT(*)) FROM dbo.IncidentArchive;' `
                                       -Server "localhost,$SqlPort" -User sa -Password $SaPassword -Database zavalivesitedb -Quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            $match = ($probeOut | Select-String -Pattern 'ROWCOUNT=(\d+)' | Select-Object -First 1)
            if ($match) { [int]::TryParse($match.Matches[0].Groups[1].Value, [ref]$rows) | Out-Null }
        }
    } catch {
        # Database may not exist yet - $rows stays 0, deploy will run.
    }
    if ($rows -ge 100 -and -not $Force) {
        Write-Ok "zavalivesitedb.dbo.IncidentArchive already has $rows rows - skipping deploy-prestage.ps1"
    } else {
        if ($Force -and $rows -ge 100) {
            Write-Warn2 "-Force: re-running deploy-prestage.ps1 (will drop + recreate zavalivesitedb, ~1-3 min) ..."
        } else {
            Write-Warn2 "zavalivesitedb.dbo.IncidentArchive has $rows rows - running deploy-prestage.ps1 (this takes 1-3 min for embeddings) ..."
        }
        $deploy = Join-Path $PSScriptRoot 'deploy-prestage.ps1'
        if (-not (Test-Path $deploy)) { Write-Fail "Missing $deploy" }
        else {
            # Retry wrapper: AI_GENERATE_EMBEDDINGS in 02_seed_corpus.sql has no
            # per-row TRY/CATCH, so a single transient embedding flake aborts the
            # 500-row seed loop. deploy-prestage.ps1 is idempotent (00_setup.sql
            # drops + recreates zavalivesitedb), so retrying is safe.
            # deploy-prestage.ps1 'throw's on failure (not exit), so use try/catch
            # to catch the propagated exception and check $LASTEXITCODE.
            $maxAttempts = 3
            $deployOk = $false
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                $caught = $null
                try {
                    & $deploy -Server "localhost,$SqlPort" -SaPassword $SaPassword -SqlAdminPassword $SqlAdminPassword
                } catch {
                    $caught = $_
                }
                if (-not $caught -and $LASTEXITCODE -eq 0) {
                    Write-Ok 'SQL state deployed.'
                    $deployOk = $true
                    break
                }
                $reason = if ($caught) { $caught.Exception.Message } else { "exit $LASTEXITCODE" }
                if ($attempt -lt $maxAttempts) {
                    Write-Warn2 "deploy-prestage.ps1 failed on attempt $attempt/$maxAttempts ($reason) - retrying in 10s ..."
                    Start-Sleep -Seconds 10
                } else {
                    Write-Fail "deploy-prestage.ps1 failed after $maxAttempts attempts ($reason)"
                }
            }
            if (-not $deployOk -and $script:Failed.Count -eq 0) {
                Write-Fail "deploy-prestage.ps1 did not succeed."
            }
        }
    }
}

if ($script:Failed.Count -gt 0) { Write-Host "`nRequired check failed. Stopping." -ForegroundColor Red; exit 1 }

# --- 13. dotnet restore + build ---------------------------------------------
if ($SkipDotnet) {
    Write-Step '13. dotnet restore + build -- SKIPPED (-SkipDotnet)'
} else {
    Write-Step '13. dotnet restore + build (warm cache for Start-LiveSite.ps1)'
    $appHostDir = Join-Path $PSScriptRoot 'dotnet\AppHost'
    $webProj    = Join-Path $PSScriptRoot 'dotnet\Web\ZavaLiveSite.Web.csproj'
    if (-not (Test-Path $webProj)) {
        Write-Fail "Web project not found: $webProj"
    } else {
        if ($Force) {
            Write-Info '-Force: dotnet clean + build --no-incremental ZavaLiveSite.Web ...'
            & dotnet clean $webProj -c Debug --nologo -v minimal | Out-Host
            & dotnet build $webProj -c Debug --no-incremental --nologo -v minimal | Out-Host
        } else {
            Write-Info 'dotnet restore + build ZavaLiveSite.Web ...'
            & dotnet build $webProj -c Debug --nologo -v minimal | Out-Host
        }
        if ($LASTEXITCODE -ne 0) { Write-Fail "dotnet build $webProj failed." }
        else { Write-Ok 'ZavaLiveSite.Web built.' }
    }
    # AppHost is a single-file app launched via `dotnet run apphost.cs` - no csproj.
    # Just ensure aspire workload + .NET 10 dotnet-tools restore is happy.
    $toolsManifest = Join-Path $PSScriptRoot 'dotnet\dotnet-tools.json'
    if (Test-Path $toolsManifest) {
        Push-Location (Split-Path $toolsManifest)
        try {
            Write-Info 'dotnet tool restore (aspire CLI etc.) ...'
            & dotnet tool restore --tool-manifest $toolsManifest | Out-Host
            if ($LASTEXITCODE -ne 0) { Write-Warn2 'dotnet tool restore failed (non-fatal; Start-LiveSite uses dotnet run apphost.cs).' }
            else { Write-Ok 'dotnet tools restored.' }
        } finally { Pop-Location }
    }
}

# --- Summary -----------------------------------------------------------------
Write-Host ''
if ($script:Failed.Count -eq 0) {
    Write-Host '=== Build.ps1 succeeded ===' -ForegroundColor Green
    Write-Host ''
    Write-Host 'One manual step the script CANNOT do (web checkbox tied to your GitHub account):' -ForegroundColor Yellow
    Write-Host '  * Enable Anthropic Claude Opus 4.7 at https://github.com/settings/copilot/features'
    Write-Host ''
    Write-Host 'Then:' -ForegroundColor Yellow
    Write-Host '  .\Verify-Build.ps1     # confirm the running stack is healthy (re-run any time after reboot / idle)'
    Write-Host '  .\Start-LiveSite.ps1   # Aspire AppHost: DAB + Blazor WASM'
    Write-Host '  .\Test-AgentPath.ps1   # full Beat-4 dry run (Copilot CLI + Claude Opus 4.7 + DAB MCP)'
    Write-Host ''
    exit 0
} else {
    Write-Host '=== Build.ps1 FAILED ===' -ForegroundColor Red
    foreach ($f in $script:Failed) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
