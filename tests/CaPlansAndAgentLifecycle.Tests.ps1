BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'Quorum.psd1') -Force
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-gov-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Work | Out-Null
    function script:Write-TestJson {
        param([string]$Name, $Value)
        $path = Join-Path $script:Work $Name
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $Value -Depth 20))
        return $path
    }
}

AfterAll {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) { Remove-Item -LiteralPath $script:Work -Recurse -Force }
}

Describe 'Conditional Access policy plan facts' {
    It 'counts enforcing, report-only and disabled rules, and missing owners' {
        InModuleScope Quorum {
            $plans = @(
                [pscustomobject]@{
                    id          = 'aaaaaaaa-0000-4000-8000-000000000001'
                    displayName = 'Enforcing Plan'
                    owners      = @('aaaaaaaa-0000-4000-8000-0000000000e1')
                    rules       = @(
                        [pscustomobject]@{ id = 'r1'; state = 'enabled' }
                        [pscustomobject]@{ id = 'r2'; state = 'disabled' }
                    )
                }
                [pscustomobject]@{
                    id          = 'aaaaaaaa-0000-4000-8000-000000000002'
                    displayName = 'Report Only Plan'
                    owners      = @()
                    rules       = @(
                        [pscustomobject]@{ id = 'r3'; state = 'enabledForReportingButNotEnforced' }
                    )
                }
                [pscustomobject]@{
                    id                 = 'aaaaaaaa-0000-4000-8000-000000000003'
                    displayName        = 'Count Only Plan'
                    owners             = @('aaaaaaaa-0000-4000-8000-0000000000e2')
                    'rules@odata.count' = 4
                }
            )
            $items = @(ConvertTo-QuorumConditionalAccessPlan -Plan $plans)
            $items.Count | Should -Be 3
            $items[0].Facts['plan.hasEnforcingRule'] | Should -BeTrue
            $items[0].Facts['plan.enforcingRuleCount'] | Should -Be 1
            $items[0].Facts['plan.disabledRuleCount'] | Should -Be 1
            $items[0].Facts['plan.hasOwners'] | Should -BeTrue
            $items[1].Facts['plan.hasEnforcingRule'] | Should -BeFalse
            $items[1].Facts['plan.reportOnlyRuleCount'] | Should -Be 1
            $items[1].Facts['plan.hasOwners'] | Should -BeFalse
            $items[2].Facts['plan.ruleCount'] | Should -Be 4
            $items[2].Facts['plan.hasEnforcingRule'] | Should -Be $null
            $items[2].Facts['plan.rulesExpanded'] | Should -BeFalse
        }
    }
}

Describe 'Q014 and Q015 Conditional Access policy plans' {
    It 'flags plans with no enforcing rule or no owners, and ignores count-only exports' {
        $plans = Write-TestJson 'plans.json' @{
            value = @(
                [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000001'; displayName = 'Lab Enforcing'; owners = @('aaaaaaaa-0000-4000-8000-0000000000e1'); rules = @([ordered]@{ id = 'r1'; state = 'enabled' }) }
                [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000002'; displayName = 'Lab No Owners'; owners = @(); rules = @([ordered]@{ id = 'r2'; state = 'enabled' }) }
                [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000003'; displayName = 'Lab Report Only'; owners = @('aaaaaaaa-0000-4000-8000-0000000000e1'); rules = @([ordered]@{ id = 'r3'; state = 'enabledForReportingButNotEnforced' }) }
                [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000004'; displayName = 'Lab Empty'; owners = @('aaaaaaaa-0000-4000-8000-0000000000e1'); rules = @() }
                [ordered]@{ id = 'aaaaaaaa-0000-4000-8000-000000000005'; displayName = 'Lab Count Only'; owners = @('aaaaaaaa-0000-4000-8000-0000000000e1'); 'rules@odata.count' = 2 }
            )
        }
        $rules = Join-Path $script:ModuleRoot 'rules'
        $r = Invoke-Quorum -ConditionalAccessPlanPath $plans -RulesPath $rules -OutputPath (Join-Path $script:Work 'plans') 6>$null
        $q014 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q014' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q015 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q015' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q014 | Should -Be @('Lab Empty', 'Lab Report Only')
        $q015 | Should -Be @('Lab No Owners')
        $r.DeviceCount | Should -Be 0
        $status = @($r.CollectorStatus | Where-Object { $_['source'] -eq 'Entra Conditional Access plans' })[0]
        $status['recordCount'] | Should -Be 5
    }
}

Describe 'Agent ID lifecycle policy facts' {
    It 'ignores guest policies and summarises enabled agent policies' {
        InModuleScope Quorum {
            $raw = @(
                [pscustomobject]@{
                    '@odata.type'  = '#microsoft.graph.identityGovernance.agentIdentityLifecyclePolicy'
                    id             = 'bbbbbbbb-0000-4000-8000-000000000001'
                    displayName    = 'Default policy'
                    policySource   = 'systemDefault'
                    isEnabled      = $false
                    versionNumber  = 1
                    enforcementAction = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.identityGovernance.disableThenDeleteEnforcementAction' }
                    rules          = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.identityGovernance.inactivityRule'; isEnabled = $true })
                }
                [pscustomobject]@{
                    '@odata.type' = '#microsoft.graph.identityGovernance.guestLifecyclePolicy'
                    id            = 'bbbbbbbb-0000-4000-8000-000000000002'
                    displayName   = 'Guest policy'
                    policySource  = 'userCreated'
                    isEnabled     = $true
                }
            )
            $pack = New-QuorumLifecyclePolicySet -Policy $raw
            $pack.Policies.Count | Should -Be 2
            $pack.Policies[0].Facts['lifecyclePolicy.isAgentIdentity'] | Should -BeTrue
            $pack.Policies[0].Facts['lifecyclePolicy.isSystemDefault'] | Should -BeTrue
            $pack.Policies[0].Facts['lifecyclePolicy.enforcementKind'] | Should -Be 'disableThenDelete'
            $pack.Policies[1].Facts['lifecyclePolicy.isAgentIdentity'] | Should -BeFalse
            $pack.Set.Facts['lifecyclePolicySet.agentPolicyCount'] | Should -Be 1
            $pack.Set.Facts['lifecyclePolicySet.enabledAgentPolicyCount'] | Should -Be 0
            $pack.Set.Facts['lifecyclePolicySet.defaultPresent'] | Should -BeTrue
            $pack.Set.Facts['lifecyclePolicySet.defaultEnabled'] | Should -BeFalse
        }
    }
}

Describe 'Q016 Agent ID lifecycle policies' {
    It 'flags when no agent policy is enabled, even if a guest policy is on' {
        $policies = Write-TestJson 'policies.json' @(
            [ordered]@{ '@odata.type' = '#microsoft.graph.identityGovernance.agentIdentityLifecyclePolicy'; id = 'bbbbbbbb-0000-4000-8000-000000000001'; displayName = 'Default'; policySource = 'systemDefault'; isEnabled = $false }
            [ordered]@{ '@odata.type' = '#microsoft.graph.identityGovernance.guestLifecyclePolicy'; id = 'bbbbbbbb-0000-4000-8000-000000000002'; displayName = 'Guest'; policySource = 'userCreated'; isEnabled = $true }
        )
        $r = Invoke-Quorum -LifecyclePolicyPath $policies -RulesPath (Join-Path $script:ModuleRoot 'rules/Q016-no-enabled-agent-lifecycle-policy.yaml') -OutputPath (Join-Path $script:Work 'q016-off') 6>$null
        @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q016' }).Count | Should -Be 1
    }

    It 'does not flag when a custom Agent ID policy is enabled' {
        $policies = Write-TestJson 'policies-on.json' @(
            [ordered]@{ '@odata.type' = '#microsoft.graph.identityGovernance.agentIdentityLifecyclePolicy'; id = 'bbbbbbbb-0000-4000-8000-000000000001'; displayName = 'Default'; policySource = 'systemDefault'; isEnabled = $false }
            [ordered]@{ '@odata.type' = '#microsoft.graph.identityGovernance.agentIdentityLifecyclePolicy'; id = 'bbbbbbbb-0000-4000-8000-000000000003'; displayName = 'Custom'; policySource = 'userCreated'; isEnabled = $true }
        )
        $r = Invoke-Quorum -LifecyclePolicyPath $policies -RulesPath (Join-Path $script:ModuleRoot 'rules/Q016-no-enabled-agent-lifecycle-policy.yaml') -OutputPath (Join-Path $script:Work 'q016-on') 6>$null
        @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q016' }).Count | Should -Be 0
    }
}

Describe 'Q017 and Q018 agent identities' {
    It 'flags an enabled agent with no governing policy or no sponsors, and skips disabled or unexpanded objects' {
        $agents = Write-TestJson 'agents.json' @(
            [ordered]@{ id = 'cccccccc-0000-4000-8000-000000000001'; displayName = 'Lab Governed'; accountEnabled = $true; sponsors = @([ordered]@{ id = 's1' }); lifecycle = [ordered]@{ effectiveGoverningPolicy = [ordered]@{ id = 'p1' } } }
            [ordered]@{ id = 'cccccccc-0000-4000-8000-000000000002'; displayName = 'Lab No Sponsors'; accountEnabled = $true; sponsors = @(); lifecycle = [ordered]@{ effectiveGoverningPolicy = [ordered]@{ id = 'p1' } } }
            [ordered]@{ id = 'cccccccc-0000-4000-8000-000000000003'; displayName = 'Lab No Policy'; accountEnabled = $true; sponsors = @([ordered]@{ id = 's2' }); lifecycle = [ordered]@{ effectiveGoverningPolicy = $null } }
            [ordered]@{ id = 'cccccccc-0000-4000-8000-000000000004'; displayName = 'Lab Disabled'; accountEnabled = $false; sponsors = @(); lifecycle = [ordered]@{ effectiveGoverningPolicy = $null } }
            [ordered]@{ id = 'cccccccc-0000-4000-8000-000000000005'; displayName = 'Lab Not Expanded'; accountEnabled = $true }
        )
        $rulesDir = Join-Path $script:Work 'agent-rules'
        New-Item -ItemType Directory -Path $rulesDir | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:ModuleRoot 'rules/Q017-agent-without-governing-lifecycle-policy.yaml') -Destination $rulesDir
        Copy-Item -LiteralPath (Join-Path $script:ModuleRoot 'rules/Q018-agent-without-sponsors.yaml') -Destination $rulesDir
        $r = Invoke-Quorum -AgentIdentityPath $agents -RulesPath $rulesDir -OutputPath (Join-Path $script:Work 'agents') 6>$null
        $q017 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q017' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q018 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q018' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q017 | Should -Be @('Lab No Policy')
        $q018 | Should -Be @('Lab No Sponsors')
        $r.DeviceCount | Should -Be 0
    }
}

Describe 'Demo inventory for policy plans and Agent ID' {
    It 'reports the expected demo findings without changing the device count' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'demo') 6>$null
        $r.DeviceCount | Should -Be 51
        $r.FindingCount | Should -Be 44
        @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q013' }).Count | Should -Be 3
        $q014 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q014' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q015 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q015' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q016 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q016' })
        $q017 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q017' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q018 = @($r.Findings | Where-Object { $_['ruleId'] -eq 'Q018' } | ForEach-Object { [string]$_['hostname'] } | Sort-Object)
        $q014 | Should -Be @('Lab Empty Rule Plan', 'Lab Report-Only Network Plan')
        $q015 | Should -Be @('Lab Agent Access Plan Without Owners')
        $q016.Count | Should -Be 1
        $q017 | Should -Be @('Lab Ungoverned Agent')
        $q018 | Should -Be @('Lab Unsponsored Agent')
    }
}

Describe 'Rule subjects for governance objects' {
    It 'accepts the shipped Q014 to Q018 rules' {
        foreach ($name in @('Q014-ca-plan-no-enforcing-rule.yaml', 'Q015-ca-plan-no-owners.yaml', 'Q016-no-enabled-agent-lifecycle-policy.yaml', 'Q017-agent-without-governing-lifecycle-policy.yaml', 'Q018-agent-without-sponsors.yaml')) {
            $check = @(Test-QuorumRule -Path (Join-Path $script:ModuleRoot "rules/$name"))[0]
            $check.Valid | Should -BeTrue
        }
    }

    It 'lints device facts in a plan rule as unknown' {
        $dir = Join-Path $script:Work 'lint-plan'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $text = "id: X3`ntitle: t`nseverity: low`nsubject: conditionalAccessPlan`ndescription: d`nwhyItMatters: w`nremediation: r`ncondition:`n  fact: intune.present`n  op: eq`n  value: true`n"
        [System.IO.File]::WriteAllText((Join-Path $dir 'X3.yaml'), $text)
        $check = @(Test-QuorumRule -Path $dir)[0]
        $check.Valid | Should -BeFalse
        ($check.Errors -join ' ') | Should -Match "unknown fact 'intune.present'"
    }

    It 'rejects an unknown subject still' {
        InModuleScope Quorum {
            $doc = [ordered]@{ id = 'X4'; title = 't'; severity = 'low'; description = 'd'; whyItMatters = 'w'; remediation = 'r'; subject = 'mailbox'; condition = [ordered]@{ fact = 'plan.hasOwners'; op = 'eq'; value = $true } }
            { ConvertTo-QuorumRule $doc 'x.yaml' } | Should -Throw '*unknown subject*'
        }
    }
}
