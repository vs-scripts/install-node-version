<# :
@echo off
echo.
echo Error: This script must be run from a PowerShell terminal.
echo.
exit /b 1
#>

<#
.SYNOPSIS
    Installs and configures Volta to pin Node.js LTS to the repository.

.DESCRIPTION
    This script ensures Volta is installed on the system, adds it to the PATH,
    creates a package.json if needed, and pins the latest Node.js LTS version
    to the repository. Volta manages Node.js versions per-project.

.NOTES
    Author: Richeve Bebedor <richeve.bebedor+vs-scripts@gmail.com>
    Version: 0.0.0
    Platform: Windows only
    Requirements: PowerShell 5.1 or later (pwsh 7+ preferred), Administrator privileges

.EXAMPLE
    .\install-node-version.ps1
    Installs Volta and pins Node.js LTS to the current repository.

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
        Volta and winget dependencies in this script are currently targeted at Windows users.

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
        Write-FormattedStep "Installing Volta"
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

function Get-RepositoryRoot {
    <#
    .SYNOPSIS
        Determines the project root directory.

    .DESCRIPTION
        Attempts to find the git repository root using the git command.
        Falls back to the current working directory if git is unavailable.

    .OUTPUTS
        String - The absolute path to the repository root or current working directory.

    .EXAMPLE
        $root = Get-RepositoryRoot
        Returns the repository root path.
    #>
    [CmdletBinding()]
    param()

    [string]$repositoryRoot = $PWD.Path

    $gitCommand = Get-Command -Name 'git' -ErrorAction SilentlyContinue
    if ($gitCommand) {
        try {
            $detectedRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
            if ($detectedRoot -and (Test-Path -LiteralPath $detectedRoot)) {
                Write-Debug "Detected Git repository root: $detectedRoot"
                $repositoryRoot = $detectedRoot
            }
        } catch {
            Write-Debug "Git root detection failed, using current directory"
        }
    }

    return $repositoryRoot
}

function Install-PackageWithWinget {
    <#
    .SYNOPSIS
        Installs a package using the Windows Package Manager (winget).

    .DESCRIPTION
        Standardizes the winget installation command with agreements and
        silent flags. Throws if winget is missing.

    .PARAMETER PackageIdentifier
        The ID of the package to install (e.g., "Volta.Volta").

    .EXAMPLE
        Install-PackageWithWinget -PackageIdentifier "Volta.Volta"
        Installs Volta using winget.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Package identifier for winget")]
        [ValidateNotNullOrEmpty()]
        [string]$PackageIdentifier
    )

    $wingetCommand = Get-Command -Name 'winget' -ErrorAction SilentlyContinue
    if (-not $wingetCommand) {
        throw "Package '$PackageIdentifier' is not installed and 'winget' was not found."
    }

    Write-Debug "Executing: winget install --id $PackageIdentifier --silent --accept-package-agreements"
    & winget install --id $PackageIdentifier --source winget --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget installation for $PackageIdentifier failed (Exit Code: $LASTEXITCODE)"
    }
}

function Ensure-VoltaInstalled {
    <#
    .SYNOPSIS
        Ensures the Volta tool manager is installed on the system.

    .DESCRIPTION
        Checks for the 'volta' command. If missing, attempts to install it via winget.

    .EXAMPLE
        Ensure-VoltaInstalled
        Installs Volta if not already present.
    #>
    [CmdletBinding()]
    param()

    $voltaCommand = Get-Command -Name 'volta' -ErrorAction SilentlyContinue
    if ($voltaCommand) {
        Write-Verbose "Volta is already installed at: $($voltaCommand.Source)"
        return
    }

    Write-FormattedStep "Volta not found. Attempting to install via winget..."
    Install-PackageWithWinget -PackageIdentifier "Volta.Volta"
}

function Add-VoltaToSessionPath {
    <#
    .SYNOPSIS
        Ensures the Volta binary directory is in the current session's PATH.

    .DESCRIPTION
        Checks if the Volta bin directory exists and adds it to the session PATH
        if not already present. Uses case-insensitive comparison for path matching.

    .EXAMPLE
        Add-VoltaToSessionPath
        Adds Volta bin directory to the current session PATH.
    #>
    [CmdletBinding()]
    param()

    $voltaBinaryDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Volta\bin'

    if (-not (Test-Path -LiteralPath $voltaBinaryDirectory)) {
        Write-Debug "Creating Volta bin directory: $voltaBinaryDirectory"
        New-Item -ItemType Directory -Path $voltaBinaryDirectory -Force | Out-Null
    }

    $pathSeparator = [System.IO.Path]::PathSeparator
    $pathEntries = ($env:PATH -split $pathSeparator) | Where-Object { $_ -ne '' }

    $isVoltaInPath = $false
    foreach ($pathEntry in $pathEntries) {
        try {
            $normalizedPathEntry = [System.IO.Path]::GetFullPath($pathEntry).TrimEnd('\')
            $normalizedVoltaPath = [System.IO.Path]::GetFullPath($voltaBinaryDirectory).TrimEnd('\')
            if ($normalizedPathEntry -ieq $normalizedVoltaPath) {
                $isVoltaInPath = $true
                break
            }
        } catch {
            Write-Debug "Error normalizing path: $_"
        }
    }

    if (-not $isVoltaInPath) {
        Write-Verbose "Adding Volta bin to current session PATH: $voltaBinaryDirectory"
        $env:PATH = "$voltaBinaryDirectory$pathSeparator$env:PATH"
    }
}

function Initialize-PackageJsonIfMissing {
    <#
    .SYNOPSIS
        Ensures a package.json file exists for Volta pinning.

    .DESCRIPTION
        Volta requires package.json to pin versions. If missing, creates a minimal one
        with the directory name as the project name.

    .PARAMETER RepositoryRoot
        The directory where package.json should reside.

    .OUTPUTS
        String - The full path to the package.json file.

    .EXAMPLE
        $packageJsonPath = Initialize-PackageJsonIfMissing -RepositoryRoot "C:\Projects\MyRepo"
        Creates or returns the path to package.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Repository root directory path")]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $packageJsonPath = Join-Path -Path $RepositoryRoot -ChildPath 'package.json'

    if (Test-Path -LiteralPath $packageJsonPath) {
        Write-Verbose "Found existing package.json at $packageJsonPath"
        return $packageJsonPath
    }

    Write-FormattedStep "Creating minimal package.json at $packageJsonPath"
    $packageConfiguration = [ordered]@{
        name    = Split-Path -Leaf $RepositoryRoot
        private = $true
    }

    $jsonContent = $packageConfiguration | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $packageJsonPath -Value $jsonContent -Encoding UTF8
    Write-Verbose "Initialized new package.json"

    return $packageJsonPath
}

# --- Primary Functions ---

function Invoke-NodeVersionPinningWorkflow {
    <#
    .SYNOPSIS
        Executes the full workflow to install Volta and pin Node.js LTS locally.

    .DESCRIPTION
        Orchestrates Volta installation, PATH updates, package.json initialization,
        and Node.js LTS version pinning for the repository.

    .PARAMETER RepositoryRoot
        The directory context for pinning Node.js.

    .EXAMPLE
        Invoke-NodeVersionPinningWorkflow -RepositoryRoot "C:\Projects\MyRepo"
        Installs Volta and pins Node.js LTS to the specified repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Repository root directory path")]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    Write-FormattedStep "Initializing Node.js LTS Environment"
    Write-Debug "Target Directory: $RepositoryRoot"

    # 1. Ensure Volta is available
    Ensure-VoltaInstalled
    Add-VoltaToSessionPath

    # 2. Ensure package.json exists
    $null = Initialize-PackageJsonIfMissing -RepositoryRoot $RepositoryRoot

    # 3. Bind Node.js LTS to this folder
    Push-Location -Path $RepositoryRoot
    try {
        Write-FormattedStep "Pinning latest LTS Node.js to this folder"
        & volta pin node@lts --verbose

        # 4. Verify and display state
        Write-FormattedStep "Environment Verification"
        Write-Verbose "Active Node.js Version:"
        & node --version

        Write-Verbose "Volta Managed Versions in this folder:"
        & volta list node
    } finally {
        Pop-Location
    }
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
    $repositoryRoot = Get-RepositoryRoot
    Invoke-NodeVersionPinningWorkflow -RepositoryRoot $repositoryRoot

    Write-FormattedStep "Success: Node.js LTS is now bound to this folder and session."
    Write-Verbose "Usage: Run 'node' in ($repositoryRoot) to use the pinned version."
} catch {
    Write-Error -Message "Failed to install/pin Node.js: $($_.Exception.Message)" -ErrorAction Continue
    Write-Debug -Message "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}
