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

    It 'imports as Quorum and exports only Invoke-Quorum and Test-QuorumRule' {
        $script:ImportedModule.Name | Should -BeExactly 'Quorum'
        @($script:ImportedModule.ExportedCommands.Keys).Count | Should -Be 2
        $script:ImportedModule.ExportedCommands.ContainsKey('Invoke-Quorum') |
            Should -BeTrue
        $script:ImportedModule.ExportedCommands.ContainsKey('Test-QuorumRule') |
            Should -BeTrue
    }

    It 'imports by manifest path from outside the repository' {
        Push-Location -LiteralPath $TestDrive
        try {
            $module = Import-Module $script:ManifestPath -Force -PassThru -ErrorAction Stop

            $module.Name | Should -BeExactly 'Quorum'
            $module.ModuleBase |
                Should -Be (Split-Path -Parent $script:ManifestPath)
            @($module.ExportedCommands.Keys).Count | Should -Be 1
            $module.ExportedCommands.ContainsKey('Invoke-Quorum') |
                Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }
}
