<#
.SYNOPSIS
    Pulls and runs a SQL Server / Azure SQL container. No SQL connectivity test.

.DESCRIPTION
    1. Verifies docker is installed and resolves the image to pull.
    2. If the image is hosted on an *.azurecr.io registry, performs ACR login
       via the current `az` token (`az login` required, AcrPull on the registry
       required). Other registries (e.g. mcr.microsoft.com) need no auth.
    3. Pulls the image.
    4. Removes any existing container named -ContainerName.
    5. Runs the container detached on -Port (default 1433).

    Use Test-AzureSqlConnection.ps1 separately to validate SQL is up.

.PARAMETER Image
    Full image reference. Resolution order:
      1. -Image parameter value if non-empty
      2. $env:BRK223_SQL_IMAGE if set
      3. Error out (no built-in default — see notes below)

    Examples:
      -Image 'mcr.microsoft.com/mssql/server:2025-latest'
            -Image '<private-preview-image-from-session-owner>'
    Or set $env:BRK223_SQL_IMAGE once for the session.

    The original BRK223 demo was authored against an Azure SQL preview image
    hosted in a private Microsoft ACR ('sqlbuilds.azurecr.io'). If you do not
    have access to that registry, use the public SQL Server 2025 image
    ('mcr.microsoft.com/mssql/server:2025-latest') — see the BRK223 README
    for the SQL-2025-vs-Azure-SQL-preview notes.

.PARAMETER ContainerName
    Docker container name. Default: azsql-zavalivesite.

.PARAMETER Port
    Host port to bind 1433 to. Default: 1433.

.PARAMETER SaPassword
    SA password for the container.
    Default: value of $env:BRK223_SA_PASSWORD. Required.

.PARAMETER Gpu
    GPU mode for the Ollama-in-container path. One of:
      auto (default) — probe the host with `nvidia-smi`. If a GPU is detected,
                        behave like `on`; otherwise behave like `off`.
      on             — pass `--gpus all` to docker run. If GPU init fails,
                        automatically fall back to CPU with a loud warning.
      off            — never request a GPU. Ollama runs CPU-only.
    Requires Docker Desktop with WSL2 GPU support and nvidia-container-toolkit
    in the WSL distro when `on` (or `auto` with a GPU detected).

.EXAMPLE
    $env:BRK223_SQL_IMAGE = 'mcr.microsoft.com/mssql/server:2025-latest'
    .\Start-AzureSqlContainer.ps1

.EXAMPLE
    # Force CPU even on a GPU laptop (e.g. to baseline timings):
    .\Start-AzureSqlContainer.ps1 -Gpu off

.EXAMPLE
    # Force GPU and fail loudly if prereqs are missing (still falls back to CPU):
    .\Start-AzureSqlContainer.ps1 -Gpu on
#>
[CmdletBinding()]
param(
    [string]$Image = '',
    [string]$ContainerName = 'azsql-zavalivesite',
    [int]$Port = 1433,
    [string]$SaPassword = $env:BRK223_SA_PASSWORD,
    [ValidateSet('auto','on','off')]
    [string]$Gpu = 'auto'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($SaPassword)) {
    throw 'SaPassword required. Pass -SaPassword or set $env:BRK223_SA_PASSWORD.'
}

# --- Resolve image (param > env var > error) ---------------------------------
if (-not $Image) { $Image = $env:BRK223_SQL_IMAGE }
if (-not $Image) {
    throw @"
No SQL image specified. Pass -Image or set `$env:BRK223_SQL_IMAGE.
Examples:
  -Image 'mcr.microsoft.com/mssql/server:2025-latest'              # public, no auth
  -Image 'sqlbuilds.azurecr.io/mssql-p-adhoc/.../developer-edition:<tag>'   # private Microsoft ACR
See the BRK223 README for the differences between the Azure SQL preview
container and the public SQL Server 2025 container.
"@
}

# --- Decide whether ACR login is required ------------------------------------
$registry = ($Image -split '/', 2)[0]
$needsAcrLogin = $registry -like '*.azurecr.io'

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' not found in PATH."
    }
}

function Initialize-Docker {
    # 1) docker on PATH?
    $cmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $cmd) {
        # 2) Try the standard Docker Desktop location and add to PATH for this session.
        $candidates = @(
            "$Env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
            "${Env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe"
        )
        $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if (-not $found) {
            throw "Docker not found. Install Docker Desktop ('winget install Docker.DockerDesktop') and re-run."
        }
        $Env:Path = (Split-Path $found) + ';' + $Env:Path
    }

    # 3) Engine running? `docker info` exits non-zero when daemon is unreachable.
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { return }

    # 4) Start Docker Desktop and wait.
    $desktop = @(
        "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${Env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $desktop) { throw "Docker engine not running and Docker Desktop.exe not found." }

    Write-Host "Docker engine not running. Launching Docker Desktop..." -ForegroundColor Yellow
    Start-Process -FilePath $desktop | Out-Null

    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker engine is ready." -ForegroundColor Green
            return
        }
    }
    throw "Docker Desktop did not become ready within 3 minutes."
}

Write-Host "=== Pre-flight checks ===" -ForegroundColor Cyan
Initialize-Docker
Write-Host "docker : $((docker --version))"

if ($needsAcrLogin) {
    Assert-Command az
    Write-Host "az     : $((az version --output tsv --query '\"azure-cli\"' 2>$null))"

    Write-Host "`n=== Verify az login ===" -ForegroundColor Cyan
    $acct = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $acct) { throw "Not signed in to Azure. Run 'az login' first." }
    Write-Host ("Subscription: {0} ({1})" -f $acct.name, $acct.id)
    Write-Host ("User        : {0}" -f $acct.user.name)

    Write-Host "`n=== ACR login via access token ===" -ForegroundColor Cyan
    $acrName   = ($registry -split '\.')[0]
    $tokenJson = az acr login -n $acrName --expose-token --output json 2>$null | ConvertFrom-Json
    if (-not $tokenJson -or -not $tokenJson.accessToken) {
        throw "Failed to obtain ACR access token for '$acrName'. Ensure your account has AcrPull on that registry."
    }
    $tokenJson.accessToken | docker login $registry --username '00000000-0000-0000-0000-000000000000' --password-stdin | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "docker login to $registry failed." }
} else {
    Write-Host "Registry '$registry' is public — skipping ACR / az login." -ForegroundColor DarkGray
}

Write-Host "`n=== Pulling image ===" -ForegroundColor Cyan
Write-Host "Image: $Image"
docker pull $Image | Out-Host
if ($LASTEXITCODE -ne 0) { throw "docker pull failed." }

$existing = docker ps -a --filter "name=^/$ContainerName$" --format '{{.ID}}'
if ($existing) {
    Write-Host "`nRemoving existing container '$ContainerName' ($existing)..." -ForegroundColor Yellow
    docker rm -f $ContainerName | Out-Host
}

Write-Host "`n=== Running container '$ContainerName' on port $Port ===" -ForegroundColor Cyan
$baseRunArgs = @(
    'run','-d',
    '--name', $ContainerName,
    '-p', "$Port`:1433",
    '-e', 'ACCEPT_EULA=y',
    '-e', "MSSQL_SA_PASSWORD=$SaPassword"
)

# Resolve -Gpu auto by probing the host for an NVIDIA GPU.
$useGpu = $false
switch ($Gpu) {
    'on'  { $useGpu = $true }
    'off' { $useGpu = $false }
    'auto' {
        $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($nvSmi) {
            $gpuList = & nvidia-smi --query-gpu=name --format=csv,noheader 2>$null
            if ($LASTEXITCODE -eq 0 -and $gpuList) {
                $first = ($gpuList -split "`n" | Where-Object { $_ } | Select-Object -First 1).Trim()
                Write-Host "GPU : auto-detected NVIDIA GPU on host ($first) — using --gpus all" -ForegroundColor Green
                $useGpu = $true
            } else {
                Write-Host "GPU : auto — nvidia-smi present but reported no GPU. Running CPU-only." -ForegroundColor DarkGray
            }
        } else {
            Write-Host "GPU : auto — no nvidia-smi on host. Running CPU-only. (Pass -Gpu on to force.)" -ForegroundColor DarkGray
        }
    }
}

$gpuFellBack = $false
$runSucceeded = $false

if ($useGpu) {
    if ($Gpu -eq 'on') {
        Write-Host "GPU : forced on — attempting --gpus all" -ForegroundColor Green
    }
    $gpuRunArgs = $baseRunArgs + @('--gpus','all', $Image)
    # Capture stderr so we can show why GPU init failed if it does.
    $gpuStderrFile = [IO.Path]::GetTempFileName()
    try {
        & docker @gpuRunArgs 2> $gpuStderrFile | Out-Host
        if ($LASTEXITCODE -eq 0) {
            $runSucceeded = $true
        } else {
            $gpuErr = (Get-Content $gpuStderrFile -Raw)
            Write-Host ""
            Write-Host "*** GPU launch FAILED — falling back to CPU so the demo can still run. ***" -ForegroundColor Yellow
            Write-Host "    Docker stderr:" -ForegroundColor Yellow
            if ($gpuErr) { $gpuErr.TrimEnd() -split "`n" | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow } }
            Write-Host "    Common causes:" -ForegroundColor Yellow
            Write-Host "      * nvidia-container-toolkit not installed in WSL distro" -ForegroundColor Yellow
            Write-Host "      * Docker Desktop GPU support disabled or restart required" -ForegroundColor Yellow
            Write-Host "      * Host NVIDIA driver missing or too old" -ForegroundColor Yellow
            Write-Host "    Verify with: docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi" -ForegroundColor Yellow
            # Clean up any half-created container before retrying.
            docker rm -f $ContainerName 2>$null | Out-Null
            $gpuFellBack = $true
        }
    } finally {
        Remove-Item $gpuStderrFile -ErrorAction SilentlyContinue
    }
}

if (-not $runSucceeded) {
    $mode = if ($gpuFellBack) { 'CPU (GPU fallback)' } else { 'CPU' }
    if (-not $useGpu) {
        Write-Host "GPU : disabled — running on $mode. Ollama will run on CPU." -ForegroundColor DarkGray
    }
    $cpuRunArgs = $baseRunArgs + @($Image)
    & docker @cpuRunArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "docker run failed." }
    $runSucceeded = $true
}

if ($gpuFellBack) {
    Write-Host ""
    Write-Host "NOTE: container is up but Ollama is on CPU. Fix the GPU prereqs and re-run with -Gpu on before stage." -ForegroundColor Yellow
}

Write-Host "`nContainer '$ContainerName' started on localhost,$Port (sa / $SaPassword)." -ForegroundColor Green
Write-Host "Next: .\Test-AzureSqlConnection.ps1 -Port $Port -SaPassword $SaPassword"
Write-Host "Stop: docker rm -f $ContainerName"
