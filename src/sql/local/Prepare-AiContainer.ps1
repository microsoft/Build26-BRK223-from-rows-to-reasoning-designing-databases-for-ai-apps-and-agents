<#
.SYNOPSIS
    BRK223 prereq: install + start Ollama and Caddy inside the SQL container,
    pull embedding + chat models, trust Caddy CA in SQLPAL.

.DESCRIPTION
    Idempotent wrapper around the validated baseline at c:\bwsql\ollama\container\.
    Run AFTER Start-AzureSqlContainer.ps1, BEFORE deploy-prestage.ps1.

    Steps (per ollama/container/SKILL.md):
      1. Copy install scripts + Caddyfile into container
      2. 01-install-ollama.sh
      3. 02-install-caddy.sh
      4. 03-start-services.sh (initial)
      5. 04-pull-model.sh mxbai-embed-large    (1024-dim embeddings)
      6. 04-pull-model.sh phi4-mini            (chat completions)
      7. 05-trust-caddy-ca.sh
      8. docker restart (so SQLPAL re-reads the CA trust dir)
      9. 03-start-services.sh (services don't auto-start after restart)
     10. End-to-end probe: AI_GENERATE_EMBEDDINGS via OllamaMxbai

.PARAMETER ContainerName
    Docker container name. Default: azsql-zavalivesite.

.PARAMETER SkillFolder
    Folder with the validated install scripts. Default: c:\bwsql\ollama\container.

.PARAMETER EmbeddingModel
    Ollama embedding model to pull. Default: mxbai-embed-large.

.PARAMETER ChatModel
    Ollama chat model to pull. Default: phi4-mini.

.PARAMETER SkipRestart
    Skip the docker restart step (only safe if Caddy CA was already trusted in
    a previous run AND sqlservr has been started since then).

.EXAMPLE
    .\Prepare-AiContainer.ps1
#>
[CmdletBinding()]
param(
    [string]$ContainerName  = 'azsql-zavalivesite',
    [string]$SkillFolder    = '',  # defaults to $PSScriptRoot\skills\container if empty
    [string]$EmbeddingModel = 'mxbai-embed-large',
    [string]$ChatModel      = 'phi4-mini',
    [switch]$SkipRestart
)

# Resolve skill folder default
if (-not $SkillFolder) {
    $SkillFolder = Join-Path $PSScriptRoot 'skills\container'
}

$ErrorActionPreference = 'Stop'

function Get-Docker {
    $cmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$Env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${Env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe"
    )
    $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $found) { throw "Docker not found. Install Docker Desktop or run Start-AzureSqlContainer.ps1 first." }
    return $found
}

$docker = Get-Docker
Write-Host "Using docker: $docker"

# Verify container is running.
$state = & $docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
if ($LASTEXITCODE -ne 0 -or $state -ne 'true') {
    throw "Container '$ContainerName' is not running. Run .\Start-AzureSqlContainer.ps1 first."
}

# Required SKILL artifacts.
$artifacts = @(
    '01-install-ollama.sh',
    '02-install-caddy.sh',
    '03-start-services.sh',
    '04-pull-model.sh',
    '05-trust-caddy-ca.sh',
    'Caddyfile'
)
foreach ($f in $artifacts) {
    $p = Join-Path $SkillFolder $f
    if (-not (Test-Path $p)) { throw "Missing SKILL artifact: $p" }
}

function Invoke-InContainer {
    param([string]$Description, [string[]]$Cmd)
    Write-Host ""
    Write-Host "=== $Description ===" -ForegroundColor Cyan
    & $docker exec -u root $ContainerName @Cmd
    if ($LASTEXITCODE -ne 0) { throw "Step failed: $Description (exit $LASTEXITCODE)" }
}

function Copy-IntoContainer {
    param([string]$Local, [string]$Remote)
    & $docker cp $Local "${ContainerName}:$Remote" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker cp failed: $Local -> $Remote" }
}

# ---- Step 1: copy SKILL artifacts into /tmp/ai-prereq/ ----
Write-Host ""
Write-Host "=== Step 1: copy SKILL artifacts into container ===" -ForegroundColor Cyan
& $docker exec -u root $ContainerName mkdir -p /tmp/ai-prereq /etc/caddy | Out-Null
foreach ($f in $artifacts) {
    Copy-IntoContainer -Local (Join-Path $SkillFolder $f) -Remote "/tmp/ai-prereq/$f"
}
Invoke-InContainer 'Step 1b: chmod +x scripts' @('sh','-c','chmod +x /tmp/ai-prereq/*.sh; cp /tmp/ai-prereq/Caddyfile /etc/caddy/Caddyfile')

# ---- Step 2: install ollama (idempotent — script no-ops if already installed) ----
Invoke-InContainer 'Step 2: install Ollama' @('sh','/tmp/ai-prereq/01-install-ollama.sh')

# ---- Step 3: install caddy ----
Invoke-InContainer 'Step 3: install Caddy' @('sh','/tmp/ai-prereq/02-install-caddy.sh')

# ---- Step 4: start services (first time) ----
Invoke-InContainer 'Step 4: start Ollama + Caddy' @('sh','/tmp/ai-prereq/03-start-services.sh')

# ---- Step 5: pull embedding model ----
Invoke-InContainer "Step 5: pull embedding model ($EmbeddingModel)" @('sh','-c',"MODEL=$EmbeddingModel sh /tmp/ai-prereq/04-pull-model.sh")

# ---- Step 6: pull chat model ----
Invoke-InContainer "Step 6: pull chat model ($ChatModel)" @('sh','-c',"MODEL=$ChatModel sh /tmp/ai-prereq/04-pull-model.sh")

# ---- Step 7: trust Caddy CA in SQLPAL ----
Invoke-InContainer 'Step 7: copy Caddy CA into SQLPAL trust dir' @('sh','/tmp/ai-prereq/05-trust-caddy-ca.sh')

# ---- Step 8: docker restart (so sqlservr re-reads the trust dir) ----
if ($SkipRestart) {
    Write-Host ""
    Write-Host "=== Step 8: SKIPPED (-SkipRestart) ===" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "=== Step 8: docker restart $ContainerName ===" -ForegroundColor Cyan
    & $docker restart $ContainerName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker restart failed" }

    # Wait for sqlservr to come back up.
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $log = & $docker logs --tail 20 $ContainerName 2>&1 | Out-String
        if ($log -match 'Recovery is complete' -or $log -match 'SQL Server is now ready for client connections') {
            Write-Host '  sqlservr ready.' -ForegroundColor Green
            break
        }
    }

    # ---- Step 9: re-start services (they don't auto-start after restart) ----
    Invoke-InContainer 'Step 9: re-start Ollama + Caddy after restart' @('sh','/tmp/ai-prereq/03-start-services.sh')
}

# ---- Step 10: smoke-test endpoint visible from inside the container ----
Write-Host ""
Write-Host "=== Step 10: smoke-test https://localhost:8444/v1/models ===" -ForegroundColor Cyan
$probe = & $docker exec -u root $ContainerName sh -c 'curl -fsSk -o /tmp/m.json -w "HTTP %{http_code}\n" https://localhost:8444/v1/models; cat /tmp/m.json'
Write-Host $probe

Write-Host ""
Write-Host "Prereq complete. Now run:" -ForegroundColor Green
Write-Host "  `$env:BRK223_SA_PASSWORD = '<sa pwd>'" -ForegroundColor Green
Write-Host "  `$env:BRK223_SQLADMIN_PASSWORD = '<sqladmin pwd>'" -ForegroundColor Green
Write-Host "  .\deploy-prestage.ps1" -ForegroundColor Green
