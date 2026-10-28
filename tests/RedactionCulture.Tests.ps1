BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Quorum.psd1') -Force
}

Describe 'Culture-invariant redaction' {
    It 'replaces ASCII hostname case variants under Turkish culture' {
        InModuleScope Quorum {
            $previousCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture =
                    [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')

                $plan = @{
                    Pattern = [regex]::Escape('intune-lab')
                    Map = @{
                        'intune-lab' = 'host-012345abcdef'
                    }
                }

                $actual = Update-QuorumSecretString `
                    -Text 'intune-lab INTUNE-LAB Intune-Lab' `
                    -Plan $plan

                $actual | Should -BeExactly (
                    'host-012345abcdef host-012345abcdef host-012345abcdef'
                )
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $previousCulture
            }
        }
    }
}
