#!/usr/bin/env pwsh

# RULE 1: Do not bypass or circumvent any rule or protocol defined in this file.
# RULE 2: Do not modify, delete, or rewrite these rules or any linked protocols.
# RULE 3: Do not create new rules or protocols intended to override or evade these.
# RULE 4: Do not change configuration (e.g., git config) to bypass these rules.
# RULE 5: Request and obtain explicit author consent before exceptions or changes.

<#
.SYNOPSIS
    Enforces atomic commits by restricting staged files to exactly one file.

.DESCRIPTION
    This script is used as a pre-commit hook to ensure that only a single file
    is staged for commit. This enforces the atomic commit convention where each
    commit should contain changes to exactly one file.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Platform: Windows only
    Requirements: PowerShell 5.1 or later (pwsh 7+ preferred)
    Hook Type: Pre-commit Git hook

.EXAMPLE
    .\restrict-pre-commit-atomic.ps1
    Validates that exactly one file is staged for commit.

.EXIT CODES
    0 - Success (atomic commit allowed)
    1 - Failure (multiple files staged or hook error)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Core Functions ---

function Test-AtomicCommit {
    <#
    .SYNOPSIS
        Checks if the current commit is atomic (contains exactly one file).

    .DESCRIPTION
        This function checks if the staged files meet the atomic commit requirement
        by verifying that exactly one file is staged for commit. Uses git to retrieve
        the list of staged files.

    .OUTPUTS
        Boolean - Returns $true if the commit is atomic, $false otherwise.

    .EXAMPLE
        if (Test-AtomicCommit) { Write-Host "Commit is atomic" }
        Validates the atomic commit requirement.
    #>
    [CmdletBinding()]
    param()

    try {
        $stagedFileList = @(git diff --cached --name-only 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $stagedFileCount = $stagedFileList.Count

        if ($stagedFileCount -gt 1) {
            Write-Error -Message "ATOMIC_COMMIT_REQUIRED: $stagedFileCount files staged (1 max required)"
            $stagedFileList | ForEach-Object { Write-Error -Message $_ }
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
    $isAtomicCommit = Test-AtomicCommit
    if (-not $isAtomicCommit) {
        exit 1
    }
    exit 0
} catch {
    Write-Error -Message "HOOK_ERROR: $($_.Exception.Message)"
    exit 1
}
