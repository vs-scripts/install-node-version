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
        Volta and winget dependencies in this script are currently targeted
        at Windows users.
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

function Install-PackageWithWinget {
    <#
    .SYNOPSIS
        Installs a package using the Windows Package Manager (winget).
    .DESCRIPTION
        Standardizes the winget installation command with agreements and
        silent flags. Throws if winget is missing.
    .PARAMETER PackageId
        The ID of the package to install (e.g., "Volta.Volta").
    #>
    param([string]$PackageId)

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Volta is not installed and 'winget' was not found."
    }

    Write-Debug
        "Executing: winget install --id $PackageId --silent
        --accept-package-agreements"
    & winget install --id $PackageId --source winget --silent
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning
            "winget installation for $PackageId failed (Code: $LASTEXITCODE)"
    }
}

function Ensure-VoltaInstalled {
    <#
    .SYNOPSIS
        Ensures the Volta tool manager is installed on the system.
    .DESCRIPTION
        Checks for the 'volta' command. If missing, attempts to install it.
    #>
    $cmd = Get-Command volta -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Verbose "Volta is already installed at: $($cmd.Source)"
        return
    }

    Write-Step "Volta not found. Attempting to install via winget..."
    Install-PackageWithWinget -PackageId "Volta.Volta"
}

function Ensure-VoltaOnPath {
    <#
    .SYNOPSIS
        Ensures the Volta binary directory is in the current session's PATH.
    .DESCRIPTION
        Checks if $env:LOCALAPPDATA\Volta\bin exists and is in $env:PATH.
    #>
    $voltaBin = Join-Path $env:LOCALAPPDATA 'Volta\bin'

    if (-not (Test-Path -LiteralPath $voltaBin)) {
        Write-Debug "Creating Volta bin directory if missing: $voltaBin"
        New-Item -ItemType Directory -Path $voltaBin -Force | Out-Null
    }

    $sep = [System.IO.Path]::PathSeparator
    $pathParts = ($env:PATH -split $sep) | Where-Object { $_ -ne '' }

    $already = $false
    foreach ($p in $pathParts) {
        try {
            $fullP = [System.IO.Path]::GetFullPath($p).TrimEnd('\')
            $fullV = [System.IO.Path]::GetFullPath($voltaBin).TrimEnd('\')
            if ($fullP -ieq $fullV) {
                $already = $true
                break
            }
        } catch {}
    }

    if (-not $already) {
        Write-Verbose "Adding Volta bin to current session PATH: $voltaBin"
        $env:PATH = "$voltaBin$sep$env:PATH"
    }
}

function Get-RepoRoot {
    <#
    .SYNOPSIS
        Determines the project root directory.
    .DESCRIPTION
        Attempts to find the git repository root. Fallbacks to CWD.
    .OUTPUTS
        String - The absolute path to the repository root or CWD.
    #>
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        try {
            $root = (& git rev-parse --show-toplevel 2>$null).Trim()
            if ($root -and (Test-Path -LiteralPath $root)) {
                Write-Debug "Detected Git repository root: $root"
                return $root
            }
        } catch {}
    }

    Write-Debug "No Git root detected. Using CWD: $($PWD.Path)"
    return $PWD.Path
}

function Ensure-PackageJson {
    <#
    .SYNOPSIS
        Ensures a package.json file exists for Volta pinning.
    .DESCRIPTION
        Volta requires package.json. If missing, it creates a minimal one.
    .PARAMETER Root
        The directory where package.json should reside.
    .OUTPUTS
        String - The full path to the package.json file.
    #>
    param([string]$Root)
    $pkgPath = Join-Path $Root 'package.json'

    if (Test-Path -LiteralPath $pkgPath) {
        Write-Verbose "Found existing package.json at $pkgPath"
        return $pkgPath
    }

    Write-Step "Creating minimal package.json at $pkgPath"
    $obj = [ordered]@{
        name = Split-Path -Leaf $Root
        private = $true
    }

    $json = ($obj | ConvertTo-Json -Depth 20)
    Set-Content -LiteralPath $pkgPath -Value $json -Encoding UTF8
    Write-Verbose "Initialized new package.json"

    return $pkgPath
}

function Invoke-NodePinningWorkflow {
    <#
    .SYNOPSIS
        Executes the full workflow to install Volta and pin Node.js LTS locally.
    .DESCRIPTION
        Orchestrates installation, PATH updates, and version pinning.
    .PARAMETER TargetDir
        The directory context for pinning Node.js.
    #>
    param([string]$TargetDir)

    Write-Step "Initializing Node.js LTS Environment"
    Write-Debug "Target Directory: $TargetDir"

    # 1. Ensure Volta is available
    Ensure-VoltaInstalled
    Ensure-VoltaOnPath

    # 2. Ensure package.json exists
    $null = Ensure-PackageJson -Root $TargetDir

    # 3. Bind Node.js LTS to this folder
    Push-Location $TargetDir
    try {
        Write-Step "Pinning latest LTS Node.js to this folder"
        & volta pin node@lts --verbose

        # 4. Verify and display state
        Write-Step "Environment Verification"
        Write-Verbose "Active Node.js Version:"
        & node --version

        Write-Verbose "Volta Managed Versions in this folder:"
        & volta list node
    } finally {
        Pop-Location
    }
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
    $root = Get-RepoRoot
    Invoke-NodePinningWorkflow -TargetDir $root

    Write-Step "Success: Node.js LTS is now bound to this folder and session."
    Write-Verbose "Usage: Run 'node' in ($root) to use the pinned version."
} catch {
    Write-Error "Failed to install/pin Node.js: $($_.Exception.Message)"
    Write-Debug "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}
