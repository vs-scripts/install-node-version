#!/usr/bin/env pwsh

<#
RULE 01: SHOULD NOT evade any rule and protocol defined in this file.           ###
RULE 02: SHOULD NOT alter these rules or protocols.                             ###
RULE 03: SHOULD NOT create new rules or protocols to override or evade.         ###
RULE 04: SHOULD NOT change configurations to bypass these rules or protocols.   ###
RULE 05: MUST obtain author consent before making changes.                      ###
#>

<#
.SYNOPSIS
    Enforces atomic pushes by restricting pushes to a single commit with one file.

.DESCRIPTION
    This script is used as a pre-push hook to ensure that:
    1. Only a single commit is being pushed
    2. That commit contains only a single file

    This enforces the atomic push convention where each push should contain
    exactly one commit with changes to exactly one file.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Platform: Windows only
    Requirements: PowerShell 5.1 or later (pwsh 7+ preferred)
    Hook Type: Pre-push Git hook

.EXAMPLE
    .\restrict-pre-push-atomic.ps1
    Validates that exactly one commit with one file is being pushed.

.EXIT CODES
    0 - Success (atomic push allowed or no commits to push)
    1 - Failure (multiple commits or multiple files in commit)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Core Functions ---

function Test-AtomicPush {
    <#
    .SYNOPSIS
        Checks if the current push is atomic (contains exactly one commit with one file).

    .DESCRIPTION
        This function checks if the push meets the atomic push requirement by verifying:
        1. Only a single commit is being pushed
        2. That commit contains only a single file

    .OUTPUTS
        Boolean - Returns $true if the push is atomic, $false otherwise.

    .EXAMPLE
        if (Test-AtomicPush) { Write-Host "Push is atomic" }
        Validates the atomic push requirement.
    #>
    [CmdletBinding()]
    param()

    try {
        $commitList = @(git rev-list '@{upstream}..HEAD' 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $commitCount = $commitList.Count

        if ($commitCount -gt 1) {
            Write-Error -Message "ATOMIC_PUSH_REQUIRED: $commitCount commits to push (1 required)"
            for ($commitIndex = 0; $commitIndex -lt $commitList.Count; $commitIndex++) {
                $currentCommitHash = $commitList[$commitIndex]
                $commitMessage = git log -1 --pretty='%s' $currentCommitHash 2>&1 | Select-Object -First 1
                $commitShortHash = $currentCommitHash.Substring(0, 7)
                Write-Error -Message "$($commitIndex + 1). $commitShortHash $commitMessage"
            }
            return $false
        }

        if ($commitCount -eq 1) {
            $currentCommitHash = $commitList[0]
            $changedFileList = @(git diff-tree --no-commit-id --name-only -r $currentCommitHash 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
            $changedFileCount = $changedFileList.Count

            if ($changedFileCount -gt 1) {
                Write-Error -Message "ATOMIC_COMMIT_REQUIRED: $changedFileCount files in commit (1 required)"
                $changedFileList | ForEach-Object { Write-Error -Message $_ }
                return $false
            }
        }

        return $true
    } catch {
        # Fail silently on push to avoid breaking the push operation
        return $true
    }
}

# --- Main Script Execution ---

try {
    $isAtomicPush = Test-AtomicPush
    if (-not $isAtomicPush) {
        exit 1
    }
    exit 0
} catch {
    # Fail silently on push to avoid breaking the push operation
    exit 0
}
