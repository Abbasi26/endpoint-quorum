BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $manifest = Join-Path $script:ModuleRoot 'Quorum.psd1'
    Import-Module $manifest -Force
    InModuleScope Quorum {
        function global:New-QuorumTestRecord {
            param(
                [Parameter(Mandatory = $true)][string]$Source,
                $DeviceId,
                [string]$Hostname = 'lab-host',
                $ObservedAt,
                $ComplianceState,
                $AccountEnabled,
                $IsCompliant,
                $OperatingSystem,
                $OsBuild,
                $HealthStatus,
                $RiskScore,
                $OnboardingStatus,
                $IpAddress,
                $UserPrincipalName,
                $UserDisplayName
            )
            $parts = Get-QuorumHostnameParts $Hostname
            if ($null -eq $parts) { throw 'Test hostname is empty.' }
            New-QuorumRecord -Source $Source `
                -DeviceId $DeviceId `
                -HostnameOriginal $parts.Original `
                -HostnameRaw $parts.Raw `
                -HostnameKey $parts.Key `
                -ObservedAt $ObservedAt `
                -ComplianceState $ComplianceState `
                -AccountEnabled $AccountEnabled `
                -IsCompliant $IsCompliant `
                -OperatingSystem $OperatingSystem `
                -OsBuild $OsBuild `
                -HealthStatus $HealthStatus `
                -RiskScore $RiskScore `
                -OnboardingStatus $OnboardingStatus `
                -IpAddress $IpAddress `
                -UserPrincipalName $UserPrincipalName `
                -UserDisplayName $UserDisplayName
        }
    }
}

AfterAll {
    if (Test-Path Function:\New-QuorumTestRecord) {
        Remove-Item Function:\New-QuorumTestRecord
    }
    if (Get-Module Quorum) {
        Remove-Module Quorum -Force
    }
}

Describe 'Device matching' {
    It 'joins records that share an Entra device id and rates that match high' {
        InModuleScope Quorum {
            $id = '40000000-0000-4000-8000-0000000000aa'
            $intune = New-QuorumTestRecord -Source 'Intune' -DeviceId $id -Hostname 'WIN11-HEALTHY-01' -ComplianceState 'compliant'
            $entra = New-QuorumTestRecord -Source 'Entra' -DeviceId $id -Hostname 'other-name' -AccountEnabled $true -OperatingSystem 'Windows'
            $defender = New-QuorumTestRecord -Source 'Defender' -DeviceId $id -Hostname 'win11-healthy-01.lab.example' -OnboardingStatus 'onboarded'
            $devices = (Merge-QuorumDevice -Record @($intune, $entra, $defender))
            $devices.Count | Should -Be 1
            $devices[0].MatchMethod | Should -Be 'deviceId'
            $devices[0].MatchConfidence | Should -Be 'high'
            $devices[0].MatchScore | Should -Be 0.95
            @($devices[0].Records).Count | Should -Be 3
        }
    }

    It 'falls back to an exact hostname when a record has no device id' {
        InModuleScope Quorum {
            $intune = New-QuorumTestRecord -Source 'Intune' -DeviceId '40000000-0000-4000-8000-0000000000bb' -Hostname 'lab-kiosk-02'
            $defender = New-QuorumTestRecord -Source 'Defender' -Hostname 'lab-kiosk-02' -OnboardingStatus 'onboarded'
            $devices = (Merge-QuorumDevice -Record @($intune, $defender))
            $devices.Count | Should -Be 1
            $devices[0].MatchMethod | Should -Be 'hostname'
            $devices[0].MatchConfidence | Should -Be 'medium'
            $devices[0].MatchScore | Should -Be 0.70
        }
    }

    It 'falls back to the short hostname and rates that match low' {
        InModuleScope Quorum {
            $entra = New-QuorumTestRecord -Source 'Entra' -Hostname 'LAB-EDGE.lab.example' -AccountEnabled $true -OperatingSystem 'Windows'
            $defender = New-QuorumTestRecord -Source 'Defender' -Hostname 'lab-edge' -OnboardingStatus 'onboarded'
            $devices = (Merge-QuorumDevice -Record @($entra, $defender))
            $devices.Count | Should -Be 1
            $devices[0].MatchMethod | Should -Be 'hostname-normalized'
            $devices[0].MatchConfidence | Should -Be 'low'
            $devices[0].HostnameKey | Should -Be 'lab-edge'
        }
    }

    It 'keeps different device ids apart and marks the shared hostname as a duplicate' {
        InModuleScope Quorum {
            $left = New-QuorumTestRecord -Source 'Entra' -DeviceId '40000000-0000-4000-8000-0000000000c1' -Hostname 'shared-desk' -AccountEnabled $true -OperatingSystem 'Windows'
            $right = New-QuorumTestRecord -Source 'Entra' -DeviceId '40000000-0000-4000-8000-0000000000c2' -Hostname 'shared-desk' -AccountEnabled $true -OperatingSystem 'Windows'
            $devices = (Merge-QuorumDevice -Record @($left, $right))
            $devices.Count | Should -Be 2
            $devices[0].Duplicate | Should -BeTrue
            $devices[1].Duplicate | Should -BeTrue
            $devices[0].DuplicateCount | Should -Be 2
            $devices[0].MatchConfidence | Should -Be 'uncorroborated'
        }
    }

    It 'leaves a single source uncorroborated' {
        InModuleScope Quorum {
            $only = New-QuorumTestRecord -Source 'Intune' -DeviceId '40000000-0000-4000-8000-0000000000d1' -Hostname 'solo-laptop' -ComplianceState 'compliant'
            $devices = (Merge-QuorumDevice -Record @($only))
            $devices.Count | Should -Be 1
            $devices[0].MatchMethod | Should -Be 'single'
            $devices[0].MatchConfidence | Should -Be 'uncorroborated'
            $null -eq $devices[0].MatchScore | Should -BeTrue
        }
    }
}

Describe 'Rules' {
    BeforeAll {
        $global:QuorumAsOf = [datetime]::new(2026, 4, 15, 12, 0, 0, [DateTimeKind]::Utc)
        $global:QuorumRecent = [datetime]::new(2026, 4, 14, 12, 0, 0, [DateTimeKind]::Utc)
        $global:QuorumOld = [datetime]::new(2026, 1, 1, 12, 0, 0, [DateTimeKind]::Utc)
    }

    It 'loads the twelve starter rules' {
        InModuleScope Quorum {
            $rules = (Import-QuorumRule -Path (Join-QuorumPath $script:QuorumModuleRoot 'rules'))
            $rules.Count | Should -Be 12
            $ids = @($rules | ForEach-Object { $_.Id } | Sort-Object)
            $ids | Should -Contain 'Q001'
            $ids | Should -Contain 'Q012'
            @($rules | Where-Object { $_.Enabled }).Count | Should -Be 12
        }
    }

    It 'rejects a duplicate rule id and an unknown severity' {
        InModuleScope Quorum {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-rules-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            try {
                $body = @"
id: Q900
title: Example
severity: medium
description: Example rule.
whyItMatters: Example reason.
remediation: Example fix.
condition:
  all:
    - fact: intune.present
      op: eq
      value: true
"@
                $utf8 = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText((Join-Path $dir 'a.yaml'), $body, $utf8)
                [System.IO.File]::WriteAllText((Join-Path $dir 'b.yaml'), $body, $utf8)
                { Import-QuorumRule -Path $dir } | Should -Throw '*Duplicate rule id*'

                $bad = $body.Replace('severity: medium', 'severity: urgent')
                [System.IO.File]::WriteAllText((Join-Path $dir 'b.yaml'), $bad, $utf8)
                { Import-QuorumRule -Path $dir } | Should -Throw '*unknown severity*'
            }
            finally {
                Remove-Item -LiteralPath $dir -Recurse -Force
            }
        }
    }

    It 'flags a compliant Intune device whose Defender contact is stale' {
        InModuleScope Quorum {
            $id = '40000000-0000-4000-8000-0000000000e1'
            $intune = New-QuorumTestRecord -Source 'Intune' -DeviceId $id -Hostname 'silent-sensor' -ObservedAt $global:QuorumRecent -ComplianceState 'compliant' -OsBuild '26100'
            $defender = New-QuorumTestRecord -Source 'Defender' -DeviceId $id -Hostname 'silent-sensor' -ObservedAt $global:QuorumOld -OsBuild '26100' -OnboardingStatus 'onboarded' -HealthStatus 'active' -RiskScore 'low'
            $devices = (Merge-QuorumDevice -Record @($intune, $defender))
            $rules = (Import-QuorumRule -Path (Join-QuorumPath $script:QuorumModuleRoot 'rules'))
            $findings = (Invoke-QuorumRule -Device $devices -Rule $rules -AsOf $global:QuorumAsOf)
            $ids = @($findings | ForEach-Object { $_.RuleId })
            $ids | Should -Contain 'Q001'
            $ids | Should -Not -Contain 'Q003'
            $ids | Should -Not -Contain 'Q011'
        }
    }

    It 'flags an Intune device with no Defender record' {
        InModuleScope Quorum {
            $intune = New-QuorumTestRecord -Source 'Intune' -DeviceId '40000000-0000-4000-8000-0000000000e2' -Hostname 'no-sensor' -ObservedAt $global:QuorumRecent -ComplianceState 'compliant' -OsBuild '26100'
            $devices = (Merge-QuorumDevice -Record @($intune))
            $rule = (Import-QuorumRule -Path (Join-QuorumPath $script:QuorumModuleRoot 'rules' 'Q003-intune-without-defender.yaml'))
            $findings = (Invoke-QuorumRule -Device $devices -Rule $rule -AsOf $global:QuorumAsOf)
            $findings.Count | Should -Be 1
            $findings[0].RuleId | Should -Be 'Q003'
            $findings[0].Severity | Should -Be 'high'
        }
    }

    It 'flags an enabled Windows device that Intune does not know' {
        InModuleScope Quorum {
            $entra = New-QuorumTestRecord -Source 'Entra' -DeviceId '40000000-0000-4000-8000-0000000000e3' -Hostname 'unmanaged-win' -ObservedAt $global:QuorumRecent -AccountEnabled $true -OperatingSystem 'Windows' -OsBuild '26100'
            $devices = (Merge-QuorumDevice -Record @($entra))
            $rule = (Import-QuorumRule -Path (Join-QuorumPath $script:QuorumModuleRoot 'rules' 'Q002-entra-enabled-no-intune.yaml'))
            $findings = (Invoke-QuorumRule -Device $devices -Rule $rule -AsOf $global:QuorumAsOf)
            $findings.Count | Should -Be 1
            $findings[0].RuleId | Should -Be 'Q002'
        }
    }

    It 'flags an OS build mismatch and ignores a revision inside the same build' {
        InModuleScope Quorum {
            $id = '40000000-0000-4000-8000-0000000000e4'
            $mismatchIntune = New-QuorumTestRecord -Source 'Intune' -DeviceId $id -Hostname 'build-gap' -ObservedAt $global:QuorumRecent -ComplianceState 'compliant' -OsBuild '26100'
            $mismatchDefender = New-QuorumTestRecord -Source 'Defender' -DeviceId $id -Hostname 'build-gap' -ObservedAt $global:QuorumRecent -OsBuild '22631' -OnboardingStatus 'onboarded'
            $mismatch = (Merge-QuorumDevice -Record @($mismatchIntune, $mismatchDefender))
            $rule = (Import-QuorumRule -Path (Join-QuorumPath $script:QuorumModuleRoot 'rules' 'Q004-os-build-mismatch.yaml'))
            $hit = (Invoke-QuorumRule -Device $mismatch -Rule $rule -AsOf $global:QuorumAsOf)
            $hit.Count | Should -Be 1

            $sameIntune = New-QuorumTestRecord -Source 'Intune' -DeviceId $id -Hostname 'build-same' -OsBuild '26100'
            $sameDefender = New-QuorumTestRecord -Source 'Defender' -DeviceId $id -Hostname 'build-same' -OsBuild '26100'
            $same = (Merge-QuorumDevice -Record @($sameIntune, $sameDefender))
            $miss = (Invoke-QuorumRule -Device $same -Rule $rule -AsOf $global:QuorumAsOf)
            $miss.Count | Should -Be 0
        }
    }

    It 'groups duplicate hostnames into one finding' {
        InModuleScope Quorum {
            $left = New-QuorumTestRecord -Source 'Entra' -DeviceId '40000000-0000-4000-8000-0000000000e5' -Hostname 'shared-desk' -ObservedAt $global:QuorumRecent -AccountEnabled $true -OperatingSystem 'Windows'
            $right = New-QuorumTestRecord -Source 'Entra' -DeviceId '40000000-0000-4000-8000-0000000000e6' -Hostname 'shared-desk.lab.example' -ObservedAt $global:QuorumRecent -AccountEnabled $true -OperatingSystem 'Windows'
            $devices = (Merge-QuorumDevice -Record @($left, $right))
            $rule = (Import-QuorumRule -Path (Join-QuorumPath $script:QuorumModuleRoot 'rules' 'Q006-duplicate-hostname.yaml'))
            $findings = (Invoke-QuorumRule -Device $devices -Rule $rule -AsOf $global:QuorumAsOf)
            $findings.Count | Should -Be 1
            @($findings[0].QuorumIds).Count | Should -Be 2
            $findings[0].GroupKey | Should -Be 'shared-desk'
        }
    }

    It 'flags high Defender risk on a compliant Intune device' {
        InModuleScope Quorum {
            $id = '40000000-0000-4000-8000-0000000000e7'
            $intune = New-QuorumTestRecord -Source 'Intune' -DeviceId $id -Hostname 'risky-compliant' -ObservedAt $global:QuorumRecent -ComplianceState 'compliant' -OsBuild '26100'
            $defender = New-QuorumTestRecord -Source 'Defender' -DeviceId $id -Hostname 'risky-compliant' -ObservedAt $global:QuorumRecent -OsBuild '26100' -RiskScore 'High' -OnboardingStatus 'onboarded' -HealthStatus 'active'
            $devices = (Merge-QuorumDevice -Record @($intune, $defender))
            $rule = (Import-QuorumRule -Path (Join-QuorumPath $script:QuorumModuleRoot 'rules' 'Q007-defender-high-risk-intune-compliant.yaml'))
            $findings = (Invoke-QuorumRule -Device $devices -Rule $rule -AsOf $global:QuorumAsOf)
            $findings.Count | Should -Be 1
            $findings[0].Severity | Should -Be 'high'
        }
    }

    It 'does not run a disabled rule' {
        InModuleScope Quorum {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-off-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            try {
                $body = @"
id: Q901
title: Disabled
severity: low
enabled: false
description: Disabled rule.
whyItMatters: It should not fire.
remediation: Leave it disabled.
condition:
  all:
    - fact: intune.present
      op: eq
      value: true
"@
                $utf8 = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText((Join-Path $dir 'off.yaml'), $body, $utf8)
                $intune = New-QuorumTestRecord -Source 'Intune' -DeviceId '40000000-0000-4000-8000-0000000000e8' -Hostname 'still-here' -ComplianceState 'compliant'
                $devices = (Merge-QuorumDevice -Record @($intune))
                $rule = (Import-QuorumRule -Path $dir)
                $findings = (Invoke-QuorumRule -Device $devices -Rule $rule -AsOf $global:QuorumAsOf)
                $findings.Count | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $dir -Recurse -Force
            }
        }
    }
}

Describe 'Collector normalization' {
    It 'normalizes an Intune device, including the build and the device id' {
        InModuleScope Quorum {
            $item = [pscustomobject]@{
                id                   = '10000000-0000-4000-8000-0000000000aa'
                deviceName           = 'LAB-PC.lab.example'
                azureADDeviceId      = '40000000-0000-4000-8000-0000000000AA'
                userPrincipalName    = 'ada.example@lab.example'
                userDisplayName      = 'Ada Example'
                complianceState      = 'Compliant'
                osVersion            = '10.0.22631.5189'
                operatingSystem      = 'Windows'
                lastSyncDateTime     = '2026-04-01T00:00:00Z'
                isEncrypted          = $true
            }
            $records = @(ConvertTo-QuorumIntuneRecord -Item $item)
            $records.Count | Should -Be 1
            $records[0].Source | Should -Be 'Intune'
            $records[0].DeviceId | Should -Be '40000000-0000-4000-8000-0000000000aa'
            $records[0].HostnameKey | Should -Be 'lab-pc'
            $records[0].OsBuild | Should -Be '22631'
            $records[0].ComplianceState | Should -Be 'compliant'
            $records[0].UserPrincipalName | Should -Be 'ada.example@lab.example'
        }
    }

    It 'drops an all-zero Entra device id and keeps the sign-in as the observation time' {
        InModuleScope Quorum {
            $item = [pscustomobject]@{
                id                            = '20000000-0000-4000-8000-0000000000aa'
                deviceId                      = '00000000-0000-0000-0000-000000000000'
                displayName                   = 'orphan-object'
                accountEnabled                = $true
                operatingSystem               = 'Windows'
                operatingSystemVersion        = '10.0.26100.3775'
                approximateLastSignInDateTime = '2026-02-01T08:00:00Z'
                isCompliant                   = $false
            }
            $records = @(ConvertTo-QuorumEntraRecord -Item $item)
            $records.Count | Should -Be 1
            $null -eq $records[0].DeviceId | Should -BeTrue
            $records[0].AccountEnabled | Should -BeTrue
            $records[0].OsBuild | Should -Be '26100'
            $records[0].OperatingSystem | Should -Be 'windows'
            $null -eq $records[0].ObservedAt | Should -BeFalse
        }
    }

    It 'normalizes a Defender machine and prefers the numeric build' {
        InModuleScope Quorum {
            $item = [pscustomobject]@{
                id                = '30000000-0000-4000-8000-0000000000aa'
                computerDnsName   = 'sensor-01.lab.example'
                aadDeviceId       = '40000000-0000-4000-8000-0000000000bb'
                osBuild           = 26100
                osVersion         = '10.0.22631.1'
                lastSeen          = '2026-04-10T00:00:00Z'
                healthStatus      = 'Active'
                riskScore         = 'High'
                onboardingStatus  = 'Onboarded'
                lastIpAddress     = '203.0.113.44'
                osPlatform        = 'Windows10'
            }
            $records = @(ConvertTo-QuorumDefenderRecord -Item $item)
            $records.Count | Should -Be 1
            $records[0].Source | Should -Be 'Defender'
            $records[0].OsBuild | Should -Be '26100'
            $records[0].RiskScore | Should -Be 'high'
            $records[0].OnboardingStatus | Should -Be 'onboarded'
            $records[0].IpAddress | Should -Be '203.0.113.44'
            $records[0].HostnameKey | Should -Be 'sensor-01'
        }
    }
}

Describe 'Redaction' {
    It 'replaces the same hostname, UPN, and IP with one stable token inside a run' {
        InModuleScope Quorum {
            $model = [ordered]@{
                meta = [ordered]@{
                    note = 'See alpha-lab and alpha-lab, user ada.example@lab.example from 203.0.113.10.'
                }
                devices = @(
                    [ordered]@{
                        hostname = 'alpha-lab'
                        intune   = [ordered]@{
                            present    = $true
                            attributes = @(
                                [ordered]@{ key = 'hostname'; value = 'alpha-lab' }
                                [ordered]@{ key = 'upn'; value = 'ada.example@lab.example' }
                                [ordered]@{ key = 'user'; value = 'Ada Example' }
                                [ordered]@{ key = 'ip'; value = '203.0.113.10' }
                            )
                        }
                        entra    = $null
                        defender = $null
                    }
                    [ordered]@{
                        hostname = 'ALPHA-LAB'
                        intune   = $null
                        entra    = [ordered]@{
                            present    = $true
                            attributes = @(
                                [ordered]@{ key = 'hostname'; value = 'ALPHA-LAB' }
                            )
                        }
                        defender = $null
                    }
                )
                findings = @()
            }
            $map = (Protect-QuorumReport -Model $model)
            $hostEntries = @($map | Where-Object { $_.kind -eq 'host' -and $_.original.ToLowerInvariant() -eq 'alpha-lab' })
            $hostEntries.Count | Should -Be 1
            $token = [string]$hostEntries[0].token
            $token | Should -Match '^host-[0-9a-f]{12}$'
            $model.devices[0].hostname | Should -Be $token
            $model.devices[1].hostname | Should -Be $token
            $model.meta.note | Should -Not -Match 'alpha-lab'
            $model.meta.note | Should -Match ([regex]::Escape($token))
            $model.meta.note | Should -Not -Match 'ada\.example@lab\.example'
            $model.meta.note | Should -Not -Match '203\.0\.113\.10'
            $model.devices[0].intune.attributes[2].value | Should -Match '^user-'
        }
    }
}

Describe 'Invoke-Quorum -Demo' {
    BeforeAll {
        $script:DemoOut = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-demo-' + [guid]::NewGuid().ToString('n'))
        $script:RedactOut = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-redact-' + [guid]::NewGuid().ToString('n'))
        $script:DemoWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $script:DemoResult = Invoke-Quorum -Demo -OutputPath $script:DemoOut
        $script:DemoWatch.Stop()
        $script:RedactResult = Invoke-Quorum -Demo -Redact -OutputPath $script:RedactOut
    }

    AfterAll {
        foreach ($dir in @($script:DemoOut, $script:RedactOut)) {
            if ($dir -and (Test-Path -LiteralPath $dir)) {
                Remove-Item -LiteralPath $dir -Recurse -Force
            }
        }
    }

    It 'finishes offline in under a minute and writes every report' {
        $script:DemoWatch.Elapsed.TotalSeconds | Should -BeLessThan 60
        $script:DemoResult.Mode | Should -Be 'Demo'
        $script:DemoResult.DeviceCount | Should -BeGreaterOrEqual 45
        $script:DemoResult.FindingCount | Should -BeGreaterThan 0
        Test-Path -LiteralPath $script:DemoResult.HtmlPath | Should -BeTrue
        Test-Path -LiteralPath $script:DemoResult.MarkdownPath | Should -BeTrue
        Test-Path -LiteralPath $script:DemoResult.CsvPath | Should -BeTrue
        Test-Path -LiteralPath $script:DemoResult.JsonPath | Should -BeTrue
        $null -eq $script:DemoResult.RedactionMapPath | Should -BeTrue
    }

    It 'embeds the report data and does not call a CDN' {
        $html = [System.IO.File]::ReadAllText($script:DemoResult.HtmlPath)
        $html | Should -Not -Match '__QUORUM_DATA__'
        $html | Should -Match 'id="quorum-data"'
        $html | Should -Not -Match 'cdn|unpkg|jsdelivr|googleapis'
        $html | Should -Not -Match '<script[^>]+src='
        $html | Should -Not -Match '<link[^>]+href='
        $html | Should -Match 'win11-healthy-01'
        $markdown = [System.IO.File]::ReadAllText($script:DemoResult.MarkdownPath)
        $markdown | Should -Match '# Quorum summary'
        $csv = [System.IO.File]::ReadAllText($script:DemoResult.CsvPath)
        $csv | Should -Match 'RuleId'
    }

    It 'refuses to mix -Demo with a tenant' {
        { Invoke-Quorum -Demo -TenantId '00000000-0000-0000-0000-000000000000' -OutputPath $script:DemoOut } | Should -Throw '*cannot be combined*'
    }

    It 'pseudonymizes the shared demo report and writes a reversal map' {
        $html = [System.IO.File]::ReadAllText($script:RedactResult.HtmlPath)
        $markdown = [System.IO.File]::ReadAllText($script:RedactResult.MarkdownPath)
        $csv = [System.IO.File]::ReadAllText($script:RedactResult.CsvPath)
        foreach ($secret in @('win11-healthy-01', 'rowan.hale@lab.example', '203.0.113.11', 'Rowan Hale')) {
            $html | Should -Not -Match ([regex]::Escape($secret))
            $markdown | Should -Not -Match ([regex]::Escape($secret))
            $csv | Should -Not -Match ([regex]::Escape($secret))
        }
        Test-Path -LiteralPath $script:RedactResult.RedactionMapPath | Should -BeTrue
        $map = [System.IO.File]::ReadAllText($script:RedactResult.RedactionMapPath) | ConvertFrom-Json
        $hostEntry = @($map.entries | Where-Object { $_.original -eq 'win11-healthy-01' })
        $hostEntry.Count | Should -Be 1
        $html | Should -Match ([regex]::Escape([string]$hostEntry[0].token))
        @($map.entries | Where-Object { $_.original -eq 'rowan.hale@lab.example' }).Count | Should -Be 1
        @($map.entries | Where-Object { $_.original -eq '203.0.113.11' }).Count | Should -Be 1
    }
}