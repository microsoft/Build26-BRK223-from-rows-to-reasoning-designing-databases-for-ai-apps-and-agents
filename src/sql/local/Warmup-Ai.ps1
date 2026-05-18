<#
.SYNOPSIS
    Curtain-up: pre-warm Ollama models so the first on-stage call is instant.

.DESCRIPTION
    Beat 4 calls phi4-mini exactly once on stage. If the model isn't already
    resident, the first call costs ~80s (mmap weights, allocate KV cache).
    Warm calls are ~15s. This script issues one cheap throwaway chat completion
    against phi4-mini AND one embedding call against mxbai-embed-large so both
    models are loaded and KV-warm before doors open.

    Combined with OLLAMA_KEEP_ALIVE=-1 (set in 03-start-services.sh by
    Prepare-AiContainer.ps1), the models stay resident for the whole talk.

    Run AFTER Prepare-AiContainer.ps1 + deploy-prestage.ps1, ~5 min before
    doors. Re-run any time you've been idle > ~10 min during rehearsal.

.PARAMETER ContainerName
    Docker container name. Default: azsql-zavalivesite.

.PARAMETER ChatModel
    Ollama chat model. Default: phi4-mini.

.PARAMETER EmbeddingModel
    Ollama embedding model. Default: mxbai-embed-large.

.EXAMPLE
    .\Warmup-Ai.ps1
#>
[CmdletBinding()]
param(
    [string]$ContainerName  = 'azsql-zavalivesite',
    [string]$ChatModel      = 'phi4-mini',
    [string]$EmbeddingModel = 'mxbai-embed-large'
)

$ErrorActionPreference = 'Stop'

function Get-Docker {
    $cmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$Env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${Env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe"
    )
    $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $found) { throw "Docker not found." }
    return $found
}

$docker = Get-Docker

$state = & $docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
if ($LASTEXITCODE -ne 0 -or $state -ne 'true') {
    throw "Container '$ContainerName' is not running."
}

# ---- Chat warmup (the one that matters) ----
Write-Host "Warming chat model ($ChatModel) — first time can take ~80s..." -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
$chatBody = @{
    model      = $ChatModel
    messages   = @(@{ role = 'user'; content = 'hi' })
    max_tokens = 1
    stream     = $false
} | ConvertTo-Json -Compress -Depth 5

# Escape single quotes for sh -c
$chatBodyEsc = $chatBody -replace "'", "'\''"
$chatCmd = "curl -fsSk -X POST -H 'Content-Type: application/json' -d '$chatBodyEsc' https://localhost:8444/v1/chat/completions -o /dev/null -w 'HTTP %{http_code}  %{time_total}s\n'"
$chatResult = & $docker exec -u root $ContainerName sh -c $chatCmd
$sw.Stop()
Write-Host "  chat:  $chatResult  (wall $([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Green

# ---- Embedding warmup ----
Write-Host "Warming embedding model ($EmbeddingModel)..." -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
$embBody = @{ model = $EmbeddingModel; input = 'warm' } | ConvertTo-Json -Compress
$embBodyEsc = $embBody -replace "'", "'\''"
$embCmd = "curl -fsSk -X POST -H 'Content-Type: application/json' -d '$embBodyEsc' https://localhost:8444/v1/embeddings -o /dev/null -w 'HTTP %{http_code}  %{time_total}s\n'"
$embResult = & $docker exec -u root $ContainerName sh -c $embCmd
$sw.Stop()
Write-Host "  embed: $embResult  (wall $([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Green

Write-Host ""
Write-Host "Both models resident. KEEP_ALIVE=-1 will hold them for the whole session." -ForegroundColor Green
