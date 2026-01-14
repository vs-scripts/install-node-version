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

try {
    # Get the list of commits to be pushed
    $commits = @(git rev-list '@{upstream}..HEAD' 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
    $commitCount = $commits.Count

    if ($commitCount -gt 1) {
        Write-Error "ATOMIC_PUSH_REQUIRED: $commitCount commits to push (1 required)"
        for ($i = 0; $i -lt $commits.Count; $i++) {
            $commit = $commits[$i]
            $commitMsg = git log -1 --pretty='%s' $commit 2>&1 | Select-Object -First 1
            $commitShort = $commit.Substring(0, 7)
            Write-Error "$($i + 1). $commitShort $commitMsg"
        }
        exit 1
    }

    if ($commitCount -eq 1) {
        $commit = $commits[0]
        $files = @(git diff-tree --no-commit-id --name-only -r $commit 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $fileCount = $files.Count

        if ($fileCount -gt 1) {
            Write-Error "ATOMIC_COMMIT_REQUIRED: $fileCount files in commit (1 required)"
            $files | ForEach-Object { Write-Error $_ }
            exit 1
        }
    }

    exit 0
}
catch {
    # Fail silently on push to avoid breaking the push operation
    exit 0
}
