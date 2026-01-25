<# :
@echo off
echo.
echo Error: This script must be run from a PowerShell terminal.
echo.
exit /b 1
#>

<#
.SYNOPSIS
    Configures SSH-Agent service for global access on Windows.

.DESCRIPTION
    This script ensures the SSH-Agent service is installed, configured, and running
    globally on the system. It installs OpenSSH Client if needed, configures the service
    for automatic startup, and sets up registry settings for global access.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Platform: Windows only
    Requirements: PowerShell 5.1 or later (pwsh 7+ preferred), Administrator privileges

.EXAMPLE
    .\start-global-ssh-agent.ps1
    Installs and configures SSH-Agent for global system access.

.EXIT CODES
    0 - Success
    1 - Failure (with error message)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest

# --- Core Functions ---

function Initialize-ScriptEnvironment {
    <#
    .SYNOPSIS
        Configures the PowerShell session preferences for consistent script behavior.

    .DESCRIPTION
        Sets script-level preferences for Verbose, Debug, ErrorAction, and Progress
        to ensure consistent and informative output throughout script execution.
        These settings apply only to the current script scope.

    .NOTES
        This function must be called early in script execution, before any other
        operations that depend on these preferences.

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

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Checks if the current process is running with administrative privileges.

    .DESCRIPTION
        Uses Windows Security API to determine if the current user identity
        belongs to the Administrator role.

    .OUTPUTS
        Boolean - True if user is administrator, False otherwise.

    .EXAMPLE
        if (Test-IsAdministrator) { Write-Host "Running as admin" }
        Checks for administrative privileges.
    #>
    [CmdletBinding()]
    param()

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = [Security.Principal.WindowsPrincipal]$currentIdentity
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-WindowsPlatform {
    <#
    .SYNOPSIS
        Ensures the script is running on a Windows platform.

    .DESCRIPTION
        Checks the $PSVersionTable.Platform or $env:OS environment variable.
        Throws an exception if the platform is not Windows.

    .NOTES
        SSH Agent configuration in this script is currently targeted at Windows users.

    .EXAMPLE
        Assert-WindowsPlatform
        Validates that the current platform is Windows.
    #>
    [CmdletBinding()]
    param()

    $isWindowsPlatform = ($PSVersionTable.Platform -eq 'Win32NT') -or
        ($env:OS -eq 'Windows_NT')
    if (-not $isWindowsPlatform) {
        throw "This script is currently Windows-only."
    }
}

function Test-IsInteractivePowerShell {
    <#
    .SYNOPSIS
        Verifies if the script is running in an interactive PowerShell host.

    .DESCRIPTION
        Checks the $Host name to ensure the script isn't running in a
        non-interactive background process where elevation prompts might fail.

    .EXAMPLE
        Test-IsInteractivePowerShell
        Validates that the current session is interactive.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $Host -or $Host.Name -eq "Default Host") {
        Write-Error -Message "This script must be run from an interactive PowerShell terminal."
        exit 1
    }
}

function Invoke-ElevationRequest {
    <#
    .SYNOPSIS
        Restarts the current script with elevated (administrator) privileges.

    .DESCRIPTION
        Uses Start-Process with the -Verb RunAs parameter to relaunch the script
        as administrator. If pwsh is available, it prefers it over powershell.exe.

    .EXAMPLE
        Invoke-ElevationRequest
        Requests elevation and relaunches the script as administrator.
    #>
    [CmdletBinding()]
    param()

    Write-Host -Object "==> Requesting administrative privileges..." -ForegroundColor Yellow

    $powerShellCoreCommand = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
    $executablePath = if ($powerShellCoreCommand) { $powerShellCoreCommand.Source } else { (Get-Process -Id $PID).Path }

    try {
        Start-Process -FilePath $executablePath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit 0
    } catch {
        Write-Error -Message "Elevation failed: $($_.Exception.Message)"
        exit 1
    }
}

function Invoke-PowerShellCoreTransition {
    <#
    .SYNOPSIS
        Transitions the script execution to PowerShell Core (pwsh) if available.

    .DESCRIPTION
        If the current major version is less than 7 and pwsh is found in the PATH,
        the script relaunches itself using pwsh for better performance and compatibility.

    .EXAMPLE
        Invoke-PowerShellCoreTransition
        Relaunches the script in PowerShell Core if available and version < 7.
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $powerShellCoreCommand = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
        if ($powerShellCoreCommand) {
            Write-Debug "Relaunching in PowerShell Core for better performance..."
            & $powerShellCoreCommand.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
            exit $LASTEXITCODE
        }
    }
}

function Write-FormattedStep {
    <#
    .SYNOPSIS
        Outputs a formatted step indicator to the console.

    .DESCRIPTION
        Uses Write-Host with specific colors and formatting to highlight major
        logical steps in the script execution.

    .PARAMETER Message
        The string message to display as a step indicator.

    .EXAMPLE
        Write-FormattedStep "Configuring SSH-Agent"
        Displays a formatted step message in cyan with bold font weight.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Step message to display")]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Host -Object "`n==> $Message" -ForegroundColor Cyan -FontWeight Bold
}

# --- Helper Functions ---

function Install-OpenSSHClientCapability {
    <#
    .SYNOPSIS
        Installs OpenSSH Client if not already present.

    .DESCRIPTION
        Uses Windows Capability features to install OpenSSH Client, which includes
        the SSH-Agent service.

    .EXAMPLE
        Install-OpenSSHClientCapability
        Installs OpenSSH Client on the system.
    #>
    [CmdletBinding()]
    param()

    $openSSHCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Client*' }
    if ($openSSHCapability) {
        Write-Debug "Installing OpenSSH Client..."
        Add-WindowsCapability -Online -Name $openSSHCapability.Name
        Write-Verbose "OpenSSH Client installed successfully."
    } else {
        throw "OpenSSH Client capability not found."
    }
}

function Install-SSHAgentServiceIfNotPresent {
    <#
    .SYNOPSIS
        Ensures SSH-Agent service is installed and available.

    .DESCRIPTION
        Checks for SSH-Agent service, installs OpenSSH Client if needed,
        and returns the service object.

    .OUTPUTS
        System.ServiceProcess.ServiceController - The SSH-Agent service object.

    .EXAMPLE
        $service = Ensure-SSHAgentServiceExists
        Ensures SSH-Agent service is available.
    #>
    [CmdletBinding()]
    param()

    $sshAgentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue

    if (-not $sshAgentService) {
        Write-FormattedStep "SSH-Agent service not found. Installing OpenSSH Client..."
        Install-OpenSSHClientCapability

        # Refresh service list
        $sshAgentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
        if (-not $sshAgentService) {
            throw "SSH-Agent service still not found after installation."
        }
    }

    Write-Verbose "SSH-Agent service found."
    return $sshAgentService
}

function Set-SSHAgentForGlobalAccess {
    <#
    .SYNOPSIS
        Configures SSH-Agent service for global access.

    .DESCRIPTION
        Sets service startup type to Automatic and configures registry settings
        to enable global SSH agent access for all users.

    .EXAMPLE
        Configure-SSHAgentForGlobalAccess
        Configures SSH-Agent for global system access.
    #>
    [CmdletBinding()]
    param()

    Write-FormattedStep "Configuring SSH-Agent service for global access"

    # Set service startup type to Automatic
    Set-Service -Name "ssh-agent" -StartupType Automatic -ErrorAction Stop
    Write-Verbose "SSH-Agent service set to start automatically."

    # Configure registry for global SSH agent access
    try {
        $registryPath = "HKLM:\SOFTWARE\OpenSSH"
        if (-not (Test-Path -LiteralPath $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
        }

        # Set agent to be available for all users
        Set-ItemProperty -Path $registryPath -Name "Agent" -Value "1" -Type String -Force
        Write-Verbose "Registry settings configured for global access."
    } catch {
        Write-Warning "Failed to configure registry settings: $($_.Exception.Message)"
        Write-Verbose "The service should still work, but some global settings may not apply."
    }
}

function Start-SSHAgentServiceAndVerify {
    <#
    .SYNOPSIS
        Starts the SSH-Agent service and verifies it is running.

    .DESCRIPTION
        Starts the SSH-Agent service if not already running and verifies
        the service status.

    .OUTPUTS
        System.ServiceProcess.ServiceController - The SSH-Agent service object.

    .EXAMPLE
        $service = Start-SSHAgentServiceAndVerify
        Starts SSH-Agent and returns the service object.
    #>
    [CmdletBinding()]
    param()

    $sshAgentService = Get-Service -Name "ssh-agent"

    if ($sshAgentService.Status -ne 'Running') {
        Write-FormattedStep "Starting SSH-Agent service..."
        Start-Service -Name "ssh-agent" -ErrorAction Stop
        Write-Verbose "SSH-Agent service started successfully."
    } else {
        Write-Verbose "SSH-Agent service is already running."
    }

    # Verify service status
    $serviceStatus = Get-Service -Name "ssh-agent"
    if ($serviceStatus.Status -eq 'Running') {
        Write-Verbose "SSH-Agent service is running and configured for global access."
        Write-Verbose "Service startup type: $($serviceStatus.StartType)"
        Write-Verbose "Service status: $($serviceStatus.Status)"
    } else {
        throw "SSH-Agent service failed to start properly. Current status: $($serviceStatus.Status)"
    }

    return $serviceStatus
}

# --- Primary Functions ---

function Invoke-SSHAgentConfigurationWorkflow {
    <#
    .SYNOPSIS
        Executes the full workflow to configure SSH-Agent globally.

    .DESCRIPTION
        Orchestrates OpenSSH installation, service configuration, and startup
        to enable global SSH-Agent access on the system.

    .EXAMPLE
        Invoke-SSHAgentConfigurationWorkflow
        Configures SSH-Agent for global system access.
    #>
    [CmdletBinding()]
    param()

    Write-FormattedStep "Initializing Global SSH-Agent Configuration"

    # 1. Ensure SSH-Agent service is available
    $null = Ensure-SSHAgentServiceExists

    # 2. Configure service for global access
    Configure-SSHAgentForGlobalAccess

    # 3. Start and verify the service
    Start-SSHAgentServiceAndVerify

    Write-FormattedStep "Success: SSH-Agent is now configured for global access."
    Write-Verbose "The SSH-Agent will start automatically for all users on system boot."
    Write-Verbose "Users can now use 'ssh-add' to manage their SSH keys."
}

# --- Main Script Execution ---

Initialize-ScriptEnvironment
Test-IsInteractivePowerShell

if (-not (Test-IsAdministrator)) {
    Invoke-ElevationRequest
}

Invoke-PowerShellCoreTransition

try {
    Assert-WindowsPlatform
    Invoke-SSHAgentConfigurationWorkflow

    # Final status check
    $finalServiceStatus = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
    if ($finalServiceStatus) {
        Write-Verbose "Final service status: $($finalServiceStatus.Status) (Startup: $($finalServiceStatus.StartType))"
    } else {
        Write-Warning "Could not verify final service status."
    }
} catch {
    Write-Error -Message "Failed to configure SSH-Agent: $($_.Exception.Message)" -ErrorAction Continue
    Write-Debug -Message "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}
