#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Test script for atomic commit message validation.

.DESCRIPTION
    Tests the pattern matching logic of restrict-commit-msg-atomic.ps1
    with various file paths and commit message scenarios.

.NOTES
    Author: Test Suite
    Version: 0.0.0
    Platform: Windows only
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Test Configuration ---

$testCases = @(
    @{
        name = "Simple file in root"
        file = "README.md"
        message = "issue(readme): update documentation`n`n1. file: README.md`n2. change: added section`n3. reason: clarity`n4. impact: none`n5. verify: manual"
        expected = $true
    }
    @{
        name = "File in subdirectory"
        file = "scripts/test.ps1"
        message = "issue(test): fix validation`n`n1. file: scripts/test.ps1`n2. change: fixed logic`n3. reason: bug fix`n4. impact: none`n5. verify: tested"
        expected = $true
    }
    @{
        name = "File with special characters"
        file = "helps/concise-commit-format.help"
        message = "helps(format): update guide`n`n1. file: helps/concise-commit-format.help`n2. change: added examples`n3. reason: clarity`n4. impact: none`n5. verify: reviewed"
        expected = $true
    }
    @{
        name = "File with dots in name"
        file = ".gitattributes"
        message = "issue(gitattributes): update git attributes configuration`n`n1. file: .gitattributes`n2. change: added rules`n3. reason: cleanup`n4. impact: none`n5. verify: tested"
        expected = $true
    }
    @{
        name = "File not in message"
        file = "scripts/test.ps1"
        message = "issue(other): some change`n`n1. file: scripts/other.ps1`n2. change: fixed logic`n3. reason: bug fix`n4. impact: none`n5. verify: tested"
        expected = $false
    }
    @{
        name = "File mentioned in header only"
        file = "FORMAT"
        message = "issue(format): update FORMAT file`n`n1. file: FORMAT`n2. change: clarified rules`n3. reason: consistency`n4. impact: none`n5. verify: reviewed"
        expected = $true
    }
    @{
        name = "File with parentheses in path"
        file = "src/utils(old).js"
        message = "issue(utils): refactor`n`n1. file: src/utils(old).js`n2. change: cleaned up`n3. reason: maintenance`n4. impact: none`n5. verify: tested"
        expected = $true
    }
    @{
        name = "File with brackets in path"
        file = "src/[test].js"
        message = "issue(test): fix`n`n1. file: src/[test].js`n2. change: fixed`n3. reason: bug`n4. impact: none`n5. verify: tested"
        expected = $true
    }
    @{
        name = "Partial match should fail"
        file = "test.js"
        message = "issue(test): fix`n`n1. file: mytest.js`n2. change: fixed`n3. reason: bug`n4. impact: none`n5. verify: tested"
        expected = $false
    }
    @{
        name = "Case insensitive match"
        file = "README.md"
        message = "issue(readme): update`n`n1. file: readme.md`n2. change: added`n3. reason: clarity`n4. impact: none`n5. verify: manual"
        expected = $true
    }
    @{
        name = "Message with git comments"
        file = ".gitattributes"
        message = "issue(gitattributes): update git attributes configuration`n`n1. file: .gitattributes`n2. change: added rules comments and new file patterns`n3. reason: enforce repository rules`n4. impact: no impact, configuration update only`n5. verify: reviewed gitattributes file`n`n# RULE 00: MUST read and respect the ./5LAWS file.`n# RULE 01: MUST NOT evade any rule or protocol"
        expected = $true
    }
)

# --- Test Function ---

function Test-PatternMatch {
    param(
        [string]$FilePath,
        [string]$CommitMessage,
        [bool]$Expected
    )

    try {
        # Filter out comment lines (like git does)
        $filteredMessage = $CommitMessage -split "`n" | Where-Object { $_ -notmatch '^\s*#' } | Join-String -Separator "`n"

        # Escape special regex characters
        $escapedFile = [regex]::Escape($FilePath)
        # Match the file path as a whole word or path component
        $pattern = "(?:^|[\s/\\])$escapedFile(?:[\s/\\]|$)"

        # Use multiline mode to match across lines
        $isMatch = [regex]::IsMatch($filteredMessage, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        return $isMatch -eq $Expected
    } catch {
        Write-Error "Test error: $($_.Exception.Message)"
        return $false
    }
}

# --- Run Tests ---

$passed = 0
$failed = 0

Write-Host "`n=== Atomic Commit Message Pattern Matching Tests ===" -ForegroundColor Cyan
Write-Host ""

foreach ($testCase in $testCases) {
    $result = Test-PatternMatch -FilePath $testCase.file -CommitMessage $testCase.message -Expected $testCase.expected

    if ($result) {
        Write-Host "✓ PASS: $($testCase.name)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "✗ FAIL: $($testCase.name)" -ForegroundColor Red
        Write-Host "  File: $($testCase.file)" -ForegroundColor Yellow
        Write-Host "  Expected: $($testCase.expected)" -ForegroundColor Yellow
        $failed++
    }
}

Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host ""

if ($failed -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
}
