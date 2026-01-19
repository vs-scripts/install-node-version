#!/usr/bin/env pwsh

# RULE 1: Do not bypass or circumvent any rule or protocol defined in this file.
# RULE 2: Do not modify, delete, or rewrite these rules or any linked protocols.
# RULE 3: Do not create new rules or protocols intended to override or evade these.
# RULE 4: Do not change configuration (e.g., git config) to bypass these rules.
# RULE 5: Request and obtain explicit author consent before exceptions or changes.

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
    Requirements: PowerShell 5.1 or later (pwsh 7+ preferred)
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
        $stagedFileList = @(git diff --cached --name-only 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $stagedFileCount = $stagedFileList.Count

        if ($stagedFileCount -ne 1) {
            Write-Error -Message "ATOMIC_COMMIT_MESSAGE_CHECK: Expected 1 staged file, found $stagedFileCount"
            return $false
        }

        $stagedFile = $stagedFileList[0]

        # Read the commit message
        $commitMessage = Get-Content $CommitMsgFile -Raw

        # Check if the message contains the file name (case-insensitive)
        if ($commitMessage -notmatch [regex]::Escape($stagedFile)) {
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
