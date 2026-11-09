BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'Quorum.psd1') -Force
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-dir-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Work | Out-Null
    function script:Write-TestJson {
        param([string]$Name, $Value)
        $path = Join-Path $script:Work $Name
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $Value -Depth 20))
        return $path
    }
    # Fictional objects only. The ids are made up and do not exist in any tenant.
    $script:Groups = @(
        [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000001'; displayName = 'DYN-Test-MemberOf-Device'; groupTypes = @('DynamicMembership'); membershipRule = "device.memberof -any (group.objectId -in ['aaaaaaaa-0000-4000-8000-0000000000f1'])"; membershipRuleProcessingState = 'On' }
        [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000002'; displayName = 'DYN-Test-MemberOf-User-MixedCase'; groupTypes = @('Unified', 'DynamicMembership'); membershipRule = "(user.accountEnabled -eq true) and (User.MemberOf -any (group.objectId -in ['aaaaaaaa-0000-4000-8000-0000000000f2']))"; membershipRuleProcessingState = 'Paused' }
        [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000003'; displayName = 'DYN-Test-Attribute-Only'; groupTypes = @('DynamicMembership'); membershipRule = '(user.department -eq "memberof team")'; membershipRuleProcessingState = 'On' }
        [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000004'; displayName = 'Test-Assigned-With-Stale-Rule'; groupTypes = @(); membershipRule = "user.memberof -any (group.objectId -in ['aaaaaaaa-0000-4000-8000-0000000000f3'])"; membershipRuleProcessingState = $null }
    )
    $script:Units = @(
        [ordered]@{ id = 'bbbbbbbb-0000-4000-8000-000000000001'; displayName = 'AU-Test-MemberOf'; membershipType = 'Dynamic'; membershipRule = "user.memberof -any (group.objectId -in ['aaaaaaaa-0000-4000-8000-0000000000f4'])"; membershipRuleProcessingState = 'On' }
        [ordered]@{ id = 'bbbbbbbb-0000-4000-8000-000000000002'; displayName = 'AU-Test-Assigned'; membershipType = 'Assigned' }
    )
}

AfterAll {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) { Remove-Item -LiteralPath $script:Work -Recurse -Force }
}

Describe 'memberOf detection' {
    It 'recognises user.memberof and device.memberof in any case' {
        InModuleScope Quorum {
            Test-QuorumMemberOfRule "user.memberof -any (group.objectId -in ['x'])" | Should -BeTrue
            Test-QuorumMemberOfRule "DEVICE.MemberOf -any (group.objectId -in ['x'])" | Should -BeTrue
            Test-QuorumMemberOfRule '(user.department -eq "memberof team")' | Should -BeFalse
            Test-QuorumMemberOfRule '(user.memberofSomething -eq "x")' | Should -BeFalse
            Test-QuorumMemberOfRule '' | Should -BeFalse
            Test-QuorumMemberOfRule $null | Should -BeFalse
        }
    }
}

Describe 'Q013 dynamic memberOf rule' {
    It 'flags dynamic groups and dynamic AUs that use memberOf, and nothing else' {
        $groups = Write-TestJson 'groups.json' @{ value = $script:Groups }
        $units = Write-TestJson 'units.json' $script:Units
        $r = Invoke-Quorum -GroupPath $groups -AdministrativeUnitPath $units -RulesPath (Join-Path $script:ModuleRoot 'rules/Q013-dynamic-memberof-frozen.yaml') -OutputPath (Join-Path $script:Work 'q013') 6>$null
        $names = @($r.Findings | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $names | Should -Be @('AU-Test-MemberOf', 'DYN-Test-MemberOf-Device', 'DYN-Test-MemberOf-User-MixedCase')
        $r.DeviceCount | Should -Be 0
        @($r.Findings | ForEach-Object { $_['ruleId'] } | Select-Object -Unique) | Should -Be @('Q013')
        $au = @($r.Findings | Where-Object { $_['hostname'] -eq 'AU-Test-MemberOf' })[0]
        @($au['quorumIds']) | Should -Be @('au:bbbbbbbb-0000-4000-8000-000000000001')
        $kind = @($au['evidence'] | Where-Object { $_['key'] -eq 'directory.kind' })[0]
        $kind['value'] | Should -Be 'administrativeUnit'
        $status = @($r.CollectorStatus | Where-Object { $_['source'] -eq 'Entra groups and AUs' })[0]
        $status['recordCount'] | Should -Be 6
    }

    It 'reports the demo groups and AUs' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'demo') 6>$null
        $q013 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q013' })
        $q013.Count | Should -Be 3
        $r.DeviceCount | Should -Be 50
    }

    It 'does not let device rules see directory objects' {
        $groups = Write-TestJson 'groups-only.json' $script:Groups
        $r = Invoke-Quorum -GroupPath $groups -OutputPath (Join-Path $script:Work 'groups-only') 6>$null
        @($r.Findings | Where-Object { $_['ruleId'] -ne 'Q013' }).Count | Should -Be 0
    }
}

Describe 'Rule subject' {
    It 'rejects an unknown subject' {
        InModuleScope Quorum {
            $doc = [ordered]@{ id = 'X1'; title = 't'; severity = 'low'; description = 'd'; whyItMatters = 'w'; remediation = 'r'; subject = 'mailbox'; condition = [ordered]@{ fact = 'directory.dynamic'; op = 'eq'; value = $true } }
            { ConvertTo-QuorumRule $doc 'x.yaml' } | Should -Throw '*unknown subject*'
        }
    }

    It 'lints device facts in a directory rule as unknown' {
        $dir = Join-Path $script:Work 'lint'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $text = "id: X2`ntitle: t`nseverity: low`nsubject: directoryObject`ndescription: d`nwhyItMatters: w`nremediation: r`ncondition:`n  fact: intune.present`n  op: eq`n  value: true`n"
        [System.IO.File]::WriteAllText((Join-Path $dir 'X2.yaml'), $text)
        $check = @(Test-QuorumRule -Path $dir)[0]
        $check.Valid | Should -BeFalse
        ($check.Errors -join ' ') | Should -Match "unknown fact 'intune.present'"
    }

    It 'accepts the shipped Q013 rule' {
        $check = @(Test-QuorumRule -Path (Join-Path $script:ModuleRoot 'rules/Q013-dynamic-memberof-frozen.yaml'))[0]
        $check.Valid | Should -BeTrue
    }
}
