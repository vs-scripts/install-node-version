#!/usr/bin/env pwsh

<#
# RULE 01: MUST NOT evade any rule or protocol defined in this file.
# RULE 02: MUST NOT alter these rules or protocols without author consent.
# RULE 03: MUST NOT create new rules or protocols to override or evade.
# RULE 04: MUST NOT change configurations to bypass these rules or protocols.
# RULE 05: MUST obtain author consent before making any changes.
#>

<#
.SYNOPSIS
    Enforces atomic commit messages by ensuring the message references the single staged file.

.DESCRIPTION
    This script is used as a commit-msg hook to ensure that the commit message
    contains the name of the single staged file, enforcing atomic commit message convention.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Platform: Windows only
    Requirements: pwsh 7.5.4+
    Hook Type: Commit-msg Git hook

.EXAMPLE
    .\restrict-commit-msg-atomic.ps1 "path/to/commit-msg-file"
    Validates that the commit message references the single staged file.

.EXIT CODES
    0 - Success (atomic commit message allowed)
    1 - Failure (message does not reference the file or hook error)
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$CommitMsgFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the concise logging module
$scriptDir = $PSScriptRoot
. "$scriptDir\concise-log.ps1"

# --- Core Functions ---

function Test-AtomicCommitMessage {
    <#
    .SYNOPSIS
        Checks if the commit message references the single staged file.

    .DESCRIPTION
        This function checks if the commit message contains the name of the single
        staged file, ensuring the message follows atomic commit conventions.

    .OUTPUTS
        Boolean - Returns $true if the message is atomic, $false otherwise.

    .EXAMPLE
        if (Test-AtomicCommitMessage) { Write-Host "Commit message is atomic" }
        Validates the atomic commit message requirement.
    #>
    [CmdletBinding()]
    param()

    try {
        # Get the staged file (should be exactly one)
        $stagedFileOutput = git diff --cached --name-only 2>&1
        $stagedFileList = @($stagedFileOutput | Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $stagedFileCount = $stagedFileList.Count

        if ($stagedFileCount -ne 1) {
            Write-Error -Message "ATOMIC_COMMIT_MESSAGE_CHECK: Expected 1 staged file, found $stagedFileCount"
            return $false
        }

        $stagedFile = $stagedFileList[0].Trim()

        Write-Host "Staged file: '$stagedFile'"

        # Read the commit message and filter out comment lines
        $rawMessage = Get-Content $CommitMsgFile -Raw
        $commitMessage = $rawMessage -split "`n" | Where-Object { $_ -notmatch '^\s*#' } | Join-String -Separator "`n"

        Write-Host "Commit message: '$commitMessage'"

        # Escape special regex characters and create pattern for exact file match
        $escapedFile = [regex]::Escape($stagedFile)
        # Match the file path with word boundaries or path separators
        # Allow start of string, whitespace, or path separator before file
        # Allow end of string, whitespace, or path separator after file
        $pattern = "(?:^|[\s/\\])$escapedFile(?:[\s/\\]|$)"

        Write-Host "Pattern: '$pattern'"

        # Use multiline mode to match across lines
        $isMatch = [regex]::IsMatch($commitMessage, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        Write-Host "Is match: $isMatch"

        if (-not $isMatch) {
            Write-Error -Message "ATOMIC_COMMIT_MESSAGE_REQUIRED: Commit message must reference the file '$stagedFile'"
            return $false
        }

        return $true
    } catch {
        Write-Error -Message "HOOK_ERROR: $($_.Exception.Message)"
        return $false
    }
}

# --- Main Script Execution ---

try {
    $isAtomicMessage = Test-AtomicCommitMessage
    if (-not $isAtomicMessage) {
        exit 1
    }
    exit 0
} catch {
    Write-Error -Message "HOOK_ERROR: $($_.Exception.Message)"
    exit 1
}
