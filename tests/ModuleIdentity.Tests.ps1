BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'Quorum.psd1'
    $script:ImportedModule = Import-Module $manifest -Force -PassThru
}

Describe 'Module identity' {
    It 'imports as Quorum and exports only Invoke-Quorum' {
        $script:ImportedModule.Name | Should -BeExactly 'Quorum'
        @($script:ImportedModule.ExportedCommands.Keys).Count | Should -Be 1
        $script:ImportedModule.ExportedCommands.ContainsKey('Invoke-Quorum') |
            Should -BeTrue
    }
}

# Skipped: renaming and runtime changes; tests were not executed during this review.
# Risk: the reference test still needs validation on the existing CI matrix.
