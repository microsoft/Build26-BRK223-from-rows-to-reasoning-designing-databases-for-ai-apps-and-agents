# Generate-Mitigation.ps1
# Smoke-test wrapper that invokes dbo.usp_GenerateMitigation for incident #5012.
# This is the same proc the Beat 4 MCP `GenerateMitigation` tool calls; useful
# for rehearsal so you don't have to drive Copilot Chat just to light up the
# mitigation card on the live page.
#
# Pipeline inside the proc:
#   1. AI_GENERATE_EMBEDDINGS(EngineerNote)   -> mxbai-embed-large via OllamaMxbai
#   2. HybridSearch (vector + JSON)           -> top-K IncidentArchive + Runbook
#   3. RAG prompt + sp_invoke_external_rest_endpoint -> phi4 chat
#   4. UPDATE dbo.Incident SET ProposedMitigation = <model output>
#
# After this completes, click Refresh on the website.

[CmdletBinding()]
param(
    [int]$IncidentId        = 5012,
    [string]$ServerInstance = 'localhost,14330',
    [string]$Database       = 'zavalivesitedb',
    [string]$User           = 'sqladmin',
    [string]$Password       = $env:BRK223_SQLADMIN_PASSWORD
)

if ([string]::IsNullOrEmpty($Password)) {
    throw 'Password required. Pass -Password or set $env:BRK223_SQLADMIN_PASSWORD.'
}

. (Join-Path $PSScriptRoot 'Common.ps1')
$sqlsim = Get-Sqlsim
$sql    = "EXEC dbo.usp_GenerateMitigation @IncidentId = $IncidentId;"

& $sqlsim -S $ServerInstance -d $Database -U $User -P $Password -Q $sql -q
