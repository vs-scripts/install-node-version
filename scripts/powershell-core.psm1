<#
.SYNOPSIS
PSM1 Core Module - Reusable PowerShell functions for elevated scripts

.DESCRIPTION
The PSM1 Core Module provides essential functions for script initialization, platform validation,
elevation handling, and standardized logging. This module consolidates common functionality used
across elevated scripts, enabling code reuse and consistent behavior.

The module includes:
- Core initialization functions (Initialize-ScriptEnvironment, Assert-WindowsPlatform, etc.)
- Elevation functions (Test-IsAdministrator, Invoke-ElevationRequest)
- Logging functions (Write-DebugLog, Write-InfoLog, Write-WarningLog, Write-ErrorLog, Write-ExceptionLog)
- Formatted output functions (Write-FormattedStep)

.NOTES
- Module has no side effects at import time
- All functions are exported via Export-ModuleMember
- Follows PowerShell standards and SOLID principles
- Requires PowerShell 7.5.4

.EXAMPLE
Import-Module -Name powershell-core
Initialize-ScriptEnvironment
Assert-WindowsPlatform
Write-InfoLog -Scope "INIT-SCRIPT" -Message "Script initialized successfully"
#>

Set-StrictMode -Version Latest

#region Core Initialization Functions

<#
.SYNOPSIS
Initializes the script environment with standard PowerShell preferences.

.DESCRIPTION
Sets up PowerShell preferences for consistent behavior across all scripts.
Configures StrictMode, ErrorActionPreference, DebugPreference, WarningPreference,
and VerbosePreference to ensure predictable script execution.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
None. This function sets preferences and produces no output.

.EXAMPLE
Initialize-ScriptEnvironment

.NOTES
This function should be called early in script execution to establish consistent
preferences. It has no side effects beyond setting PowerShell preferences.
#>
function Initialize-ScriptEnvironment {
    [CmdletBinding()]
    param()

    try {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $DebugPreference = 'Continue'
        $WarningPreference = 'Continue'
        $VerbosePreference = 'Continue'
    }
    catch {
        Write-Error -Message "Failed to initialize script environment: $_"
        throw
    }
}

<#
.SYNOPSIS
Validates that the script is running on Windows platform.

.DESCRIPTION
Checks if the current PowerShell session is running on Windows platform.
Throws an error if the script is not running on Windows, as many elevated
scripts require Windows-specific functionality.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
None. Throws an error if not on Windows platform.

.EXAMPLE
Assert-WindowsPlatform

.NOTES
This function should be called early in script execution to ensure the script
is running on a compatible platform. It uses $PSVersionTable to determine
the current platform.
#>
function Assert-WindowsPlatform {
    [CmdletBinding()]
    param()

    try {
        $isWindowsPlatform = $PSVersionTable.Platform -eq 'Win32NT' -or $PSVersionTable.OS -like '*Windows*'

        if (-not $isWindowsPlatform) {
            throw "This script requires Windows platform. Current platform: $($PSVersionTable.OS)"
        }
    }
    catch {
        Write-Error -Message "Platform validation failed: $_"
        throw
    }
}

<#
.SYNOPSIS
Tests if the current PowerShell session is interactive.

.DESCRIPTION
Determines whether the current PowerShell session is interactive (user-driven)
or non-interactive (automated, scheduled task, CI/CD pipeline). This is useful
for functions that need different behavior in interactive vs. non-interactive contexts.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
System.Boolean. Returns $true if session is interactive, $false otherwise.

.EXAMPLE
if (Test-IsInteractivePowerShell) {
    Write-Host "Running in interactive mode"
} else {
    Write-Host "Running in non-interactive mode"
}

.NOTES
This function checks $PSVersionTable.Interactive or input/output redirection
to determine if the session is interactive.
#>
function Test-IsInteractivePowerShell {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # Check if session is interactive
        $isInteractive = [Environment]::UserInteractive -and -not [Environment]::GetCommandLineArgs().Contains('-NonInteractive')
        return $isInteractive
    }
    catch {
        Write-Error -Message "Failed to determine if session is interactive: $_"
        return $false
    }
}

<#
.SYNOPSIS
Relaunches the script in PowerShell Core (pwsh) if needed.

.DESCRIPTION
Checks if the current PowerShell host is Windows PowerShell (powershell.exe)
or if the pwsh version doesn't match 7.5.4. If transition is needed, relaunches
the script in pwsh 7.5.4 with the same arguments and exits the current process.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
None. Exits the current process if relaunch is needed.

.EXAMPLE
Invoke-PowerShellCoreTransition

.NOTES
This function should be called early in script execution to ensure the script
runs in the correct PowerShell version. It uses the call operator (&) to
relaunch the script with the same arguments.
#>
function Invoke-PowerShellCoreTransition {
    [CmdletBinding()]
    param()

    try {
        # Check if running in Windows PowerShell
        $isWindowsPowerShell = $PSVersionTable.PSVersion.Major -lt 6

        if ($isWindowsPowerShell) {
            # Relaunch in pwsh
            $scriptPath = $MyInvocation.ScriptName
            $arguments = $PSBoundParameters.Values

            & pwsh -NoProfile -File $scriptPath @arguments
            exit $LASTEXITCODE
        }

        # Check if pwsh version matches 7.5.4
        $currentVersion = $PSVersionTable.PSVersion
        $requiredVersion = [version]'7.5.4'

        if ($currentVersion -ne $requiredVersion) {
            Write-Warning "PowerShell version mismatch. Current: $currentVersion, Required: $requiredVersion"
        }
    }
    catch {
        Write-Error -Message "Failed to transition to PowerShell Core: $_"
        throw
    }
}

<#
.SYNOPSIS
Enforces exact PowerShell version 7.5.4.

.DESCRIPTION
Validates that the current PowerShell version is exactly 7.5.4. Throws an error
if the version doesn't match exactly. This is stricter than Invoke-PowerShellCoreTransition
and is used when exact version matching is required.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
None. Throws an error if version doesn't match.

.EXAMPLE
Assert-PowerShellVersionStrict

.NOTES
This function should be called when exact version matching is required.
It checks $PSVersionTable.PSVersion against the required version 7.5.4.
#>
function Assert-PowerShellVersionStrict {
    [CmdletBinding()]
    param()

    try {
        $currentVersion = $PSVersionTable.PSVersion
        $requiredVersion = [version]'7.5.4'

        if ($currentVersion -ne $requiredVersion) {
            throw "PowerShell version mismatch. Current: $currentVersion, Required: $requiredVersion"
        }
    }
    catch {
        Write-Error -Message "PowerShell version validation failed: $_"
        throw
    }
}

#endregion

#region Elevation Functions

<#
.SYNOPSIS
Tests if the current process has administrative privileges.

.DESCRIPTION
Determines whether the current PowerShell process is running with administrative
privileges. This is useful for scripts that require elevation to perform their tasks.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
System.Boolean. Returns $true if running as administrator, $false otherwise.

.EXAMPLE
if (Test-IsAdministrator) {
    Write-Host "Running with administrative privileges"
} else {
    Write-Host "Not running with administrative privileges"
}

.NOTES
This function uses Windows identity checks to determine administrative status.
It works on Windows platforms only.
#>
function Test-IsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        return $isAdmin
    }
    catch {
        Write-Error -Message "Failed to determine administrator status: $_"
        return $false
    }
}

<#
.SYNOPSIS
Requests elevation via UAC and relaunches the script.

.DESCRIPTION
Requests administrative privileges via User Account Control (UAC) and relaunches
the script with elevated privileges. In non-interactive contexts (scheduled tasks,
CI/CD pipelines), logs guidance and exits with code 1 instead of attempting elevation.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
None. Exits the current process after relaunch or with code 1 in non-interactive context.

.EXAMPLE
if (-not (Test-IsAdministrator)) {
    Invoke-ElevationRequest
}

.NOTES
This function checks if the session is interactive before attempting elevation.
In non-interactive contexts, it logs guidance and exits with code 1.
#>
function Invoke-ElevationRequest {
    [CmdletBinding()]
    param()

    try {
        $isInteractive = Test-IsInteractivePowerShell

        if (-not $isInteractive) {
            Write-ErrorLog -Scope "ELEV-REQUEST" -Message "Cannot request elevation in non-interactive context. Run script with administrative privileges."
            exit 1
        }

        # Relaunch with elevation
        $scriptPath = $MyInvocation.ScriptName
        $arguments = $PSBoundParameters.Values

        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "powershell.exe"
        $processInfo.Arguments = "-NoProfile -File `"$scriptPath`" $arguments"
        $processInfo.UseShellExecute = $true
        $processInfo.Verb = "runas"

        $process = [System.Diagnostics.Process]::Start($processInfo)
        $process.WaitForExit()

        exit $process.ExitCode
    }
    catch {
        Write-Error -Message "Failed to request elevation: $_"
        exit 1
    }
}

#endregion

#region Logging Functions

<#
.SYNOPSIS
Generates a hash for log entries.

.DESCRIPTION
Creates an 8-character hash based on the current timestamp and a random value.
This hash is used to uniquely identify log entries for verification and tracking.

.PARAMETER None
This function takes no parameters.

.OUTPUTS
System.String. An 8-character hash string.

.EXAMPLE
$hash = Get-LogHash

.NOTES
This is a private helper function used internally by logging functions.
#>
function Get-LogHash {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $hashInput = "$(Get-Date -Format 'yyyyMMddHHmmssffff')$(Get-Random -Maximum 10000)"
        $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
        $hashObject = [System.Security.Cryptography.SHA256]::Create()
        $hash = $hashObject.ComputeHash($hashBytes)
        $hashString = [System.BitConverter]::ToString($hash).Replace('-', '').Substring(0, 8)
        return $hashString.ToLower()
    }
    catch {
        return "00000000"
    }
}

<#
.SYNOPSIS
Formats a log entry with timestamp, level, scope, message, and hash.

.DESCRIPTION
Creates a formatted log entry following the CLOGF (Concise Log Format) specification.
The format is: # TIMESTAMP LEVEL SCOPE MESSAGE HASH

Handles line wrapping for long messages to maintain readability.

.PARAMETER Level
The log level indicator (D, I, W, E, X).

.PARAMETER Scope
The scope in PARENT-CHILD format (e.g., INIT-SCRIPT).

.PARAMETER Message
The log message.

.OUTPUTS
System.String. The formatted log entry.

.EXAMPLE
$logEntry = Format-LogEntry -Level "I" -Scope "INIT-SCRIPT" -Message "Script initialized"

.NOTES
This is a private helper function used internally by logging functions.
#>
function Format-LogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    try {
        $timestamp = Get-Date -Format 'o'
        $hash = Get-LogHash

        # Format: # TIMESTAMP LEVEL SCOPE MESSAGE HASH
        $logEntry = "# $timestamp $Level $Scope $Message [$hash]"

        return $logEntry
    }
    catch {
        return "# $(Get-Date -Format 'o') E LOG-FORMAT Error formatting log entry [00000000]"
    }
}

<#
.SYNOPSIS
Core logging implementation.

.DESCRIPTION
Implements the core logging functionality used by all logging functions.
Formats the log entry and outputs it to the appropriate stream based on the level.

.PARAMETER Level
The log level indicator (D, I, W, E, X).

.PARAMETER Scope
The scope in PARENT-CHILD format (e.g., INIT-SCRIPT).

.PARAMETER Message
The log message.

.OUTPUTS
None. Outputs to the appropriate stream (debug, information, warning, error).

.EXAMPLE
Write-Log -Level "I" -Scope "INIT-SCRIPT" -Message "Script initialized"

.NOTES
This is a private helper function used internally by logging functions.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    try {
        $logEntry = Format-LogEntry -Level $Level -Scope $Scope -Message $Message

        switch ($Level) {
            'D' { Write-Debug -Message $logEntry }
            'I' { Write-Information -MessageData $logEntry -InformationAction Continue }
            'W' { Write-Warning -Message $logEntry }
            'E' { Write-Error -Message $logEntry -ErrorAction Continue }
            'X' { Write-Error -Message $logEntry -ErrorAction Continue }
            default { Write-Information -MessageData $logEntry -InformationAction Continue }
        }
    }
    catch {
        Write-Error -Message "Failed to write log entry: $_"
    }
}

<#
.SYNOPSIS
Outputs debug-level log entries.

.DESCRIPTION
Writes a debug-level log entry with timestamp, scope, message, and hash.
Follows the CLOGF specification for consistent log formatting.

.PARAMETER Scope
The scope in PARENT-CHILD format (e.g., INIT-SCRIPT).

.PARAMETER Message
The debug message.

.OUTPUTS
None. Outputs to the debug stream.

.EXAMPLE
Write-DebugLog -Scope "INIT-SCRIPT" -Message "Initializing script environment"

.NOTES
Debug-level logs are typically used for detailed diagnostic information.
#>
function Write-DebugLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level 'D' -Scope $Scope -Message $Message
}

<#
.SYNOPSIS
Outputs information-level log entries.

.DESCRIPTION
Writes an information-level log entry with timestamp, scope, message, and hash.
Follows the CLOGF specification for consistent log formatting.

.PARAMETER Scope
The scope in PARENT-CHILD format (e.g., INIT-SCRIPT).

.PARAMETER Message
The information message.

.OUTPUTS
None. Outputs to the information stream.

.EXAMPLE
Write-InfoLog -Scope "INIT-SCRIPT" -Message "Script initialized successfully"

.NOTES
Information-level logs are typically used for general informational messages.
#>
function Write-InfoLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level 'I' -Scope $Scope -Message $Message
}

<#
.SYNOPSIS
Outputs warning-level log entries.

.DESCRIPTION
Writes a warning-level log entry with timestamp, scope, message, and hash.
Follows the CLOGF specification for consistent log formatting.

.PARAMETER Scope
The scope in PARENT-CHILD format (e.g., INIT-SCRIPT).

.PARAMETER Message
The warning message.

.OUTPUTS
None. Outputs to the warning stream.

.EXAMPLE
Write-WarningLog -Scope "INIT-SCRIPT" -Message "Script is running in non-standard mode"

.NOTES
Warning-level logs are typically used for potentially problematic situations.
#>
function Write-WarningLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level 'W' -Scope $Scope -Message $Message
}

<#
.SYNOPSIS
Outputs error-level log entries.

.DESCRIPTION
Writes an error-level log entry with timestamp, scope, message, and hash.
Follows the CLOGF specification for consistent log formatting.

.PARAMETER Scope
The scope in PARENT-CHILD format (e.g., INIT-SCRIPT).

.PARAMETER Message
The error message.

.OUTPUTS
None. Outputs to the error stream.

.EXAMPLE
Write-ErrorLog -Scope "INIT-SCRIPT" -Message "Failed to initialize script environment"

.NOTES
Error-level logs are typically used for error conditions.
#>
function Write-ErrorLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level 'E' -Scope $Scope -Message $Message
}

<#
.SYNOPSIS
Outputs exception-level log entries.

.DESCRIPTION
Writes an exception-level log entry with timestamp, scope, message, and hash.
Follows the CLOGF specification for consistent log formatting.

.PARAMETER Scope
The scope in PARENT-CHILD format (e.g., INIT-SCRIPT).

.PARAMETER Message
The exception message.

.OUTPUTS
None. Outputs to the error stream.

.EXAMPLE
Write-ExceptionLog -Scope "INIT-SCRIPT" -Message "Unhandled exception occurred"

.NOTES
Exception-level logs are typically used for exception information.
#>
function Write-ExceptionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Log -Level 'X' -Scope $Scope -Message $Message
}

#endregion

#region Formatted Output Functions

<#
.SYNOPSIS
Outputs formatted step messages with visual styling.

.DESCRIPTION
Displays a formatted step message with specified foreground color and visual formatting.
Useful for displaying progress steps in scripts with consistent visual styling.

.PARAMETER Message
The step message to display.

.PARAMETER ForegroundColor
The foreground color for the message. Default is Cyan.

.OUTPUTS
None. Outputs to the host.

.EXAMPLE
Write-FormattedStep -Message "Initializing script environment" -ForegroundColor Cyan

.NOTES
This function outputs to the host console with visual formatting.
#>
function Write-FormattedStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
    )

    try {
        $formattedMessage = "► $Message"
        Write-Host -Object $formattedMessage -ForegroundColor $ForegroundColor
    }
    catch {
        Write-Error -Message "Failed to write formatted step: $_"
    }
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    'Initialize-ScriptEnvironment'
    'Assert-WindowsPlatform'
    'Test-IsInteractivePowerShell'
    'Invoke-PowerShellCoreTransition'
    'Assert-PowerShellVersionStrict'
    'Test-IsAdministrator'
    'Invoke-ElevationRequest'
    'Write-DebugLog'
    'Write-InfoLog'
    'Write-WarningLog'
    'Write-ErrorLog'
    'Write-ExceptionLog'
    'Write-FormattedStep'
)
