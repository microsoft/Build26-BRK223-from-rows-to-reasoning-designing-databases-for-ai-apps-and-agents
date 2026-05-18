# Insert-Incident.ps1
# Inserts incident #5012 (the five-feature INSERT — JSON, REGEXP_MATCHES,
# FOR JSON PATH, AI_GENERATE_EMBEDDINGS, vector type) so the live page
# picks it up on the next Refresh.
#
# Sister script: Reset-Incident.ps1 (clears it back out).

[CmdletBinding()]
param(
    [string]$ServerInstance = 'localhost,14330',
    [string]$Database       = 'zavalivesitedb',
    [string]$User           = 'sqladmin',
    [string]$Password       = 'StrongPassw0rd'
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$sqlsim = Get-Sqlsim
$script = Join-Path $PSScriptRoot 'sqlscripts\05_create_incident.sql'

& $sqlsim -S $ServerInstance -d $Database -U $User -P $Password -i $script -q
