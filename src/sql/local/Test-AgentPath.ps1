# Test-AgentPath.ps1
# Drives the BRK223 Beat 4 agent path end-to-end via the Copilot CLI:
#
#   Claude Opus 4.7 (cloud, agent/tool router)
#     -> zavalivesite-sql MCP server (DAB at http://localhost:8765/mcp)
#       -> hybrid_search       (vector + JSON over IncidentArchive/Runbook)
#       -> generate_mitigation (calls phi4-mini in-container via Caddy)
#       -> read_records etc.   (to surface the proposed mitigation)
#
# Captures wall-clock so we know whether Beat 4 is doable live or whether
# we lean on Plan B (`Generate-Mitigation.ps1` + browser refresh).
#
# Pre-reqs (verify with Verify-Build.ps1 first):
#   - azsql-zavalivesite container running on host port 14330
#   - ollama + caddy running inside the container
#   - Aspire AppHost running (Start-LiveSite.ps1) -> DAB on :8765
#   - copilot CLI logged in, zavalivesite-sql server registered
#     (`copilot mcp list` must show it)
#
# Notes:
#   - The prompt uses snake_case tool names (hybrid_search, etc.) — that is
#     how DAB exposes stored-proc entities. The agent will route correctly
#     either way, but explicit names cut tokens + reduce the chance of it
#     hallucinating a different tool.
#   - --allow-all-tools is required for non-interactive (-p) mode.
#   - --output-format json gives JSONL we can parse later if we want
#     per-tool-call timings; today we only care about wall-clock.

[CmdletBinding()]
param(
    [int]    $IncidentId = 5012,
    [string] $Model      = 'claude-opus-4.7',
    [string] $McpServer  = 'zavalivesite-sql',

    # If set, transcript + JSONL are written here. Default: per-run file in TEMP.
    [string] $TranscriptPath,

    # When set, just run the prompt — no Reset/Insert pre-step.
    # Default behaviour also skips Reset/Insert so this script is safe to
    # re-run; the operator drives the reset workflow explicitly.
    [switch] $WithReset
)

$ErrorActionPreference = 'Stop'

if (-not $TranscriptPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $TranscriptPath = Join-Path $Env:TEMP "zavalivesite-agent-$stamp.jsonl"
}

# --- 0. Pre-flight ----------------------------------------------------------
Write-Host "[Test-AgentPath] Pre-flight" -ForegroundColor Cyan

# DAB MCP reachable on 8765? (HTTP 406 is the correct MCP-protocol response.)
try {
    $r = Invoke-WebRequest -Uri 'http://localhost:8765/mcp' `
        -UseBasicParsing -TimeoutSec 3 -SkipHttpErrorCheck -ErrorAction Stop
    if ($r.StatusCode -ne 406 -and $r.StatusCode -ne 200) {
        throw "DAB MCP /mcp returned unexpected HTTP $($r.StatusCode)."
    }
    Write-Host "  [ OK ] DAB MCP at http://localhost:8765/mcp (HTTP $($r.StatusCode))" -ForegroundColor Green
} catch {
    throw "DAB MCP not reachable on :8765. Start it with .\Start-LiveSite.ps1 first. ($_)"
}

# Server registered with the CLI?
$mcpList = copilot mcp list 2>&1 | Out-String
if ($mcpList -notmatch [regex]::Escape($McpServer)) {
    throw "MCP server '$McpServer' not registered. Run: copilot mcp add --transport http $McpServer http://localhost:8765/mcp"
}
Write-Host "  [ OK ] MCP server '$McpServer' registered with Copilot CLI" -ForegroundColor Green

# --- 1. Optional reset ------------------------------------------------------
if ($WithReset) {
    Write-Host "[Test-AgentPath] Reset + Insert (-WithReset specified)" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'Reset-Incident.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Reset-Incident.ps1 failed (exit $LASTEXITCODE)." }
    & (Join-Path $PSScriptRoot 'Insert-Incident.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Insert-Incident.ps1 failed (exit $LASTEXITCODE)." }
}

# --- 2. Build the prompt ----------------------------------------------------
# Mirrors the Live-Site SQL Triage SKILL protocol exactly. The on-stage
# version of this same flow has the operator type a 6-word prompt
# ("Mitigate incident 5012") with the SKILL attached via #file: so the
# protocol comes from the SKILL. Here we inline the protocol so the test
# is self-contained and doesn't depend on the chat client resolving the
# file attachment.
$prompt = @"
You are the Live-Site SQL Triage agent investigating production
incident #$IncidentId.

Use ONLY tools from the MCP server '$McpServer'. Do not use built-in
tools, do not run shell commands, do not edit files. Follow this
protocol in order:

1. read_records on the Incident entity, filter IncidentId eq $IncidentId.
   Capture: TenantId, Service, Severity, EngineerNote, Tags
   (errorCode, build, waitType), AlertPayload.

2. hybrid_search with the EngineerNote as Question, the TenantId,
   the errorCode from Tags, topK=3. Read every returned row.

3. For each runbook recommendation, validate it against current state.
   Diagnostics in this server are dx_index_exists, dx_resource_pressure,
   and dx_deadlock_recent. Pick which one(s) answer each runbook
   recommendation. At minimum:
     - dx_index_exists for any runbook step that proposes creating
       or rebuilding a specific named index. Pass SchemaName,
       TableName, and the exact IndexName the runbook recommends.
     - dx_resource_pressure once. WindowMinutes=5. This gates whether
       online DDL or large UPDATEs are safe to apply NOW.
     - dx_deadlock_recent once if the symptom involves Msg 1205,
       deadlock, or LCK_M_*. Confirms the symptom is current.

4. generate_mitigation with:
     IncidentId       = $IncidentId
     DiagnosticsJson  = a JSON string aggregating every diagnostic row
                        you collected in step 3, keyed by tool name:
                        {
                          "dx_index_exists":      { ... full row ... },
                          "dx_resource_pressure": { ... full row ... },
                          "dx_deadlock_recent":   { ... full row ... }
                        }
   The proc folds DiagnosticsJson into the in-database model prompt
   as ground truth and UPDATEs dbo.Incident.ProposedMitigation.

5. read_records on the Incident entity again to confirm
   ProposedMitigation is populated and Status is 'mitigating'.

6. Report back, in this order:
     - the incident summary (one sentence),
     - which diagnostics you ran and what each finding was,
     - how those findings shaped the plan vs the raw runbook text,
     - the top 1-2 hybrid_search matches with their ids and distances,
     - the proposed mitigation that was written.

Be concise. No code blocks. No file edits. Cite incident ids and
runbook ids inline.
"@

# --- 3. Invoke -------------------------------------------------------------
Write-Host "[Test-AgentPath] Invoking copilot --model $Model" -ForegroundColor Cyan
Write-Host "  Transcript: $TranscriptPath" -ForegroundColor DarkGray

$sw = [Diagnostics.Stopwatch]::StartNew()
$exit = 0
try {
    copilot -p $prompt `
        --model $Model `
        --allow-all-tools `
        --output-format json `
        --no-color 2>&1 |
        Tee-Object -FilePath $TranscriptPath
    $exit = $LASTEXITCODE
} finally {
    $sw.Stop()
}

# --- 4. Report -------------------------------------------------------------
$secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
if ($exit -eq 0) {
    Write-Host ("AGENT PATH (incident #{0}): {1}s  [exit 0]" -f $IncidentId, $secs) -ForegroundColor Green
} else {
    Write-Host ("AGENT PATH (incident #{0}): {1}s  [exit {2}] FAILED" -f $IncidentId, $secs, $exit) -ForegroundColor Red
}
Write-Host ("Transcript: {0}" -f $TranscriptPath) -ForegroundColor DarkGray
Write-Host ("=" * 60) -ForegroundColor DarkGray

exit $exit
