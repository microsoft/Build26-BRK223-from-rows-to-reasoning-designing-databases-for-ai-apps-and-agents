<#
.SYNOPSIS
    Lists models available to the logged-in Copilot CLI user.

.DESCRIPTION
    Reads the GitHub OAuth token stored by `copilot login` from Windows
    Credential Manager (target: "copilot-cli/https://github.com:<user>"),
    then calls GET https://api.githubcopilot.com/models with the same
    headers the CLI itself sends.

    Endpoint + header set were derived from the CLI source bundle
    (app.js) — see notes at the bottom of this file.

.PARAMETER User
    GitHub login. Defaults to the value of `lastLoggedInUser` in
    ~/.copilot/config.json.

.PARAMETER Filter
    Optional substring (case-insensitive) to filter model id / name.

.EXAMPLE
    .\List-CopilotModels.ps1
    .\List-CopilotModels.ps1 -Filter claude
    .\List-CopilotModels.ps1 -Filter opus
#>
[CmdletBinding()]
param(
    [string] $User,
    [string] $Filter,
    [switch] $Raw,
    [switch] $All
)

$ErrorActionPreference = 'Stop'

# --- 1. Resolve user --------------------------------------------------------
if (-not $User) {
    $cfgPath = Join-Path $HOME '.copilot\config.json'
    if (-not (Test-Path $cfgPath)) {
        throw "No -User given and $cfgPath not found. Run 'copilot login' first."
    }
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $last = $cfg.lastLoggedInUser
    if ($last -is [string]) { $User = $last }
    elseif ($last -and $last.login) { $User = $last.login; $Host_ = $last.host }
    if (-not $User) { throw "lastLoggedInUser missing from $cfgPath." }
}

if (-not $Host_) { $Host_ = 'https://github.com' }
$target = "copilot-cli/$Host_`:$User"
Write-Verbose "Credential target: $target"

# --- 2. Read OAuth token from Windows Credential Manager (UTF-8) ------------
Add-Type -Namespace CredMan -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct CREDENTIAL {
    public uint   Flags;
    public uint   Type;
    public string TargetName;
    public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public uint   CredentialBlobSize;
    public IntPtr CredentialBlob;
    public uint   Persist;
    public uint   AttributeCount;
    public IntPtr Attributes;
    public string TargetAlias;
    public string UserName;
}
[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredRead(string target, uint type, uint flags, out IntPtr credPtr);
[DllImport("advapi32.dll", SetLastError = true)]
public static extern void CredFree(IntPtr cred);
'@

$ptr = [IntPtr]::Zero
if (-not [CredMan.Native]::CredRead($target, 1, 0, [ref]$ptr)) {
    $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "CredRead failed for '$target' (Win32 error $err). Is the user logged in via 'copilot login'?"
}
try {
    $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][CredMan.Native+CREDENTIAL])
    $bytes = New-Object byte[] $cred.CredentialBlobSize
    [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $bytes, 0, $cred.CredentialBlobSize)
    $token = [System.Text.Encoding]::UTF8.GetString($bytes)
} finally {
    [CredMan.Native]::CredFree($ptr) | Out-Null
}

if ([string]::IsNullOrWhiteSpace($token)) { throw "Empty token in credential blob." }

# --- 3. Call /models ---------------------------------------------------------
$headers = @{
    'Authorization'        = "Bearer $token"
    'Accept'               = 'application/json'
    'Content-Type'         = 'application/json'
    'Copilot-Integration-Id' = 'copilot-cli'
    'X-GitHub-Api-Version' = '2026-01-09'
    'Openai-Intent'        = 'conversation-agent'
    'X-Initiator'          = 'user'
    'X-Interaction-Id'     = [guid]::NewGuid().ToString()
    'User-Agent'           = 'GitHubCopilotCLI/1.0'
}

try {
    $resp = Invoke-RestMethod -Method Get -Uri 'https://api.githubcopilot.com/models' -Headers $headers
} catch {
    Write-Host ""
    Write-Host "Request failed:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)"
    if ($_.Exception.Response) {
        try {
            $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $body = $sr.ReadToEnd()
            Write-Host "  Body: $body"
        } catch {}
    }
    exit 2
}

$models = $resp.data
if (-not $All) {
    # Mirror the CLI's filterModelsForCaller (hide non-picker models unless policy=enabled)
    $models = $models | Where-Object {
        ($_.model_picker_enabled -ne $false) -or ($_.policy.state -eq 'enabled')
    }
}
if ($Filter) {
    $needle = $Filter.ToLowerInvariant()
    $models = $models | Where-Object {
        ($_.id      -and $_.id.ToLowerInvariant().Contains($needle)) -or
        ($_.name    -and $_.name.ToLowerInvariant().Contains($needle)) -or
        ($_.vendor  -and $_.vendor.ToLowerInvariant().Contains($needle))
    }
}

if ($Raw) {
    $resp.data | ConvertTo-Json -Depth 10
    return
}

$models |
    Select-Object id, name, vendor,
        @{n='picker';e={$_.model_picker_enabled}},
        @{n='preview';e={$_.preview}},
        @{n='policy';e={$_.policy.state}} |
    Sort-Object vendor, id |
    Format-Table -AutoSize

Write-Host ""
Write-Host ("{0} model(s){1}" -f $models.Count, $(if ($Filter) { " matching '$Filter'" } else { "" })) -ForegroundColor Green

# --- Notes ------------------------------------------------------------------
# Endpoint + header set verified against the CLI bundle:
#   $env:APPDATA\npm\node_modules\@github\copilot\app.js
# Key references:
#   listModelsAttempt()  -> GET ${baseURL}/models
#   baseURL              -> https://api.githubcopilot.com  (var Myi)
#   defaultHeaders()     -> Copilot-Integration-Id, X-Interaction-Id, User-Agent
#   baseHeaders          -> Accept, Content-Type, Openai-Intent=conversation-agent,
#                           X-Initiator=user, X-GitHub-Api-Version=2026-01-09
#   createWithOAuthToken -> Authorization: Bearer <token>
# Integration-Id constant "copilot-cli" verified at multiple call sites.
