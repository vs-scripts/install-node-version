<# :
@echo off
echo.
echo Error: This script must be run from a PowerShell terminal.
echo.
exit /b 1
#>

[CmdletBinding()]
param()

function Set-ScriptEnvironment {
    $script:VerbosePreference = 'Continue'
    $script:DebugPreference = 'Continue'
    $script:ErrorActionPreference = 'Stop'
    $script:ProgressPreference = 'SilentlyContinue'
}

function Assert-WindowsPlatform {
    $isWindows = ($PSVersionTable.Platform -eq 'Win32NT') -or
        ($env:OS -eq 'Windows_NT')
    if (-not $isWindows) {
        throw "This script is currently Windows-only."
    }
}

function Test-IsInteractivePowerShell {
    if ($null -eq $Host -or $Host.Name -eq "Default Host") {
        Write-Error
            "This script must be run from an interactive PowerShell terminal."
        exit 1
    }
}

function Invoke-PowerShellCoreTransition {
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
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan -FontWeight Bold
}

function Get-RepoRoot {
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

function Invoke-VSCodeSettingsTemplateCopy {
    param([string]$RepoRoot)

    $templatePath = Join-Path $RepoRoot 'template\settings.json.template'
    $vscodeDir = Join-Path $RepoRoot '.vscode'
    $settingsPath = Join-Path $vscodeDir 'settings.json'

    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Template file not found: $templatePath"
    }

    $null = New-Item -ItemType Directory -Path $vscodeDir -Force

    Write-Step "Copying VS Code settings template"
    Write-Verbose "Source: $templatePath"
    Write-Verbose "Destination: $settingsPath"

    Copy-Item -LiteralPath $templatePath -Destination $settingsPath -Force
}

Set-ScriptEnvironment
Test-IsInteractivePowerShell
Invoke-PowerShellCoreTransition

try {
    Assert-WindowsPlatform
    $root = Get-RepoRoot
    Invoke-VSCodeSettingsTemplateCopy -RepoRoot $root

    Write-Step "Success: VS Code settings written to .vscode/settings.json"
} catch {
    Write-Error
        "Failed to copy VS Code settings template: $($_.Exception.Message)"
    Write-Debug "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}
