BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'Quorum.psd1') -Force
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-identity-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Work | Out-Null
}

AfterAll {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) {
        Remove-Item -LiteralPath $script:Work -Recurse -Force
    }
}

Describe 'Invoke-QuorumIdentityCheck' {
    It 'flags only the SMS or voice-only demo accounts' {
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'mfa') 6>$null
        $e001 = @($result.Findings | Where-Object { $_.CheckId -eq 'E001' })

        $e001.Count | Should -Be 5
        @($e001.UserPrincipalName) | Should -Contain 'sms.only.member@lab.example'
        @($e001.UserPrincipalName) | Should -Contain 'voice.office.member@lab.example'
        @($e001.UserPrincipalName) | Should -Contain 'mobile.email.member@lab.example'
        @($e001.UserPrincipalName) | Should -Contain 'admin.mobile.member@lab.example'
        @($e001.UserPrincipalName) | Should -Contain 'guest.mobile@lab.example'
        @($e001.UserPrincipalName) | Should -Not -Contain 'mobile.push.member@lab.example'
        @($e001.UserPrincipalName) | Should -Not -Contain 'passkey.only.member@lab.example'
        @($e001.UserPrincipalName) | Should -Not -Contain 'no.methods.member@lab.example'
    }

    It 'adds the limited July-date note for admin and guest accounts' {
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'notes') 6>$null
        $admin = @($result.Findings | Where-Object { $_.UserPrincipalName -eq 'admin.mobile.member@lab.example' })[0]
        $guest = @($result.Findings | Where-Object { $_.UserPrincipalName -eq 'guest.mobile@lab.example' })[0]
        $member = @($result.Findings | Where-Object { $_.UserPrincipalName -eq 'sms.only.member@lab.example' })[0]

        $admin.Note | Should -Match '2027-07-01'
        $guest.Note | Should -Match '2027-07-01'
        $member.Note | Should -Not -Match '2027-07-01'
        $member.Note | Should -Match 'Microsoft Security Store'
    }

    It 'flags memberOf rules regardless of processing state' {
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'memberof') 6>$null
        $e002 = @($result.Findings | Where-Object { $_.CheckId -eq 'E002' })

        $e002.Count | Should -Be 3
        @($e002.DisplayName) | Should -Contain 'Dynamic group with memberOf (On)'
        @($e002.DisplayName) | Should -Contain 'Dynamic group with memberOf (Paused)'
        @($e002.ObjectType) | Should -Contain 'administrativeUnit'
        @($e002.DisplayName) | Should -Not -Contain 'Dynamic group by department'
    }

    It 'accepts a plain JSON array as well as Graph pages' {
        $registrationPage = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'data/demo-identity/userRegistrationDetails.json') -Raw | ConvertFrom-Json
        $registrationPath = Join-Path $script:Work 'registrations-array.json'
        [System.IO.File]::WriteAllText($registrationPath, ($registrationPage.value | ConvertTo-Json -Depth 10))

        $result = Invoke-QuorumIdentityCheck -RegistrationDetailsPath $registrationPath -GroupsPath (Join-Path $script:ModuleRoot 'data/demo-identity/groups.json') -AdministrativeUnitsPath (Join-Path $script:ModuleRoot 'data/demo-identity/administrativeUnits.json') -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'array') 6>$null

        $result.FindingCount | Should -Be 8
    }

    It 'calculates retirement status and days from AsOf' {
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-11-04') -OutputPath (Join-Path $script:Work 'dates') 6>$null
        $e001 = @($result.Findings | Where-Object { $_.CheckId -eq 'E001' })[0]
        $e002 = @($result.Findings | Where-Object { $_.CheckId -eq 'E002' })[0]

        $e001.DaysUntilRetirement | Should -Be 89
        $e001.Status | Should -Be 'upcoming'
        $e002.DaysUntilRetirement | Should -Be -1
        $e002.Status | Should -Be 'retired'
    }

    It 'writes the three identity report files in demo mode' {
        $out = Join-Path $script:Work 'reports'
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath $out 6>$null

        Test-Path -LiteralPath $result.JsonPath | Should -BeTrue
        Test-Path -LiteralPath $result.CsvPath | Should -BeTrue
        Test-Path -LiteralPath $result.MarkdownPath | Should -BeTrue
        $result.HighestSeverity | Should -Be 'high'
    }

    It 'writes findings before FailOnSeverity throws' {
        $out = Join-Path $script:Work 'gate'

        { Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath $out -FailOnSeverity high 6>$null } | Should -Throw '*severity high or worse*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-IdentityFindings.json') | Should -BeTrue
    }

    It 'redacts user principal names in findings and reports' {
        $out = Join-Path $script:Work 'redacted'
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath $out -Redact 6>$null
        $json = Get-Content -LiteralPath $result.JsonPath -Raw

        @($result.Findings | Where-Object { $_.CheckId -eq 'E001' } | ForEach-Object { $_.UserPrincipalName }) | Should -Match '^user-[0-9a-f]{12}$'
        $json | Should -Not -Match 'sms.only.member@lab.example'
        $json | Should -Match 'user-[0-9a-f]{12}'
    }
}

Describe 'Invoke-QuorumIdentityCheck E003 Windows security baseline' {
    BeforeAll {
        $script:PolicyPath = Join-Path $script:ModuleRoot 'data/demo-identity/configurationPolicies.json'
    }

    It 'flags 24H2 and 23H2 as medium, an unknown version as low, and ignores the rest' {
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'e003-demo') 6>$null
        $e003 = @($result.Findings | Where-Object { $_.CheckId -eq 'E003' })

        $e003.Count | Should -Be 3
        @($e003 | Where-Object { $_.Severity -eq 'medium' } | ForEach-Object { $_.CurrentVersion }) | Should -Be @('Version 23H2', 'Version 24H2')
        $unknown = @($e003 | Where-Object { $_.Severity -eq 'low' })
        $unknown.Count | Should -Be 1
        $unknown[0].PolicyName | Should -Be 'LAB Windows baseline unknown version'
        $unknown[0].Note | Should -Match 'could not be determined'
        @($e003.PolicyName) | Should -Not -Contain 'LAB Windows baseline current'
        @($e003.PolicyName) | Should -Not -Contain 'LAB Defender for Endpoint baseline'
        @($e003.PolicyName) | Should -Not -Contain 'LAB settings catalog firewall'
    }

    It 'has no retirement date and status outdated' {
        $result = Invoke-QuorumIdentityCheck -Demo -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'e003-status') 6>$null
        $finding = @($result.Findings | Where-Object { $_.CheckId -eq 'E003' })[0]
        $finding.Status | Should -Be 'outdated'
        $finding.RetirementDate | Should -Be ''
        $finding.DaysUntilRetirement | Should -BeNullOrEmpty
        $finding.ExpectedVersion | Should -Be '26H2'
        Get-Content -LiteralPath $result.MarkdownPath -Raw | Should -Match 'Retirement date: none \(version check\)'
    }

    It 'uses -ExpectedWindowsBaseline for the comparison' {
        $result = Invoke-QuorumIdentityCheck -ConfigurationPoliciesPath $script:PolicyPath -ExpectedWindowsBaseline 25H2 -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'e003-25h2') 6>$null
        $medium = @($result.Findings | Where-Object { $_.CheckId -eq 'E003' -and $_.Severity -eq 'medium' })
        @($medium.CurrentVersion) | Should -Contain 'Version 24H2'
        @($medium.CurrentVersion) | Should -Contain 'Version 23H2'
        @($medium.CurrentVersion) | Should -Not -Contain 'Version 26H2'
    }

    It 'rejects an invalid -ExpectedWindowsBaseline' {
        { Invoke-QuorumIdentityCheck -ConfigurationPoliciesPath $script:PolicyPath -ExpectedWindowsBaseline '2026' -OutputPath (Join-Path $script:Work 'e003-bad') 6>$null } | Should -Throw
    }

    It 'treats a version without a yyHn token as older' {
        $path = Join-Path $script:Work 'policies-legacy.json'
        $items = @([pscustomobject]@{
            id = 'legacy-1'; name = 'LAB legacy'
            templateReference = [pscustomobject]@{ templateFamily = 'baseline'; templateDisplayName = 'Security Baseline for Windows 10 and later'; templateDisplayVersion = 'November 2021' }
        })
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $items -Depth 5))
        $result = Invoke-QuorumIdentityCheck -ConfigurationPoliciesPath $path -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'e003-legacy') 6>$null
        $result.FindingCount | Should -Be 1
        $result.Findings[0].Severity | Should -Be 'medium'
    }

    It 'accepts a plain array as well as a Graph page' {
        $page = Get-Content -LiteralPath $script:PolicyPath -Raw | ConvertFrom-Json
        $path = Join-Path $script:Work 'policies-array.json'
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject @($page.value) -Depth 10))
        $result = Invoke-QuorumIdentityCheck -ConfigurationPoliciesPath $path -AsOf ([datetime]'2026-10-29') -OutputPath (Join-Path $script:Work 'e003-array') 6>$null
        $result.FindingCount | Should -Be 3
        @($result.Notes) -join ' ' | Should -Match 'intents format'
    }
}
