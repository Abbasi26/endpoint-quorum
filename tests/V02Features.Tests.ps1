BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'Quorum.psd1') -Force
    $script:Demo = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'data/demo-inventory.json') -Raw | ConvertFrom-Json
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-v02-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Work | Out-Null
    function script:Write-TestJson {
        param([string]$Name, $Value)
        $path = Join-Path $script:Work $Name
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $Value -Depth 20))
        return $path
    }
    function script:Write-TestRule {
        param([string]$Dir, [string]$Name, [string]$Text)
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
        $path = Join-Path $Dir $Name
        [System.IO.File]::WriteAllText($path, $Text)
        return $path
    }
}

AfterAll {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) { Remove-Item -LiteralPath $script:Work -Recurse -Force }
}

Describe 'Offline import' {
    It 'evaluates a combined inventory file like the demo' {
        $out = Join-Path $script:Work 'inv'
        $r = Invoke-Quorum -InventoryPath (Join-Path $script:ModuleRoot 'data/demo-inventory.json') -OutputPath $out 6>$null
        $demo = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'demo') 6>$null
        $r.Mode | Should -Be 'Import'
        $r.DeviceCount | Should -Be $demo.DeviceCount
        $r.FindingCount | Should -Be $demo.FindingCount
        Test-Path -LiteralPath $r.HtmlPath | Should -BeTrue
    }

    It 'accepts per-source arrays and Graph pages with a value property' {
        $intune = Write-TestJson 'intune.json' @{ value = @($script:Demo.intune) }
        $entra = Write-TestJson 'entra.json' @($script:Demo.entra)
        $defender = Write-TestJson 'defender.json' @{ value = @($script:Demo.defender) }
        $groups = Write-TestJson 'groups.json' @{ value = @($script:Demo.groups) }
        $units = Write-TestJson 'units.json' @($script:Demo.administrativeUnits)
        $plans = Write-TestJson 'plans.json' @{ value = @($script:Demo.conditionalAccessPlans) }
        $policies = Write-TestJson 'policies.json' @($script:Demo.lifecyclePolicies)
        $agents = Write-TestJson 'agents.json' @{ value = @($script:Demo.agentIdentities) }
        $r = Invoke-Quorum -IntunePath $intune -EntraPath $entra -DefenderPath $defender -GroupPath $groups -AdministrativeUnitPath $units -ConditionalAccessPlanPath $plans -LifecyclePolicyPath $policies -AgentIdentityPath $agents -AsOf ([datetime]$script:Demo.asOf) -OutputPath (Join-Path $script:Work 'split') 6>$null
        $demo = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'demo2') 6>$null
        $r.Mode | Should -Be 'Import'
        $r.DeviceCount | Should -Be $demo.DeviceCount
        $r.FindingCount | Should -Be $demo.FindingCount
    }

    It 'marks a source that was not provided as not collected' {
        $intune = Write-TestJson 'intune-only.json' @($script:Demo.intune)
        $r = Invoke-Quorum -IntunePath $intune -OutputPath (Join-Path $script:Work 'intune-only') 6>$null
        $status = @($r.CollectorStatus | Where-Object { $_['source'] -eq 'Defender' -or $_.source -eq 'Defender' })
        $status.Count | Should -Be 1
        ($status[0] | ConvertTo-Json -Depth 5) | Should -Match 'Not provided'
        $r.DeviceCount | Should -BeGreaterThan 0
    }

    It 'keeps a one-element export as a device list' {
        $one = Join-Path $script:Work 'one.json'
        [System.IO.File]::WriteAllText($one, '[' + (ConvertTo-Json -InputObject $script:Demo.entra[0] -Depth 20) + ']')
        $r = Invoke-Quorum -EntraPath $one -OutputPath (Join-Path $script:Work 'one') 6>$null
        $r.DeviceCount | Should -Be 1
    }

    It 'reads a gzip-compressed export (.json.gz) like the plain file' {
        $plain = Join-Path $script:ModuleRoot 'data/demo-inventory.json'
        $gz = Join-Path $script:Work 'demo-inventory.json.gz'
        $source = [System.IO.File]::OpenRead($plain)
        $target = [System.IO.File]::Create($gz)
        $zip = New-Object System.IO.Compression.GZipStream($target, [System.IO.Compression.CompressionMode]::Compress)
        try { $source.CopyTo($zip) } finally { $zip.Dispose(); $target.Dispose(); $source.Dispose() }
        $bytes = [System.IO.File]::ReadAllBytes($gz)
        $bytes[0] | Should -Be 0x1F
        $r = Invoke-Quorum -InventoryPath $gz -OutputPath (Join-Path $script:Work 'gz') 6>$null
        $p = Invoke-Quorum -InventoryPath $plain -OutputPath (Join-Path $script:Work 'gz-plain') 6>$null
        $r.Mode | Should -Be 'Import'
        $r.DeviceCount | Should -Be $p.DeviceCount
        $r.FindingCount | Should -Be $p.FindingCount
    }

    It 'detects gzip by content, not by extension, for per-source files' {
        $json = ConvertTo-Json -InputObject @{ value = @($script:Demo.entra) } -Depth 20
        $path = Join-Path $script:Work 'entra-compressed.json'
        $target = [System.IO.File]::Create($path)
        $zip = New-Object System.IO.Compression.GZipStream($target, [System.IO.Compression.CompressionMode]::Compress)
        $writer = New-Object System.IO.StreamWriter($zip, (New-Object System.Text.UTF8Encoding($false)))
        try { $writer.Write($json) } finally { $writer.Dispose(); $target.Dispose() }
        $r = Invoke-Quorum -EntraPath $path -OutputPath (Join-Path $script:Work 'gz-entra') 6>$null
        $r.DeviceCount | Should -Be @($script:Demo.entra).Count
    }

    It 'reports a truncated gzip export clearly' {
        $path = Join-Path $script:Work 'broken.json.gz'
        [System.IO.File]::WriteAllBytes($path, [byte[]](0x1F, 0x8B, 0x08, 0x00, 0x01, 0x02))
        { Invoke-Quorum -IntunePath $path -OutputPath (Join-Path $script:Work 'gz-bad') 6>$null } | Should -Throw '*Export file*'
    }

    It 'rejects a file that is neither an array nor a value page' {
        $bad = Write-TestJson 'bad.json' @{ devices = @() }
        { Invoke-Quorum -IntunePath $bad -OutputPath (Join-Path $script:Work 'bad') 6>$null } | Should -Throw '*value array*'
    }

    It 'rejects an inventory without any source arrays' {
        $bad = Write-TestJson 'bad-inv.json' @{ asOf = '2026-01-01T00:00:00Z' }
        { Invoke-Quorum -InventoryPath $bad -OutputPath (Join-Path $script:Work 'bad2') 6>$null } | Should -Throw '*intune, entra, or defender*'
    }

    It 'refuses to mix modes' {
        { Invoke-Quorum -Demo -InventoryPath 'x.json' 6>$null } | Should -Throw '*Choose one*'
        { Invoke-Quorum -InventoryPath 'x.json' -IntunePath 'y.json' 6>$null } | Should -Throw '*not both*'
    }
}

Describe 'FailOnSeverity' {
    It 'reports the highest severity' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'sev') 6>$null
        $r.HighestSeverity | Should -Be 'high'
    }

    It 'throws after writing the report when findings reach the threshold' {
        $out = Join-Path $script:Work 'gate'
        { Invoke-Quorum -Demo -OutputPath $out -FailOnSeverity high 6>$null } | Should -Throw '*severity high or worse*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-Report.html') | Should -BeTrue
    }

    It 'passes when no finding reaches the threshold' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'gate2') -FailOnSeverity critical 6>$null
        $r.FindingCount | Should -BeGreaterThan 0
    }
}

Describe 'FailOnCount' {
    It 'throws when total findings reach the threshold' {
        $out = Join-Path $script:Work 'cnt1'
        { Invoke-Quorum -Demo -OutputPath $out -FailOnCount 44 6>$null } | Should -Throw '*total finding(s)*Threshold: 44*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-Report.html') | Should -BeTrue
    }

    It 'passes when total findings are below the threshold' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'cnt2') -FailOnCount 45 6>$null
        $r.FindingCount | Should -Be 44
    }

    It 'throws when findings at severity reach the threshold' {
        $out = Join-Path $script:Work 'cnt3'
        { Invoke-Quorum -Demo -OutputPath $out -FailOnSeverity high -FailOnCount 10 6>$null } | Should -Throw '*severity high or worse*Threshold: 10*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-Report.html') | Should -BeTrue
    }

    It 'passes when findings at severity are below the threshold' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'cnt4') -FailOnSeverity high -FailOnCount 25 6>$null
        $r.FindingCount | Should -Be 44
    }

    It 'passes when no finding reaches the severity' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'cnt5') -FailOnSeverity critical -FailOnCount 1 6>$null
        $r.FindingCount | Should -Be 44
    }

    It 'rejects zero threshold' {
        { Invoke-Quorum -Demo -FailOnCount 0 -OutputPath (Join-Path $script:Work 'cnt6') 6>$null } | Should -Throw
    }

    It 'rejects negative threshold' {
        { Invoke-Quorum -Demo -FailOnCount -5 -OutputPath (Join-Path $script:Work 'cnt7') 6>$null } | Should -Throw
    }

    It 'works with info severity (counts all)' {
        $out = Join-Path $script:Work 'cnt8'
        { Invoke-Quorum -Demo -OutputPath $out -FailOnSeverity info -FailOnCount 44 6>$null } | Should -Throw '*severity info or worse*Threshold: 44*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-Report.html') | Should -BeTrue
    }

    It 'help text documents the parameter' {
        (Get-Help Invoke-Quorum -Parameter FailOnCount).description.Text | Should -Match 'reaches this threshold'
    }
}

Describe 'Test-QuorumRule' {
    It 'accepts every shipped rule' {
        $checks = @(Test-QuorumRule)
        $checks.Count | Should -BeGreaterThan 0
        @($checks | Where-Object { -not $_.Valid }).Count | Should -Be 0
        Test-QuorumRule -Quiet | Should -BeTrue
    }

    It 'keeps its fact list in sync with Get-QuorumFact' {
        $source = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private/Get-QuorumFact.ps1') -Raw
        $actual = @([regex]::Matches($source, "\`$facts\['([^']+)'\]") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $known = InModuleScope Quorum { $script:QuorumKnownFacts }
        (@($known | Sort-Object -Unique) -join ',') | Should -Be ($actual -join ',')
    }

    It 'flags unknown facts, unknown operators, and missing parameters' {
        $dir = Join-Path $script:Work 'rules-bad'
        Write-TestRule $dir 'X001.yaml' @'
id: X001
title: Typo rule
severity: high
description: d
whyItMatters: w
remediation: r
condition:
  all:
    - fact: defender.lastSeenAgeDay
      op: gt
      valueFrom: staleDays
    - fact: intune.present
      op: equals
      value: true
'@ | Out-Null
        $check = @(Test-QuorumRule -Path $dir)
        $check.Count | Should -Be 1
        $check[0].Valid | Should -BeFalse
        ($check[0].Errors -join "`n") | Should -Match "unknown fact 'defender.lastSeenAgeDay'"
        ($check[0].Errors -join "`n") | Should -Match "unknown operator 'equals'"
        ($check[0].Errors -join "`n") | Should -Match "parameter 'staleDays'"
        Test-QuorumRule -Path $dir -Quiet | Should -BeFalse
    }

    It 'flags duplicate ids and schema errors per file' {
        $dir = Join-Path $script:Work 'rules-dup'
        $ok = @'
id: X002
title: Fine
severity: low
description: d
whyItMatters: w
remediation: >
  Open the device in the Intune console, check the compliance state,
  and confirm the record matches the Entra object.
condition:
  fact: intune.present
  op: eq
  value: false
'@
        Write-TestRule $dir 'a.yaml' $ok | Out-Null
        Write-TestRule $dir 'b.yaml' $ok | Out-Null
        Write-TestRule $dir 'c.yaml' "id: X003`ntitle: no severity`n" | Out-Null
        $check = @(Test-QuorumRule -Path $dir)
        $check.Count | Should -Be 3
        $check[0].Valid | Should -BeTrue
        ($check[1].Errors -join ' ') | Should -Match 'Duplicate rule id'
        $check[2].Valid | Should -BeFalse
    }

    It 'throws for a missing path' {
        { Test-QuorumRule -Path (Join-Path $script:Work 'nope') } | Should -Throw '*not found*'
    }

    It 'flags a remediation that is too short to be actionable' {
        $dir = Join-Path $script:Work 'rules-short'
        Write-TestRule $dir 'X004.yaml' @'
id: X004
title: Short remediation
severity: low
description: d
whyItMatters: w
remediation: fix it
condition:
  fact: intune.present
  op: eq
  value: true
'@ | Out-Null
        $check = @(Test-QuorumRule -Path $dir)
        $check.Count | Should -Be 1
        $check[0].Valid | Should -BeFalse
        ($check[0].Errors -join "`n") | Should -Match 'remediation is too short'
        Test-QuorumRule -Path $dir -Quiet | Should -BeFalse
    }

    It 'accepts a remediation that names a console and a check' {
        $dir = Join-Path $script:Work 'rules-good'
        Write-TestRule $dir 'X005.yaml' @'
id: X005
title: Good remediation
severity: medium
description: d
whyItMatters: w
remediation: >
  Open the device in the Defender console, check the sensor health,
  and re-onboard the machine if the agent is missing.
condition:
  fact: intune.present
  op: eq
  value: true
'@ | Out-Null
        $check = @(Test-QuorumRule -Path $dir)
        $check.Count | Should -Be 1
        $check[0].Valid | Should -BeTrue
        Test-QuorumRule -Path $dir -Quiet | Should -BeTrue
    }
}
