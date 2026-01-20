<#
.SYNOPSIS
    Test script for concise-log.ps1 module.

.DESCRIPTION
    This script tests the functionality of the concise-log.ps1 module,
    including its logging functions and helper functions.

.NOTES
    Author: Kilo Code
    Version: 0.0.1
    Last Modified: 2026-01-20
    Platform: Windows only
    Requirements: pwsh 7.5.4+
#>

# Import the module
. "$PSScriptRoot\..\scripts\concise-log.ps1"

# Initialize the script environment
Initialize-ScriptEnvironment

# Test the logging functions
function Test-LoggingFunctions {
    <#
    .SYNOPSIS
        Tests the logging functions in the concise-log.ps1 module.
    #>

    Write-Host "Testing logging functions..." -ForegroundColor Cyan

    # Test Write-DebugLog
    Write-Host "Testing Write-DebugLog..." -ForegroundColor Yellow
    Write-DebugLog -Scope "TEST-DEBUG" -Message "This is a debug message"

    # Test Write-InfoLog
    Write-Host "Testing Write-InfoLog..." -ForegroundColor Yellow
    Write-InfoLog -Scope "TEST-INFO" -Message "This is an info message"

    # Test Write-WarningLog
    Write-Host "Testing Write-WarningLog..." -ForegroundColor Yellow
    Write-WarningLog -Scope "TEST-WARNING" -Message "This is a warning message"

    # Test Write-ErrorLog
    Write-Host "Testing Write-ErrorLog..." -ForegroundColor Yellow
    Write-ErrorLog -Scope "TEST-ERROR" -Message "This is an error message"

    # Test Write-ExceptionLog
    Write-Host "Testing Write-ExceptionLog..." -ForegroundColor Yellow
    Write-ExceptionLog -Scope "TEST-EXCEPTION" -Message "This is an exception message"

    Write-Host "Logging functions test completed." -ForegroundColor Green
}

# Test the helper functions
function Test-HelperFunctions {
    <#
    .SYNOPSIS
        Tests the helper functions in the concise-log.ps1 module.
    #>

    Write-Host "Testing helper functions..." -ForegroundColor Cyan

    # Test Get-LogHash
    Write-Host "Testing Get-LogHash..." -ForegroundColor Yellow
    $logEntry = "# 2024-01-15T05:55:00.00Z I DATA-ACCOUNTS Cannot add account data"
    $hash = Get-LogHash -LogEntry $logEntry
    Write-Host "Generated hash: $hash" -ForegroundColor DarkGreen

    # Test Write-FormattedStep
    Write-Host "Testing Write-FormattedStep..." -ForegroundColor Yellow
    Write-FormattedStep -Message "This is a formatted step message" -ForegroundColor Magenta

    Write-Host "Helper functions test completed." -ForegroundColor Green
}

# Test the Write-Log function with different levels
function Test-WriteLogFunction {
    <#
    .SYNOPSIS
        Tests the Write-Log function with different log levels.
    #>

    Write-Host "Testing Write-Log function..." -ForegroundColor Cyan

    # Test Debug level
    Write-Host "Testing Debug level..." -ForegroundColor Yellow
    $debugLog = Write-Log -Level "D" -Scope "TEST-LOG" -Message "Debug log entry"
    Write-Host "Debug log: $debugLog" -ForegroundColor DarkGray

    # Test Information level
    Write-Host "Testing Information level..." -ForegroundColor Yellow
    $infoLog = Write-Log -Level "I" -Scope "TEST-LOG" -Message "Info log entry"
    Write-Host "Info log: $infoLog" -ForegroundColor DarkGreen

    # Test Warning level
    Write-Host "Testing Warning level..." -ForegroundColor Yellow
    $warningLog = Write-Log -Level "W" -Scope "TEST-LOG" -Message "Warning log entry"
    Write-Host "Warning log: $warningLog" -ForegroundColor DarkYellow

    # Test Error level
    Write-Host "Testing Error level..." -ForegroundColor Yellow
    $errorLog = Write-Log -Level "E" -Scope "TEST-LOG" -Message "Error log entry"
    Write-Host "Error log: $errorLog" -ForegroundColor Red

    # Test Exception level
    Write-Host "Testing Exception level..." -ForegroundColor Yellow
    $exceptionLog = Write-Log -Level "X" -Scope "TEST-LOG" -Message "Exception log entry"
    Write-Host "Exception log: $exceptionLog" -ForegroundColor Red

    Write-Host "Write-Log function test completed." -ForegroundColor Green
}

# Test the line wrapping functionality
function Test-LineWrapping {
    <#
    .SYNOPSIS
        Tests the line wrapping functionality in the Write-Log function.
    #>

    Write-Host "Testing line wrapping..." -ForegroundColor Cyan

    # Test with a long message
    $longMessage = "This is a very long message that should trigger line wrapping in the log entry to ensure it fits within the specified width."
    $wrappedLog = Write-Log -Level "I" -Scope "TEST-WRAP" -Message $longMessage
    Write-Host "Wrapped log: $wrappedLog" -ForegroundColor DarkGreen

    Write-Host "Line wrapping test completed." -ForegroundColor Green
}

# Run all tests
function Run-AllTests {
    <#
    .SYNOPSIS
        Runs all tests for the concise-log.ps1 module.
    #>

    Write-Host "Starting tests for concise-log.ps1..." -ForegroundColor Magenta

    Test-LoggingFunctions
    Test-HelperFunctions
    Test-WriteLogFunction
    Test-LineWrapping

    Write-Host "All tests completed." -ForegroundColor Magenta
}

# Execute the tests
Run-AllTests
