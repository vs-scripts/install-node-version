<# :
@echo off
echo.
echo Error: This script must be run from a PowerShell terminal.
echo.
exit /b 1
#>

[CmdletBinding()]
param()

# --- Configuration & Helpers ---

function Set-ScriptEnvironment {
    <#
    .SYNOPSIS
        Configures the PowerShell session preferences.
    .DESCRIPTION
        Sets Global/Script level Verbose, Debug, ErrorAction, and Progress
        preferences to ensure consistent and informative script output.
    #>
    $script:VerbosePreference = 'Continue'
    $script:DebugPreference = 'Continue'
    $script:ErrorActionPreference = 'Stop'
    $script:ProgressPreference = 'SilentlyContinue'
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if the current process is running with administrative privileges.
    .DESCRIPTION
        Uses Windows Security API to determine if the current user identity
        belongs to the Administrator role.
    .OUTPUTS
        Boolean - True if user is admin, False otherwise.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-WindowsPlatform {
    <#
    .SYNOPSIS
        Ensures the script is running on a Windows platform.
    .DESCRIPTION
        Checks the $PSVersionTable.Platform or $env:OS environment variable.
        Throws an exception if the platform is not Windows.
    .NOTES
        SSH Agent configuration is currently targeted at Windows users.
    #>
    $isWindows = ($PSVersionTable.Platform -eq 'Win32NT') -or
        ($env:OS -eq 'Windows_NT')
    if (-not $isWindows) {
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
    #>
    if ($null -eq $Host -or $Host.Name -eq "Default Host") {
        Write-Error
            "This script must be run from an interactive PowerShell terminal."
        exit 1
    }
}

function Invoke-Elevation {
    <#
    .SYNOPSIS
        Restarts the current script with elevated (administrator) privileges.
    .DESCRIPTION
        Uses Start-Process with the -Verb RunAs parameter to relaunch the script
        as administrator. If pwsh is available, it prefers it over powershell.exe.
    #>
    Write-Host "==> Requesting administrative privileges..."
        -ForegroundColor Yellow

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    $exe = if ($pwsh) { $pwsh.Source } else { (Get-Process -Id $PID).Path }

    try {
        Start-Process $exe -ArgumentList
            "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            -Verb RunAs
        exit 0
    } catch {
        Write-Error "Elevation failed: $($_.Exception.Message)"
        exit 1
    }
}

function Invoke-PowerShellCoreTransition {
    <#
    .SYNOPSIS
        Transitions the script execution to PowerShell Core (pwsh) if available.
    .DESCRIPTION
        If the current major version is less than 7 and pwsh is found in the PATH,
        the script relaunches itself using pwsh for better performance.
    #>
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh) {
            Write-Debug "Relaunching in PowerShell Core for better performance..."
            & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File
                $PSCommandPath @args
            exit $LASTEXITCODE
        }
    }
}

function Write-Step {
    <#
    .SYNOPSIS
        Outputs a formatted step indicator to the console.
    .DESCRIPTION
        Uses Write-Host with specific colors and formatting to highlight major
        logical steps in the script.
    .PARAMETER Message
        The string message to display.
    #>
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan -FontWeight Bold
}

function Install-OpenSSHClient {
    <#
    .SYNOPSIS
        Installs OpenSSH Client if not already present.
    .DESCRIPTION
        Uses Windows Capability features to install OpenSSH Client.
    #>
    $capability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Client*' }
    if ($capability) {
        Write-Debug "Installing OpenSSH Client..."
        Add-WindowsCapability -Online -Name $capability.Name
        Write-Verbose "OpenSSH Client installed successfully."
    } else {
        throw "OpenSSH Client capability not found."
    }
}

function Ensure-SSHAgentService {
    <#
    .SYNOPSIS
        Ensures SSH-Agent service is installed and configured.
    .DESCRIPTION
        Checks for SSH-Agent service, installs OpenSSH if needed, and configures service settings.
    #>
    $sshAgentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue

    if (-not $sshAgentService) {
        Write-Step "SSH-Agent service not found. Installing OpenSSH Client..."
        Install-OpenSSHClient

        # Refresh service list
        $sshAgentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
        if (-not $sshAgentService) {
            throw "SSH-Agent service still not found after installation."
        }
    }

    Write-Verbose "SSH-Agent service found."
    return $sshAgentService
}

function Configure-SSHAgentService {
    <#
    .SYNOPSIS
        Configures SSH-Agent service for global access.
    .DESCRIPTION
        Sets service startup type to Automatic and configures registry settings.
    #>
    Write-Step "Configuring SSH-Agent service for global access"

    # Set service startup type to Automatic
    Set-Service -Name "ssh-agent" -StartupType Automatic -ErrorAction Stop
    Write-Verbose "SSH-Agent service set to start automatically."

    # Configure registry for global SSH agent access
    try {
        $registryPath = "HKLM:\SOFTWARE\OpenSSH"
        if (-not (Test-Path $registryPath)) {
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

function Start-SSHAgentService {
    <#
    .SYNOPSIS
        Starts the SSH-Agent service.
    .DESCRIPTION
        Starts the service and verifies it's running properly.
    #>
    $sshAgentService = Get-Service -Name "ssh-agent"

    if ($sshAgentService.Status -ne 'Running') {
        Write-Step "Starting SSH-Agent service..."
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

function Invoke-SSHAgentWorkflow {
    <#
    .SYNOPSIS
        Executes the full workflow to configure SSH-Agent globally.
    .DESCRIPTION
        Orchestrates OpenSSH installation, service configuration, and startup.
    #>
    Write-Step "Initializing Global SSH-Agent Configuration"

    # 1. Ensure SSH-Agent service is available
    $null = Ensure-SSHAgentService

    # 2. Configure service for global access
    Configure-SSHAgentService

    # 3. Start and verify the service
    $finalStatus = Start-SSHAgentService

    Write-Step "Success: SSH-Agent is now configured for global access."
    Write-Verbose "The SSH-Agent will start automatically for all users on system boot."
    Write-Verbose "Users can now use 'ssh-add' to manage their SSH keys."
}

# --- Main Script Execution ---
Set-ScriptEnvironment
Test-IsInteractivePowerShell

if (-not (Test-IsAdmin)) {
    Invoke-Elevation
}

Invoke-PowerShellCoreTransition

try {
    Assert-WindowsPlatform
    Invoke-SSHAgentWorkflow

    # Final status check
    $finalStatus = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
    if ($finalStatus) {
        Write-Verbose "Final service status: $($finalStatus.Status) (Startup: $($finalStatus.StartType))"
    } else {
        Write-Warning "Could not verify final service status."
    }
} catch {
    Write-Error "Failed to configure SSH-Agent: $($_.Exception.Message)"
    Write-Debug "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}
