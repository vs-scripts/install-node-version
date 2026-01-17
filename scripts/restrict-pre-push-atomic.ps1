#!/usr/bin/env pwsh
<#
.SYNOPSIS
Enforces atomic pushes by restricting pushes to a single commit with one file.

.DESCRIPTION
This script is used as a pre-push hook to ensure that:
1. Only a single commit is being pushed
2. That commit contains only a single file

This enforces the atomic push convention.

.EXIT CODES
0 - Success (atomic push allowed or no commits to push)
1 - Failure (multiple commits or multiple files in commit)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Check-AtomicPush {
    <#
    .SYNOPSIS
    Checks if the current push is atomic (contains exactly one commit with one file).

    .DESCRIPTION
    This function checks if the push meets the atomic push requirement by verifying:
    1. Only a single commit is being pushed
    2. That commit contains only a single file

    .OUTPUTS
    Boolean
    Returns $true if the push is atomic, $false otherwise.
    #>

    try {
        # Get the list of commits to be pushed from git
        $commits = @(git rev-list '@{upstream}..HEAD' 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $commitCount = $commits.Count

        if ($commitCount -gt 1) {
            Write-Error "ATOMIC_PUSH_REQUIRED: $commitCount commits to push (1 required)"
            for ($commitIndex = 0; $commitIndex -lt $commits.Count; $commitIndex++) {
                $currentCommit = $commits[$commitIndex]
                $commitMessage = git log -1 --pretty='%s' $currentCommit 2>&1 | Select-Object -First 1
                $commitShortHash = $currentCommit.Substring(0, 7)
                Write-Error "$($commitIndex + 1). $commitShortHash $commitMessage"
            }
            return $false
        }

        if ($commitCount -eq 1) {
            $currentCommit = $commits[0]
            $changedFiles = @(git diff-tree --no-commit-id --name-only -r $currentCommit 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
            $changedFileCount = $changedFiles.Count

            if ($changedFileCount -gt 1) {
                Write-Error "ATOMIC_COMMIT_REQUIRED: $changedFileCount files in commit (1 required)"
                $changedFiles | ForEach-Object { Write-Error $_ }
                return $false
            }
        }

        return $true
    }
    catch {
        # Fail silently on push to avoid breaking the push operation
        return $true
    }
}

# Main execution
try {
    $isAtomicPush = Check-AtomicPush
    if (-not $isAtomicPush) {
        exit 1
    }
    exit 0
}
catch {
    # Fail silently on push to avoid breaking the push operation
    exit 0
}
