# BRK223 common helpers. Dot-source from any *.ps1 in this folder:
#     . (Join-Path $PSScriptRoot 'Common.ps1')

Set-StrictMode -Version 3.0

# --- Get-Sqlsim --------------------------------------------------------------
# Resolve the sqlsim.exe to use, in order:
#   1. $env:SQLSIM_PATH        (explicit override)
#   2. utilities\sqlsim.exe    (bundled with this demo, $PSScriptRoot\utilities)
#   3. Get-Command sqlsim      (on PATH)
#   4. Repo dev path           (C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe)
# Throws with a clear install hint if none of the above are present.
function Get-Sqlsim {
    if ($env:SQLSIM_PATH -and (Test-Path -LiteralPath $env:SQLSIM_PATH)) {
        return $env:SQLSIM_PATH
    }
    $bundled = Join-Path $PSScriptRoot 'utilities\sqlsim.exe'
    if (Test-Path -LiteralPath $bundled) { return $bundled }
    $cmd = Get-Command sqlsim -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $devPath = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe'
    if (Test-Path -LiteralPath $devPath) { return $devPath }
    throw @"
sqlsim not found. Set one of:
  * `$env:SQLSIM_PATH = 'C:\path\to\sqlsim.exe'
  * Drop sqlsim.exe into $($PSScriptRoot)\utilities\
  * Add sqlsim to PATH
  * Build it from c:\bwsql\sqlsimtools\sqlsim
"@
}

# --- Standard SET preamble --------------------------------------------------
# sqlsim and sqlcmd default OFF for several SET options the MSSQL extension /
# SSMS leave ON. JSON / filtered / indexed-view / computed-column indexes all
# fail Msg 1934 without these. Prepend to any script before invoking sqlsim -i.
$Script:BRK223_SqlSetPreamble = @'
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO
'@

function Get-BRK223SetPreamble { $Script:BRK223_SqlSetPreamble }

# --- Invoke-SqlsimScript ----------------------------------------------------
# Run a .sql file via sqlsim with the standard SET preamble prepended.
# Returns sqlsim's exit code; throws if exit != 0 unless -PassThruExitCode.
function Invoke-SqlsimScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [string]$Database = 'master',
        [int]$LoginTimeoutSeconds = 30,
        [int]$QueryTimeoutSeconds = 0,
        [switch]$PassThruExitCode
    )
    if (-not (Test-Path -LiteralPath $Path)) { throw "Script not found: $Path" }
    $sqlsim = Get-Sqlsim

    $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.sql')
    try {
        $body = (Get-BRK223SetPreamble) + "`r`n" + (Get-Content -Raw -LiteralPath $Path)
        Set-Content -LiteralPath $tmp -Value $body -Encoding UTF8 -NoNewline

        $sqlsimArgs = @('-S', $Server, '-d', $Database, '-U', $User, '-P', $Password,
                  '-C', '-l', $LoginTimeoutSeconds, '-i', $tmp)
        if ($QueryTimeoutSeconds -gt 0) { $sqlsimArgs += @('-t', $QueryTimeoutSeconds) }
        # Pipe to Out-Host so sqlsim's stdout is displayed but NOT captured
        # into the function's return pipeline (otherwise the return value
        # becomes an array of [stdout..., exitcode] and callers that do
        # `$code = Invoke-SqlsimScript ... -PassThruExitCode` get junk).
        & $sqlsim @sqlsimArgs | Out-Host
        $code = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }

    if ($PassThruExitCode) { return $code }
    if ($code -ne 0) { throw "sqlsim exited $code for $(Split-Path $Path -Leaf)" }
}

# --- Invoke-SqlsimQuery -----------------------------------------------------
# One-shot inline query via sqlsim -Q. For probe queries inside automation
# (e.g. SELECT 1 health check, SELECT COUNT(*) for branching).
# Returns the raw stdout (string array). Sets $LASTEXITCODE.
function Invoke-SqlsimQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Query,
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [string]$Database = 'master',
        [int]$LoginTimeoutSeconds = 5,
        [switch]$Quiet
    )
    $sqlsim = Get-Sqlsim
    $sqlsimArgs = @('-S', $Server, '-d', $Database, '-U', $User, '-P', $Password,
              '-C', '-l', $LoginTimeoutSeconds, '-Q', $Query)
    if ($Quiet) { $sqlsimArgs += '-q' }
    & $sqlsim @sqlsimArgs 2>&1
}
