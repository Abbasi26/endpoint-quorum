@{
    RootModule        = 'Quorum.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'abf01c94-fed2-46fe-acf1-993a0541dfdf'
    Author            = 'Wasaf Abbasi'
    Copyright         = '(c) 2026 Wasaf Abbasi. Licensed under the MIT License.'
    Description       = 'Read-only cross-source device contradictions for Intune, Entra ID, and Microsoft Defender for Endpoint.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-Quorum', 'Test-QuorumRule')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Security', 'Intune', 'Entra', 'Defender', 'Quorum')
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}