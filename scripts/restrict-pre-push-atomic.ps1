#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Enforces atomic pushes by restricting pushes to a single commit with one
    file.

.DESCRIPTION
    This script is used as a pre-push hook to ensure that:
    1. Only a single commit is being pushed
    2. That commit contains only a single file

    This enforces the atomic push convention where each push should contain
    exactly one commit with changes to exactly one file.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Last Modified: 2026-01-28
    Platform: Windows only
    Requirements: pwsh 7.5.4
    Hook Type: Pre-push Git hook

.EXAMPLE
    .\restrict-pre-push-atomic.ps1
    Validates that exactly one commit with one file is being pushed.

.EXIT CODES
    0 - Success (atomic push allowed or no commits to push)
    1 - Failure (multiple commits or multiple files in commit)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest

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

function Test-AtomicPush {
    <#
    .SYNOPSIS
        Checks if the current push is atomic (contains exactly one commit with
        one file).

    .DESCRIPTION
        This function checks if the push meets the atomic push requirement by
        verifying:
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
        Write-DebugLog -Scope "HOOK-PREPUSH" `
            -Message "Checking atomic push requirements"

        $commitList = @(& git rev-list '@{upstream}..HEAD' 2>&1 | `
            Where-Object { $_ -and $_ -notmatch '^\s*$' })
        $commitCount = $commitList.Count

        Write-DebugLog -Scope "HOOK-PREPUSH" `
            -Message "Found $commitCount commits to push"

        if ($commitCount -gt 1) {
            $message = "ATOMIC_PUSH_REQUIRED: $commitCount commits to push " +
                "(1 required)"
            Write-ErrorLog -Scope "HOOK-PREPUSH" -Message $message

            for ($commitIndex = 0; $commitIndex -lt $commitList.Count; `
                $commitIndex++) {
                $currentCommitHash = $commitList[$commitIndex]
                $commitMessage = & git log -1 --pretty='%s' `
                    $currentCommitHash 2>&1 | Select-Object -First 1
                $commitShortHash = $currentCommitHash.Substring(0, 7)
                $indexMessage = "$($commitIndex + 1). $commitShortHash " +
                    "$commitMessage"
                Write-ErrorLog -Scope "HOOK-PREPUSH" -Message $indexMessage
            }
            return $false
        }

        if ($commitCount -eq 1) {
            $currentCommitHash = $commitList[0]
            $changedFileList = @(& git diff-tree --no-commit-id --name-only `
                -r $currentCommitHash 2>&1 | `
                Where-Object { $_ -and $_ -notmatch '^\s*$' })
            $changedFileCount = $changedFileList.Count

            Write-DebugLog -Scope "HOOK-PREPUSH" `
                -Message "Found $changedFileCount files in commit"

            if ($changedFileCount -gt 1) {
                $message = "ATOMIC_COMMIT_REQUIRED: $changedFileCount files " +
                    "in commit (1 required)"
                Write-ErrorLog -Scope "HOOK-PREPUSH" -Message $message

                $changedFileList | ForEach-Object {
                    Write-ErrorLog -Scope "HOOK-PREPUSH" -Message $_
                }
                return $false
            }
        }

        Write-InfoLog -Scope "HOOK-PREPUSH" `
            -Message "Atomic push requirements satisfied"

        return $true
    } catch {
        Write-DebugLog -Scope "HOOK-PREPUSH" `
            -Message "Push validation failed silently: $($_.Exception.Message)"

        # Fail silently on push to avoid breaking the push operation
        return $true
    }
}

#endregion

#region Main Script Execution

Initialize-ScriptEnvironment
Assert-WindowsPlatform
Assert-PowerShellVersionStrict

try {
    $isAtomicPush = Test-AtomicPush
    if (-not $isAtomicPush) {
        Write-ErrorLog -Scope "SCRIPT-MAIN" `
            -Message "Atomic push validation failed"
        exit 1
    }

    Write-InfoLog -Scope "SCRIPT-MAIN" `
        -Message "Pre-push validation completed successfully"
    exit 0
} catch {
    Write-DebugLog -Scope "SCRIPT-MAIN" `
        -Message "Unexpected error: $($_.Exception.Message)"

    # Fail silently on push to avoid breaking the push operation
    exit 0
}

#endregion
