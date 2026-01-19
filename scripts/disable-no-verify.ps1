<# :
@echo off
echo.
echo Error: This script must be run from a PowerShell terminal.
echo.
exit /b 1
#>

<#
RULE 01: SHOULD NOT evade any rule and protocol defined in this file.           ###
RULE 02: SHOULD NOT alter these rules or protocols.                             ###
RULE 03: SHOULD NOT create new rules or protocols to override or evade.         ###
RULE 04: SHOULD NOT change configurations to bypass these rules or protocols.   ###
RULE 05: MUST obtain author consent before making changes.                      ###
#>

<#
.SYNOPSIS
    Prevents the use of --no-verify flag in git commands.

.DESCRIPTION
    This script checks command line arguments for the presence of the --no-verify flag
    and prevents its use by exiting with an error code. This enforces commit verification
    and prevents bypassing of pre-commit hooks.

.NOTES
    Author: Richeve Bebedor
    Version: 0.0.0
    Last Modified: 2026-01-19
    Platform: Windows only
    Requirements: pwsh 7.5.4+

.EXAMPLE
    .\disable-no-verify.ps1 --no-verify
    Exits with error code 1 when --no-verify is detected.

.EXIT CODES
    0 - Success (no --no-verify flag found)
    1 - Failure (--no-verify flag detected or other error)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Args
)

Set-StrictMode -Version Latest

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
        Validates the script is running on Windows platform.

    .DESCRIPTION
        Ensures the script is executed on Windows operating system.
        Exits with error if run on non-Windows platforms.

    .NOTES
        This script is designed specifically for Windows environments.
    #>
    [CmdletBinding()]
    param()

    if (-not ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)) {
        throw "This script requires Windows operating system"
    }

    Write-Verbose "Windows platform validated"
}

function Test-IsInteractivePowerShell {
    <#
    .SYNOPSIS
        Ensures the script runs in an interactive PowerShell terminal.

    .DESCRIPTION
        Verifies that the script is running in an interactive PowerShell session
        rather than a batch or non-interactive environment.

    .NOTES
        This function helps prevent accidental execution from non-PowerShell contexts.
    #>
    [CmdletBinding()]
    param()

    if (-not $Host.UI.RawUI) {
        throw "This script must be run in an interactive PowerShell terminal"
    }

    Write-Verbose "Interactive PowerShell terminal validated"
}

function Invoke-PowerShellCoreTransition {
    <#
    .SYNOPSIS
        Relaunches script in PowerShell Core if available and version is sufficient.

    .DESCRIPTION
        Checks for PowerShell Core (pwsh) availability and version.
        If available and version >= 7.5.4, continues execution.
        Otherwise, attempts to relaunch in pwsh.

    .NOTES
        This ensures consistent behavior across PowerShell versions.
    #>
    [CmdletBinding()]
    param()

    $requiredVersion = [version]'7.5.4'
    $currentVersion = $PSVersionTable.PSVersion

    if ($currentVersion -ge $requiredVersion) {
        Write-Verbose "PowerShell version $currentVersion meets requirements"
        return
    }

    # Try to find pwsh
    $pwshPath = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
    if (-not $pwshPath) {
        Write-Warning "PowerShell Core (pwsh) not found. Continuing with current version."
        return
    }

    Write-FormattedStep "Relaunching in PowerShell Core for better compatibility"
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = $MyInvocation.Line -replace [regex]::Escape($MyInvocation.MyCommand.Name), ''
    & $pwshPath -File $scriptPath $arguments
    exit 0
}

function Write-FormattedStep {
    <#
    .SYNOPSIS
        Outputs formatted step messages to console.

    .DESCRIPTION
        Displays step messages with consistent formatting for better readability
        and user experience.

    .PARAMETER Message
        The message text to display.

    .PARAMETER ForegroundColor
        The color to use for the message text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
    )

    Write-Host ">>" -NoNewline -ForegroundColor $ForegroundColor
    Write-Host " $Message" -ForegroundColor $ForegroundColor
}

# --- Helper Functions ---

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Checks for administrative privileges.

    .DESCRIPTION
        Determines if the current PowerShell session has administrative privileges.

    .RETURNS
        Boolean indicating whether the session has admin rights.
    #>
    [CmdletBinding()]
    param()

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Verbose "Administrator check: $isAdmin"
    return $isAdmin
}

function Invoke-ElevationRequest {
    <#
    .SYNOPSIS
        Requests elevation and relaunches the script with admin privileges.

    .DESCRIPTION
        Attempts to relaunch the current script with administrative privileges
        if elevation is required for certain operations.

    .NOTES
        This function exits the current process and starts a new elevated one.
    #>
    [CmdletBinding()]
    param()

    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = $MyInvocation.Line -replace [regex]::Escape($MyInvocation.MyCommand.Name), ''

    try {
        Write-FormattedStep "Requesting administrative privileges..."
        Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "`"$scriptPath$arguments`"" -Verb RunAs -Wait
        exit 0
    } catch {
        throw "Failed to elevate privileges: $($_.Exception.Message)"
    }
}

# --- Primary Functions ---

function Invoke-PrimaryWorkflow {
    <#
    .SYNOPSIS
        Executes the main workflow of checking for --no-verify flag.

    .DESCRIPTION
        Analyzes command line arguments to detect and prevent the use of
        the --no-verify flag in git operations.

    .NOTES
        This is the core functionality that enforces commit verification.
    #>
    [CmdletBinding()]
    param()

    Write-FormattedStep "Checking for --no-verify flag in arguments"

    $requiresElevation = $false

    if ($Args -contains '--no-verify') {
        Write-Host "Use of --no-verify is disabled and SHOULD NOT be bypassed" -ForegroundColor Red
        Write-Debug "Detected --no-verify flag in arguments: $Args"
        return 1
    }

    Write-FormattedStep "No --no-verify flag detected. Operation allowed."
}

# --- Main Script Execution ---

Initialize-ScriptEnvironment
Test-IsInteractivePowerShell

# Check for elevation if needed
$requiresElevation = $false
if ($requiresElevation -and -not (Test-IsAdministrator)) {
    Invoke-ElevationRequest
}

Invoke-PowerShellCoreTransition

try {
    Assert-WindowsPlatform
    $result = Invoke-PrimaryWorkflow
    if ($result -eq 1) {
        exit 1
    }
    Write-FormattedStep "Success: Operation completed successfully"
    exit 0
} catch {
    Write-Error -Message "Operation failed: $($_.Exception.Message)"
    Write-Debug -Message "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}
