# Reset-Incident.ps1
# Deletes incident #5012 so the live page goes back to "No active incidents".
# Run before each demo rehearsal of Beat 1 (insert -> Refresh -> row appears).

[CmdletBinding()]
param(
    [int]$IncidentId = 5012,
    [string]$ServerInstance = 'localhost,14330',
    [string]$Database       = 'zavalivesitedb',
    [string]$User           = 'sqladmin',
    [string]$Password       = 'StrongPassw0rd'
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$sqlsim = Get-Sqlsim
$sql    = "DELETE FROM dbo.Incident WHERE IncidentId = $IncidentId; SELECT COUNT(*) AS Remaining FROM dbo.Incident WHERE IncidentId = $IncidentId;"

& $sqlsim -S $ServerInstance -d $Database -U $User -P $Password -Q $sql -q
