BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Quorum.psd1') -Force
}

Describe 'Pagination limit' {
    It 'handles terminal page <LastPage> with continuation <HasMore>' -TestCases @(
        @{ LastPage = 1999; HasMore = $false }
        @{ LastPage = 2000; HasMore = $false }
        @{ LastPage = 2000; HasMore = $true }
    ) {
        param($LastPage, $HasMore)

        InModuleScope Quorum -Parameters @{
            LastPage = $LastPage
            HasMore = $HasMore
        } {
            param($LastPage, $HasMore)

            Mock Invoke-QuorumRest {
                param($Uri, $Token)

                $number = [int]([uri]$Uri).Query.TrimStart('?')
                $nextLink = $null
                if ($number -lt $LastPage -or $HasMore) {
                    $nextLink = 'https://paging.example/pages?' + ($number + 1)
                }
                [pscustomobject]@{
                    value = @([pscustomobject]@{ id = $number })
                    '@odata.nextLink' = $nextLink
                }
            }

            if ($HasMore) {
                {
                    Get-QuorumPagedValue `
                        -Uri 'https://paging.example/pages?1' `
                        -Token 'fake-token'
                } | Should -Throw '*Stopped paging after 2000 pages:*'
            }
            else {
                $items = Get-QuorumPagedValue `
                    -Uri 'https://paging.example/pages?1' `
                    -Token 'fake-token'

                $items.Count | Should -Be $LastPage
                ($items.id -join ',') | Should -Be ((1..$LastPage) -join ',')
            }

            Should -Invoke Invoke-QuorumRest -Times $LastPage -Exactly -Scope It
        }
    }
}

# Skipped: renaming, unrelated pagination changes, and executing tests in this read-only review.
# Risk: inventories requiring more than 2000 pages still fail intentionally.
