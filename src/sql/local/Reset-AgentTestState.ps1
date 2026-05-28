<#
.SYNOPSIS
    One-command reset for manual agent testing in VS Code.

.DESCRIPTION
    Rewinds the local demo state, re-inserts incident #5012, and verifies
    the incident is present with no mitigation yet. This is the fastest way
    to get back to a clean "ready to test the agent" state.

.PARAMETER Server
    SQL server endpoint. Default: localhost,14330.

.PARAMETER Database
    Database name. Default: zavalivesitedb.

.PARAMETER User
    SQL login used by helper scripts. Default: sqladmin.

.PARAMETER Credential
    Optional SQL credential. The username is ignored; only the password is
    used. If omitted, falls back to $env:BRK223_SQLADMIN_PASSWORD.

.EXAMPLE
    .\Reset-AgentTestState.ps1

.EXAMPLE
    $cred = Get-Credential -UserName sqladmin -Message 'Enter sqladmin password'
    .\Reset-AgentTestState.ps1 -Credential $cred
#>
[CmdletBinding()]
param(
    [string]$Server   = 'localhost,14330',
    [string]$Database = 'zavalivesitedb',
    [string]$User     = 'sqladmin',
    [System.Management.Automation.PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'

$passwordText = if ($null -ne $Credential) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
} else {
    $env:BRK223_SQLADMIN_PASSWORD
}

if ([string]::IsNullOrWhiteSpace($passwordText)) {
    throw 'Password required. Pass -Credential or set $env:BRK223_SQLADMIN_PASSWORD.'
}

Write-Host '=== Reset-AgentTestState ===' -ForegroundColor Cyan
Write-Host "Server: $Server  Database: $Database  User: $User" -ForegroundColor DarkGray

# 1) Rewind to pre-Beat-1 state (removes incident #5012, clears stage changes).
& "$PSScriptRoot\Reset-ForBeat2.ps1" -Server $Server -User $User -Password $passwordText
if ($LASTEXITCODE -ne 0) {
    throw "Reset-ForBeat2.ps1 exited $LASTEXITCODE"
}

# 2) Recreate incident #5012 with baseline payload/tags and no mitigation.
& "$PSScriptRoot\Insert-Incident.ps1" -ServerInstance $Server -Database $Database -User $User -Password $passwordText
if ($LASTEXITCODE -ne 0) {
    throw "Insert-Incident.ps1 exited $LASTEXITCODE"
}

# 3) Verify state: incident exists and ProposedMitigation is empty/null.
. (Join-Path $PSScriptRoot 'Common.ps1')
$query = @"
SET NOCOUNT ON;
SELECT
    IncidentId,
    Status,
    CASE
        WHEN ProposedMitigation IS NULL THEN 0
        WHEN TRY_CAST(ProposedMitigation AS nvarchar(max)) = N'{}' THEN 0
        ELSE 1
    END AS has_mitigation
FROM dbo.Incident
WHERE IncidentId = 5012;
"@

Write-Host "`nVerification (incident 5012):" -ForegroundColor Cyan
$result = Invoke-SqlsimQuery -Query $query -Server $Server -Database $Database -User $User -Password $passwordText
$result | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Verification query failed (sqlsim exit $LASTEXITCODE)."
}

Write-Host "`nReady for manual agent test in VS Code:" -ForegroundColor Green
Write-Host '  Prompt: Mitigate incident 5012 @live-site-sql' -ForegroundColor DarkGray
