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
    Requirements: pwsh 7.5.4, Administrator privileges

.EXAMPLE
    .\install-node-version.ps1
    Installs Volta and pins Node.js LTS to the current repository.

.EXIT CODES
    0 - Success
    1 - Failure (with error message)
#>

[CmdletBinding()]
param()

$logPath = Join-Path -Path $PSScriptRoot -ChildPath 'concise-log.ps1'
if (-not (Test-Path -LiteralPath $logPath)) {
    Write-Error 'Required module not found: concise-log.ps1'

    exit 1
}
. $logPath

# --- Core Functions ---

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

    $isAdministrator = $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    Write-DebugLog -Scope "ELEVATION-ADMIN" `
        -Message "Administrator check: $isAdministrator"

    return $isAdministrator
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

    if (-not $Host.UI.RawUI) {
        Write-ErrorLog -Scope "ELEVATION-REQUEST" `
            -Message "Non-interactive session; run in interactive PowerShell."

        exit 1
    }

    Write-InfoLog -Scope "ELEVATION-REQUEST" `
        -Message "Requesting administrative privileges"

    $powerShellCoreCommand = Get-Command -Name 'pwsh' `
        -ErrorAction SilentlyContinue

    $executablePath = if ($powerShellCoreCommand) {
        $powerShellCoreCommand.Source
    } else {
        (Get-Process -Id $PID).Path
    }

    $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

    try {
        Start-Process -FilePath $executablePath `
            -ArgumentList $argumentList `
            -Verb RunAs

        exit 0
    } catch {
        Write-ErrorLog -Scope "ELEVATION-REQUEST" `
            -Message "Elevation failed: $($_.Exception.Message)"

        Write-DebugLog -Scope "ELEVATION-REQUEST" `
            -Message "Stack Trace: $($_.ScriptStackTrace)"
        exit 1
    }
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
        String - The absolute path to the repository root or current working
                    directory.

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
                Write-DebugLog -Scope "REPO-ROOT" `
                    -Message "Detected Git repository root: $detectedRoot"

                $repositoryRoot = $detectedRoot
            }
        } catch {
            Write-DebugLog -Scope "REPO-ROOT" `
                -Message "Git root detection failed, using current directory"
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
        [Parameter(Mandatory = $true, `
            HelpMessage = "Package identifier for winget")]
        [ValidateNotNullOrEmpty()]
        [string]$PackageIdentifier
    )

    $wingetCommand = Get-Command -Name 'winget' -ErrorAction SilentlyContinue
    if (-not $wingetCommand) {
        Write-ErrorLog -Scope "WINGET-INSTALL" `
            -Message "winget not found for package $PackageIdentifier"

        $failureMessage = "Package '$PackageIdentifier' is not installed " +
            "and winget was not found."

        throw $failureMessage
    }

    Write-DebugLog -Scope "WINGET-INSTALL" `
        -Message "Installing package $PackageIdentifier via winget"

    & winget install `
        --id $PackageIdentifier `
        --source winget `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -ne 0) {
        $warningMessage = "winget install failed for $PackageIdentifier " +
            "(exit $LASTEXITCODE)"

        Write-WarningLog -Scope "WINGET-INSTALL" `
            -Message $warningMessage

        Write-ErrorLog -Scope "WINGET-INSTALL" `
            -Message "winget install failed; aborting"

        throw $warningMessage
    }
}

function Install-VoltaIfMissing {
    <#
    .SYNOPSIS
        Installs Volta if it is not already available on the system.

    .DESCRIPTION
        Checks for the 'volta' command. If missing, attempts to install it
            via winget.

    .EXAMPLE
        Install-VoltaIfMissing
        Installs Volta if not already present.
    #>
    [CmdletBinding()]
    param()

    $voltaCommand = Get-Command -Name 'volta' -ErrorAction SilentlyContinue
    if ($voltaCommand) {
        Write-InfoLog -Scope "VOLTA-INSTALL" `
            -Message "Volta already installed at $($voltaCommand.Source)"

        return
    }

    Write-InfoLog -Scope "VOLTA-INSTALL" `
        -Message "Volta not found. Installing via winget."

    Install-PackageWithWinget -PackageIdentifier "Volta.Volta"

    $voltaCommand = Get-Command -Name 'volta' -ErrorAction SilentlyContinue
    if (-not $voltaCommand) {
        Write-ErrorLog -Scope "VOLTA-INSTALL" `
            -Message "Volta not found after installation"

        throw "Volta installation failed or not on PATH"
    }
}

function Add-VoltaToSessionPath {
    <#
    .SYNOPSIS
        Ensures the Volta binary directory is in the current session's PATH.

    .DESCRIPTION
        Checks if the Volta bin directory exists and adds it to the session PATH
        if not already present. Uses case-insensitive comparison for path matching.

    .EXAMPLE
        # Adds Volta bin directory to the current session PATH.
        Add-VoltaToSessionPath
    #>
    [CmdletBinding()]
    param()

    $voltaBinaryDirectory = Join-Path -Path $env:LOCALAPPDATA `
        -ChildPath 'Volta\bin'

    if (-not (Test-Path -LiteralPath $voltaBinaryDirectory)) {
        Write-DebugLog -Scope "VOLTA-PATH" `
            -Message "Creating Volta bin directory: $voltaBinaryDirectory"

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
        Write-DebugLog -Scope "VOLTA-PATH" `
            -Message "Path normalize error: $_"
        }
    }

    if (-not $isVoltaInPath) {
        Write-InfoLog -Scope "VOLTA-PATH" `
            -Message "Adding Volta bin to PATH: $voltaBinaryDirectory"

        $env:PATH = "$voltaBinaryDirectory$pathSeparator$env:PATH"
    }
}

function Initialize-PackageJsonIfMissing {
    <#
    .SYNOPSIS
        Ensures a package.json file exists for Volta pinning.

    .DESCRIPTION
        Volta requires package.json to pin versions. If missing,
        creates a minimal one with the directory name as the project name.

    .PARAMETER RepositoryRoot
        The directory where package.json should reside.

    .OUTPUTS
        String - The full path to the package.json file.

    .EXAMPLE
        # Creates or returns the path to package.json.
        $packageJsonPath = Initialize-PackageJsonIfMissing `
            -RepositoryRoot "C:\Projects\MyRepo"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, `
            HelpMessage = "Repository root directory path")]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $packageJsonPath = Join-Path -Path $RepositoryRoot -ChildPath 'package.json'

    if (Test-Path -LiteralPath $packageJsonPath) {
        Write-InfoLog -Scope "PACKAGE-JSON" `
            -Message "Found existing package.json at $packageJsonPath"

        return $packageJsonPath
    }

    Write-InfoLog -Scope "PACKAGE-JSON" `
        -Message "Creating minimal package.json"

    $packageConfiguration = [ordered]@{
        name    = Split-Path -Leaf $RepositoryRoot
        private = $true
    }

    $jsonContent = $packageConfiguration | ConvertTo-Json -Depth 20

    Set-Content -LiteralPath $packageJsonPath -Value $jsonContent -Encoding UTF8

    Write-InfoLog -Scope "PACKAGE-JSON" -Message "Initialized new package.json"

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
        # Installs Volta and pins Node.js LTS to the specified repository.
        Invoke-NodeVersionPinningWorkflow -RepositoryRoot "C:\Projects\MyRepo"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, `
            HelpMessage = "Repository root directory path")]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    Write-InfoLog -Scope "NODE-PIN" `
        -Message "Initializing Node.js LTS environment"

    Write-DebugLog -Scope "NODE-PIN" `
        -Message "Target directory: $RepositoryRoot"

    # 1. Ensure Volta is available
    Install-VoltaIfMissing
    Add-VoltaToSessionPath

    # 2. Ensure package.json exists
    $null = Initialize-PackageJsonIfMissing -RepositoryRoot $RepositoryRoot

    # 3. Bind Node.js LTS to this folder
    Push-Location -Path $RepositoryRoot
    try {
        Write-InfoLog -Scope "NODE-PIN" `
            -Message "Pinning latest LTS Node.js to this folder"

        & volta pin node@lts --verbose

        # 4. Verify and display state
        Write-InfoLog -Scope "NODE-VERIFY" `
            -Message "Environment verification"

        Write-InfoLog -Scope "NODE-VERIFY" -Message "Active Node.js version"

        & node --version

        Write-InfoLog -Scope "NODE-VERIFY" `
            -Message "Volta managed Node.js versions for this folder"

        & volta list node
    } finally {
        Pop-Location
    }
}

# --- Main Script Execution ---

Initialize-ScriptEnvironment
Test-IsInteractivePowerShell

Invoke-PowerShellCoreTransition
if (-not (Test-IsAdministrator)) {
    Invoke-ElevationRequest
}

try {
    Assert-WindowsPlatform

    $repositoryRoot = Get-RepositoryRoot

    Invoke-NodeVersionPinningWorkflow -RepositoryRoot $repositoryRoot

    Write-InfoLog -Scope "SCRIPT-MAIN" `
        -Message "Success: Node.js LTS now bound to this folder and session"

    Write-InfoLog -Scope "SCRIPT-MAIN" `
        -Message "Usage: run node in $repositoryRoot"

    exit 0
} catch {
    Write-ErrorLog -Scope "SCRIPT-MAIN" `
        -Message "Failed to install or pin Node.js"

    Write-DebugLog -Scope "SCRIPT-MAIN" `
        -Message "Stack Trace: $($_.ScriptStackTrace)"

    exit 1
}
