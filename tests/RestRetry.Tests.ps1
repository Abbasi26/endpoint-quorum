BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Quorum.psd1') -Force
}

Describe 'REST retry boundary' {
    It 'bounds retries for HTTP <Status>' -TestCases @(
        @{ Status = 429; Attempts = 4 }
        @{ Status = 403; Attempts = 1 }
    ) {
        param($Status, $Attempts)

        InModuleScope Quorum -Parameters @{
            Status = $Status
            Attempts = $Attempts
        } {
            param($Status, $Attempts)

            Mock Invoke-RestMethod { throw 'request-failed' }
            Mock Get-QuorumHttpStatus { $Status }
            Mock Start-Sleep {}

            {
                Invoke-QuorumRest `
                    -Uri 'https://api.example/devices' `
                    -Token 'fake-token'
            } | Should -Throw '*request-failed*'

            Should -Invoke Invoke-RestMethod -Times $Attempts -Exactly -Scope It
            Should -Invoke Invoke-RestMethod -Times $Attempts -Exactly -Scope It -ParameterFilter {
                $Method -eq 'GET' -and
                $Uri -eq 'https://api.example/devices' -and
                $Headers.Authorization -ceq 'Bearer fake-token'
            }

            Should -Invoke Start-Sleep -Times ($Attempts - 1) -Exactly -Scope It
            if ($Status -eq 429) {
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Seconds -eq 5
                }
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Seconds -eq 10
                }
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Seconds -eq 15
                }
            }
        }
    }
}
