@{
    RootModule           = 'powershell-core.psm1'
    ModuleVersion        = '0.0.0'
    GUID                 = '12345678-1234-1234-1234-123456789012'
    Author               = 'PowerShell Core Module Team'
    CompanyName          = 'Organization'
    Copyright            = '(c) 2026 PowerShell Core Module Team. All rights reserved.'
    Description          = 'Core functions for elevated PowerShell scripts including initialization, elevation, logging, and formatted output'
    PowerShellVersion    = '7.5.4'
    FunctionsToExport    = @(
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
    PrivateData          = @{
        PSData = @{
            Tags       = @('core', 'elevation', 'logging', 'utilities', 'powershell')
            ProjectUri = 'https://github.com/example/project'
            LicenseUri = 'https://github.com/example/project/LICENSE'
        }
    }
}
