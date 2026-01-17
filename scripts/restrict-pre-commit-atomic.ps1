#!/usr/bin/env pwsh
<#
.SYNOPSIS
Enforces atomic commits by restricting staged files to exactly one file.

.DESCRIPTION
This script is used as a pre-commit hook to ensure that only a single file
is staged for commit. This enforces the atomic commit convention.

.EXIT CODES
0 - Success (atomic commit allowed)
1 - Failure (multiple files staged or hook error)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Check-AtomicCommit {
    <#
    .SYNOPSIS
    Checks if the current commit is atomic (contains exactly one file).

    .DESCRIPTION
    This function checks if the staged files meet the atomic commit requirement
    by verifying that exactly one file is staged for commit.

    .OUTPUTS
    Boolean
    Returns $true if the commit is atomic, $false otherwise.
    #>

    try {
        # Get the list of staged files from git
        $stagedFiles = @(git diff --cached --name-only 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $stagedFileCount = $stagedFiles.Count

        if ($stagedFileCount -gt 1) {
            Write-Error "ATOMIC_COMMIT_REQUIRED: $stagedFileCount files staged (1 required)"
            $stagedFiles | ForEach-Object { Write-Error $_ }
            return $false
        }

        return $true
    }
    catch {
        Write-Error "HOOK_ERROR: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
try {
    $isAtomicCommit = Check-AtomicCommit
    if (-not $isAtomicCommit) {
        exit 1
    }
    exit 0
}
catch {
    Write-Error "HOOK_ERROR: $($_.Exception.Message)"
    exit 1
}
