<# :
@echo off
echo.
echo Error: This script must be run from a PowerShell terminal.
echo.
exit /b 1
#>

<#
.SYNOPSIS
    Provides logging functions for generating concise log entries.

.DESCRIPTION
    This module implements the concise log format specification for generating
    standardized log entries. It includes functions for logging at different
    levels (Debug, Information, Warning, Error, Exception) and ensures all
    log entries follow the CLOGF specification.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Last Modified: 2026-01-19
    Platform: Windows only
    Requirements: pwsh 7.5.4+

.EXAMPLE
    . .\concise-log.ps1
    Write-Log -Level "I" -Scope "DATA-ACCOUNTS" -Message "Cannot add account data"

.EXIT CODES
    0 - Success
    1 - Failure (with error message)
#>

Set-StrictMode -Version Latest

# Module-level configuration variables
$script:DisableLogColors = $false
$script:EnableVerboseMode = $false

# --- Core Functions ---

function Initialize-ScriptEnvironment {
    <#
    .SYNOPSIS
        Initializes PowerShell session preferences.

    .DESCRIPTION
        Sets script-level preferences for Verbose, Debug, ErrorAction,
        and Progress to ensure consistent and informative output
        throughout script execution. These settings apply only to the
        current script scope.

    .NOTES
        This function MUST be called early in script execution, before
        any other operations that depend on these preferences.

    .EXAMPLE
        Initialize-ScriptEnvironment
        Configures all session preferences to their standard values.
    #>
    [CmdletBinding()]
    param()

    $script:VerbosePreference = 'Continue'
    $script:DebugPreference = 'Continue'
    $script:ErrorActionPreference = 'Stop'
    $script:ProgressPreference = 'SilentlyContinue'
}

function Assert-WindowsPlatform {
    <#
    .SYNOPSIS
        Validates the script is running on Windows.

    .DESCRIPTION
        Ensures the script is executed on a Windows platform, as required
        by the specification. Throws an exception if the platform is not Windows.

    .EXAMPLE
        Assert-WindowsPlatform
        Validates the current platform is Windows.
    #>
    [CmdletBinding()]
    param()

    if (-not ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)) {
        throw "This script requires Windows platform"
    }
}

function Test-IsInteractivePowerShell {
    <#
    .SYNOPSIS
        Ensures the script runs in an interactive terminal.

    .DESCRIPTION
        Checks if the script is running in an interactive PowerShell session.
        Throws an exception if the session is not interactive.

    .EXAMPLE
        Test-IsInteractivePowerShell
        Validates the current session is interactive.
    #>
    [CmdletBinding()]
    param()

    if (-not $Host.UI.RawUI) {
        throw "This script requires an interactive PowerShell terminal"
    }
}

function Invoke-PowerShellCoreTransition {
    <#
    .SYNOPSIS
        Relaunches in PowerShell Core (pwsh) if available and version < 7.

    .DESCRIPTION
        Checks if PowerShell Core (pwsh) is available and if the current
        PowerShell version is less than 7. If so, relaunches the script in pwsh.

    .EXAMPLE
        Invoke-PowerShellCoreTransition
        Transitions to PowerShell Core if necessary.
    #>
    [CmdletBinding()]
    param()

    $pwshPath = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
    if ($pwshPath -and $PSVersionTable.PSVersion.Major -lt 7) {
        Write-Verbose "Transitioning to PowerShell Core (pwsh)"
        & $pwshPath -File $PSCommandPath
        exit 0
    }
}

function Write-FormattedStep {
    <#
    .SYNOPSIS
        Outputs formatted step messages to console.

    .DESCRIPTION
        Writes a formatted step message to the console with optional color.

    .PARAMETER Message
        The message to display.

    .PARAMETER ForegroundColor
        The color of the text. Default is Cyan.

    .EXAMPLE
        Write-FormattedStep -Message "Installing packages" -ForegroundColor Cyan
        Displays a formatted step message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
    )

    Write-Host "$Message" -ForegroundColor $ForegroundColor
}

# --- Logging Functions ---

function Write-LogToHost {
    <#
    .SYNOPSIS
        Writes a log entry to the host console with color.

    .DESCRIPTION
        Outputs a formatted log entry to the console with color based on log level.

    .PARAMETER Message
        The formatted log message to display.

    .PARAMETER Level
        The log level (I, W).

    .EXAMPLE
        Write-LogToHost -Message "Log message" -Level "I"
        Displays the log message in dark green.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateSet('I', 'W')]
        [string]$Level
    )

    if ($script:DisableLogColors) {
        Write-Host $Message
    } else {
        switch ($Level) {
            'I' { Write-Host $Message -ForegroundColor DarkGreen }
            'W' { Write-Host $Message -ForegroundColor DarkYellow }
        }
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log entry in the concise log format.

    .DESCRIPTION
        Generates a log entry following the concise log format specification.
        The log entry includes a timestamp, log level, scope, message, and reference.
        Output method depends on log level and verbose mode setting.

    .PARAMETER Level
        The log level (D, I, W, E, X).

    .PARAMETER Scope
        The log scope in PARENT-CHILD format.

    .PARAMETER Message
        The log message.

    .EXAMPLE
        Write-Log -Level "I" -Scope "DATA-ACCOUNTS" -Message "Cannot add account data"
        Writes an information log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('D', 'I', 'W', 'E', 'X')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffZ"
    $logEntry = "# $timestamp $Level $Scope $Message"

    # Generate reference
    $hash = Get-LogHash -LogEntry $logEntry
    $reference = "urn:cla:$($Scope.Split('-')[0].ToLower()):$($Scope.Split('-')[1].ToLower()):$hash"

    # Format the log entry
    $formattedLog = "# $timestamp $Level $Scope $Message $reference"

    # Apply line wrapping if the log entry exceeds 83 characters
    if ($formattedLog.Length -gt 83) {
        # Split the log entry into lines, preserving the header (# DTS LVL SCP)
        $header = "# $timestamp $Level $Scope"
        $remainingMessage = " $Message $reference"

        # Calculate available space for the message after the header
        $headerLength = $header.Length + 1 # +1 for the space
        $availableSpace = 83 - $headerLength

        # Split the remaining message into chunks that fit within the available space
        # Break at word boundaries (spaces) instead of cutting words
        $messageChunks = @()
        $remainingText = $remainingMessage.TrimStart()

        while ($remainingText.Length -gt 0) {
            if ($remainingText.Length -le $availableSpace) {
                $messageChunks += $remainingText
                $remainingText = ""
            } else {
                # Find the last space within the available space
                $chunk = $remainingText.Substring(0, $availableSpace)
                $lastSpaceIndex = $chunk.LastIndexOf(' ')

                if ($lastSpaceIndex -gt 0) {
                    # Break at the last space
                    $chunk = $chunk.Substring(0, $lastSpaceIndex)
                    $messageChunks += $chunk
                    $remainingText = $remainingText.Substring($lastSpaceIndex + 1)
                } else {
                    # No space found, break at available space (word is too long)
                    $messageChunks += $chunk
                    $remainingText = $remainingText.Substring($availableSpace)
                }
            }
        }

        # Construct the formatted log with line wrapping
        $formattedLog = $header + " " + $messageChunks[0]
        for ($i = 1; $i -lt $messageChunks.Length; $i++) {
            $formattedLog += "`n" + $header + " " + $messageChunks[$i]
        }
    }

    # Output based on log level and verbose mode
    switch ($Level) {
        'D' {
            # Debug level always uses built-in Write-Debug
            Write-Debug $formattedLog
        }
        'I' {
            # Information level uses Write-Verbose if verbose mode enabled
            if ($script:EnableVerboseMode) {
                Write-Verbose $formattedLog
            } else {
                Write-LogToHost -Message $formattedLog -Level $Level
            }
        }
        'W' {
            # Warning level uses Write-Verbose if verbose mode enabled
            if ($script:EnableVerboseMode) {
                Write-Verbose $formattedLog
            } else {
                Write-LogToHost -Message $formattedLog -Level $Level
            }
        }
        'E' {
            # Error level uses Write-Verbose if verbose mode enabled
            if ($script:EnableVerboseMode) {
                Write-Verbose $formattedLog
            } else {
                Write-Host $formattedLog -ForegroundColor Red
            }
        }
        'X' {
            # Exception level uses Write-Verbose if verbose mode enabled
            if ($script:EnableVerboseMode) {
                Write-Verbose $formattedLog
            } else {
                Write-Host $formattedLog -ForegroundColor DarkRed
            }
        }
    }

    return $formattedLog
}

function Get-LogHash {
    <#
    .SYNOPSIS
        Generates a hash for the log entry.

    .DESCRIPTION
        Computes a 5-character alphanumeric hash of the log entry for use as a reference.

    .PARAMETER LogEntry
        The log entry to hash.

    .EXAMPLE
        $hash = Get-LogHash -LogEntry "# 2024-01-15T05:55:00.00Z I DATA-ACCOUNTS Cannot add account data"
        Returns a 5-character hash.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogEntry
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($LogEntry)
    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    return $hash.Substring(0, 5)
}

function Write-DebugLog {
    <#
    .SYNOPSIS
        Writes a debug log entry.

    .DESCRIPTION
        Writes a log entry at the Debug level.

    .PARAMETER Scope
        The log scope in PARENT-CHILD format.

    .PARAMETER Message
        The log message.

    .EXAMPLE
        Write-DebugLog -Scope "DATA-ACCOUNTS" -Message "Debugging account data"
        Writes a debug log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level "D" -Scope $Scope -Message $Message
}

function Write-InfoLog {
    <#
    .SYNOPSIS
        Writes an information log entry.

    .DESCRIPTION
        Writes a log entry at the Information level.

    .PARAMETER Scope
        The log scope in PARENT-CHILD format.

    .PARAMETER Message
        The log message.

    .EXAMPLE
        Write-InfoLog -Scope "DATA-ACCOUNTS" -Message "Processing account data"
        Writes an information log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level "I" -Scope $Scope -Message $Message
}

function Write-WarningLog {
    <#
    .SYNOPSIS
        Writes a warning log entry.

    .DESCRIPTION
        Writes a log entry at the Warning level.

    .PARAMETER Scope
        The log scope in PARENT-CHILD format.

    .PARAMETER Message
        The log message.

    .EXAMPLE
        Write-WarningLog -Scope "DATA-ACCOUNTS" -Message "Account data may be incomplete"
        Writes a warning log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level "W" -Scope $Scope -Message $Message
}

function Write-ErrorLog {
    <#
    .SYNOPSIS
        Writes an error log entry.

    .DESCRIPTION
        Writes a log entry at the Error level.

    .PARAMETER Scope
        The log scope in PARENT-CHILD format.

    .PARAMETER Message
        The log message.

    .EXAMPLE
        Write-ErrorLog -Scope "DATA-ACCOUNTS" -Message "Failed to add account data"
        Writes an error log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level "E" -Scope $Scope -Message $Message
}

function Write-ExceptionLog {
    <#
    .SYNOPSIS
        Writes an exception log entry.

    .DESCRIPTION
        Writes a log entry at the Exception level.

    .PARAMETER Scope
        The log scope in PARENT-CHILD format.

    .PARAMETER Message
        The log message.

    .EXAMPLE
        Write-ExceptionLog -Scope "DATA-ACCOUNTS" -Message "Unexpected error in account data"
        Writes an exception log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level "X" -Scope $Scope -Message $Message
}

# --- Main Script Execution ---

# Note: Export-ModuleMember is not needed for dot-sourcing.
# All functions defined in this script are automatically available
# to the calling script after dot-sourcing.
