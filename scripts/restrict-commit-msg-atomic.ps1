#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Enforces atomic commit messages.

.DESCRIPTION
    This script is used as a commit-msg hook to ensure that the commit
    message contains the name of the single staged file, enforcing
    atomic commit message convention.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Last Modified: 2026-01-28
    Platform: Windows only
    Requirements: pwsh 7.5.4

.EXAMPLE
    # Validates that the commit message references the single staged file.
    .\restrict-commit-msg-atomic.ps1 "path/to/commit-msg-file"


.EXIT CODES
    0 - Success (atomic commit message allowed)
    1 - Failure (message does not reference the file or hook error)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CommitMsgFile
)

# Import required modules
$scriptPath = $PSScriptRoot
$conciseLogPath = Join-Path $scriptPath 'concise-log.psm1'
$coreModulePath = Join-Path $scriptPath 'powershell-core.psm1'

# Convert to absolute paths (REQUIRED)
$conciseLogPath = [System.IO.Path]::GetFullPath($conciseLogPath)
$coreModulePath = [System.IO.Path]::GetFullPath($coreModulePath)

if (-not (Test-Path -LiteralPath $conciseLogPath)) {
    Write-Error 'Required module not found: concise-log.psm1'
    exit 1
}

if (-not (Test-Path -LiteralPath $coreModulePath)) {
    Write-Error 'Required module not found: powershell-core.psm1'
    exit 1
}

Import-Module -Name $conciseLogPath -Force -ErrorAction Stop
Import-Module -Name $coreModulePath -Force -ErrorAction Stop

#region Primary Functions

function Test-AtomicCommitMessage {
    <#
    .SYNOPSIS
        Checks if the commit message references the single staged file.

    .DESCRIPTION
        This function checks if the commit message contains the name
        of the single staged file, ensuring the message follows atomic
        commit conventions.

    .PARAMETER MessageFilePath
        The path to the commit message file.

    .OUTPUTS
        System.Boolean. Returns $true if the message is atomic, $false
        otherwise.

    .EXAMPLE
        $isAtomic = Test-AtomicCommitMessage -MessageFilePath $file
        Validates the atomic commit message requirement.

    .NOTES
        This function validates both the staged file count and message
        content.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$MessageFilePath
    )

    try {
        Write-DebugLog -Scope "HOOK-COMMITMSG" `
            -Message "Checking atomic commit message"

        # Get the staged file (should be exactly one)
        $stagedFileOutput = & git diff --cached --name-only 2>&1
        $stagedFileList = @($stagedFileOutput | Where-Object {
            $_ -and $_ -notmatch '^\s*$'
        })
        $stagedFileCount = $stagedFileList.Count

        if ($stagedFileCount -ne 1) {
            Write-ErrorLog -Scope "HOOK-COMMITMSG" `
                -Message "Expected 1 staged file, found $stagedFileCount"

            return $false
        }

        $stagedFile = $stagedFileList[0].Trim()

        Write-DebugLog -Scope "HOOK-COMMITMSG" `
            -Message "Staged file: $stagedFile"

        # Read the commit message and filter out comment lines
        $rawMessage = Get-Content -LiteralPath $MessageFilePath -Raw
        $commitMessage = $rawMessage -split "`n" | Where-Object {
            $_ -notmatch '^\s*#'
        } | Join-String -Separator "`n"

        Write-DebugLog -Scope "HOOK-COMMITMSG" `
            -Message "Commit message length: $($commitMessage.Length)"

        # Escape special regex characters for exact file match
        $escapedFile = [regex]::Escape($stagedFile)
        $pattern = "(?:^|[\s/\\])$escapedFile(?:[\s/\\]|$)"

        Write-DebugLog -Scope "HOOK-COMMITMSG" `
            -Message "Pattern: $pattern"

        # Use multiline mode to match across lines
        $regexOptions = [System.Text.RegularExpressions.RegexOptions]
        $isMatch = [regex]::IsMatch(
            $commitMessage,
            $pattern,
            $regexOptions::Multiline -bor $regexOptions::IgnoreCase
        )

        if (-not $isMatch) {
            Write-ErrorLog -Scope "HOOK-COMMITMSG" `
                -Message "Commit message must reference file: $stagedFile"

            return $false
        }

        Write-InfoLog -Scope "HOOK-COMMITMSG" `
            -Message "Atomic commit message validated"

        return $true
    }
    catch {
        Write-ErrorLog -Scope "HOOK-COMMITMSG" `
            -Message "Validation error: $($_.Exception.Message)"

        throw
    }
}

#endregion

#region Main Script Execution

Initialize-ScriptEnvironment
Assert-WindowsPlatform
Assert-PowerShellVersionStrict

try {
    $isAtomicMessage = Test-AtomicCommitMessage `
        -MessageFilePath $CommitMsgFile

    if (-not $isAtomicMessage) {
        Write-ErrorLog -Scope "SCRIPT-MAIN" `
            -Message "Commit rejected: message not atomic"

        exit 1
    }

    Write-InfoLog -Scope "SCRIPT-MAIN" `
        -Message "Success: Atomic commit message validated"

    exit 0
}
catch {
    Write-ExceptionLog -Scope "SCRIPT-MAIN" `
        -Message "Unexpected issue: $($_.Exception.Message)"

    Write-DebugLog -Scope "SCRIPT-MAIN" `
        -Message "Stack Trace: $($_.ScriptStackTrace)"

    exit 1
}

#endregion
