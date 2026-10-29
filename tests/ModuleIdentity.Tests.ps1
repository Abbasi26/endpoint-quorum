BeforeAll {
    $script:ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Quorum.psd1'
    $script:ImportedModule = Import-Module $script:ManifestPath -Force -PassThru
}

Describe 'Module identity' {
    It 'has a valid manifest with the expected identity metadata' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $manifest.Name | Should -BeExactly 'Quorum'
        $manifest.RootModule | Should -BeExactly 'Quorum.psm1'
        $manifest.PowerShellVersion | Should -Be ([version]'5.1')
    }

    It 'imports as Quorum and exports only Invoke-Quorum, Test-QuorumRule, and Invoke-QuorumIdentityCheck' {
        $script:ImportedModule.Name | Should -BeExactly 'Quorum'
        @($script:ImportedModule.ExportedCommands.Keys).Count | Should -Be 3
        $script:ImportedModule.ExportedCommands.ContainsKey('Invoke-Quorum') |
            Should -BeTrue
        $script:ImportedModule.ExportedCommands.ContainsKey('Test-QuorumRule') |
            Should -BeTrue
        $script:ImportedModule.ExportedCommands.ContainsKey('Invoke-QuorumIdentityCheck') |
            Should -BeTrue
    }

    It 'imports by manifest path from outside the repository' {
        Push-Location -LiteralPath $TestDrive
        try {
            $module = Import-Module $script:ManifestPath -Force -PassThru -ErrorAction Stop

            $module.Name | Should -BeExactly 'Quorum'
            $module.ModuleBase |
                Should -Be (Split-Path -Parent $script:ManifestPath)
            @($module.ExportedCommands.Keys).Count | Should -Be 3
            $module.ExportedCommands.ContainsKey('Invoke-Quorum') |
                Should -BeTrue
            $module.ExportedCommands.ContainsKey('Invoke-QuorumIdentityCheck') |
                Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }
}
