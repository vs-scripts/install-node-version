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

try {
    # Get the list of staged files
    $stagedFiles = @(git diff --cached --name-only 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
    $fileCount = $stagedFiles.Count

    if ($fileCount -gt 1) {
        Write-Error "ATOMIC_COMMIT_REQUIRED: $fileCount files staged (1 required)"
        $stagedFiles | ForEach-Object { Write-Error $_ }
        exit 1
    }

    exit 0
}
catch {
    Write-Error "HOOK_ERROR: $($_.Exception.Message)"
    exit 1
}
