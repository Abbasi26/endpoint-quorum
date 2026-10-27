Set-StrictMode -Version 1.0

function Import-QuorumRule {
    param([Parameter(Mandatory = $true)][string]$Path)

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $files.Add((Get-Item -LiteralPath $Path))
    }
    elseif (Test-Path -LiteralPath $Path -PathType Container) {
        $found = Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Extension -eq '.yaml' -or $_.Extension -eq '.yml' }
        foreach ($file in @($found | Sort-Object Name)) { $files.Add($file) }
    }
    else {
        throw "Rules path not found: $Path"
    }
    if ($files.Count -eq 0) { throw "No YAML rules found in $Path" }

    $rules = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($file in $files) {
        $doc = ConvertFrom-QuorumYaml -Path $file.FullName
        $rule = ConvertTo-QuorumRule $doc $file.FullName
        if ($seen.ContainsKey($rule.Id)) {
            throw "Duplicate rule id '$($rule.Id)' in $($file.Name)."
        }
        $seen[$rule.Id] = $true
        $rules.Add($rule)
    }
    return ,$rules.ToArray()
}

function ConvertTo-QuorumRule {
    param($Doc, [string]$File)
    if ($null -eq $Doc -or -not ($Doc -is [System.Collections.IDictionary])) {
        throw "Rule file is not a YAML mapping: $File"
    }
    foreach ($key in @('id', 'title', 'severity', 'description', 'whyItMatters', 'remediation', 'condition')) {
        if (-not $Doc.Contains($key) -or $null -eq $Doc[$key] -or [string]$Doc[$key] -eq '') {
            throw "Rule file $File is missing '$key'."
        }
    }
    $severity = ([string]$Doc['severity']).Trim().ToLowerInvariant()
    $allowed = @('critical', 'high', 'medium', 'low', 'info')
    if ($allowed -notcontains $severity) {
        throw "Rule $($Doc['id']) has unknown severity '$severity'. Use: $($allowed -join ', ')."
    }
    $enabled = $true
    if ($Doc.Contains('enabled') -and $null -ne $Doc['enabled']) {
        $flag = ConvertTo-QuorumNullableBool $Doc['enabled']
        if ($null -eq $flag) { throw "Rule $($Doc['id']) has an invalid 'enabled' value. Use true or false." }
        $enabled = $flag
    }
    $parameters = @{}
    if ($Doc.Contains('parameters') -and $null -ne $Doc['parameters']) {
        if (-not ($Doc['parameters'] -is [System.Collections.IDictionary])) {
            throw "Rule $($Doc['id']) parameters must be a mapping."
        }
        foreach ($name in @($Doc['parameters'].Keys)) {
            $parameters[$name] = $Doc['parameters'][$name]
        }
    }
    $groupBy = $null
    if ($Doc.Contains('groupBy') -and $Doc['groupBy']) { $groupBy = [string]$Doc['groupBy'] }
    $id = ([string]$Doc['id']).Trim()
    if ($id -notmatch '^[A-Za-z][A-Za-z0-9._-]{1,40}$') {
        throw "Rule id '$id' must start with a letter and contain only letters, numbers, dots, underscores, or hyphens."
    }
    [pscustomobject]@{
        Id            = $id
        Title         = [string]$Doc['title']
        Severity      = $severity
        Description   = [string]$Doc['description']
        WhyItMatters  = [string]$Doc['whyItMatters']
        Remediation   = [string]$Doc['remediation']
        Parameters    = $parameters
        GroupBy       = $groupBy
        Enabled       = [bool]$enabled
        Condition     = $Doc['condition']
        Path          = $File
    }
}

function Invoke-QuorumRule {
    param($Device, $Rule, [datetime]$AsOf)

    $rules = @($Rule | Where-Object { $_ -and $_.Enabled })
    $devices = @($Device | Where-Object { $_ })
    $factsById = @{}
    foreach ($one in $devices) {
        $factsById[$one.Id] = Get-QuorumFact -Device $one -AsOf $AsOf
    }

    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($rule in $rules) {
        $matched = New-Object System.Collections.Generic.List[object]
        foreach ($one in $devices) {
            $ok = Test-QuorumCondition -Condition $rule.Condition -Fact $factsById[$one.Id] -Parameter $rule.Parameters -RuleId $rule.Id
            if ($ok) { $matched.Add($one) }
        }
        if ($matched.Count -eq 0) { continue }
        if ($rule.GroupBy) {
            $groups = @{}
            foreach ($one in $matched) {
                $facts = $factsById[$one.Id]
                $groupKey = $facts[$rule.GroupBy]
                if ($null -eq $groupKey -or [string]$groupKey -eq '') { $groupKey = $one.Id }
                $groupKey = [string]$groupKey
                if (-not $groups.ContainsKey($groupKey)) {
                    $groups[$groupKey] = New-Object System.Collections.Generic.List[object]
                }
                $groups[$groupKey].Add($one)
            }
            foreach ($groupKey in @($groups.Keys | Sort-Object)) {
                $members = @($groups[$groupKey] | Sort-Object HostnameDisplay, Id)
                $findings.Add((New-QuorumFinding -Rule $rule -Device $members -Fact $factsById -GroupKey $groupKey))
            }
        }
        else {
            foreach ($one in @($matched | Sort-Object HostnameDisplay, Id)) {
                $findings.Add((New-QuorumFinding -Rule $rule -Device @($one) -Fact $factsById -GroupKey $null))
            }
        }
    }
    return ,$findings.ToArray()
}

function New-QuorumFinding {
    param($Rule, $Device, $Fact, $GroupKey)
    $devices = @($Device)
    $primary = $devices[0]
    $facts = $Fact[$primary.Id]
    $evidence = New-QuorumEvidence -Fact $facts -Condition $Rule.Condition
    if ($devices.Count -gt 1) {
        $ids = @($devices | ForEach-Object { $_.Id })
        $names = @($devices | ForEach-Object { $_.HostnameDisplay })
        $evidence['quorum.ids'] = ($ids -join ',')
        $evidence['device.count'] = [string]$devices.Count
        $evidence['hostname.names'] = ($names -join ', ')
    }
    $sources = @{}
    foreach ($one in $devices) {
        foreach ($rec in @($one.Records)) { $sources[$rec.Source] = $true }
    }
    $sourceNames = @($sources.Keys | Sort-Object)
    $confidence = $primary.MatchConfidence
    $method = $primary.MatchMethod
    if ($devices.Count -gt 1) {
        $method = 'multiple'
        $confidence = $primary.MatchConfidence
    }
    [pscustomobject]@{
        RuleId            = $Rule.Id
        Title             = $Rule.Title
        Severity          = $Rule.Severity
        Description       = $Rule.Description
        WhyItMatters      = $Rule.WhyItMatters
        Remediation       = $Rule.Remediation
        Hostname          = $primary.HostnameDisplay
        QuorumIds         = @($devices | ForEach-Object { $_.Id })
        MatchMethod       = $method
        MatchConfidence   = $confidence
        MatchScore        = $primary.MatchScore
        Sources           = $sourceNames
        Evidence          = $evidence
        GroupKey          = $GroupKey
    }
}

function New-QuorumEvidence {
    param($Fact, $Condition)
    $wanted = @{
        'intune.complianceState'      = $true
        'intune.lastSyncAgeDays'      = $true
        'intune.osBuild'              = $true
        'entra.enabled'               = $true
        'entra.isCompliant'           = $true
        'entra.lastSignInAgeDays'     = $true
        'entra.operatingSystem'       = $true
        'entra.osBuild'               = $true
        'defender.riskScore'          = $true
        'defender.healthStatus'       = $true
        'defender.onboardingStatus'   = $true
        'defender.lastSeenAgeDays'    = $true
        'defender.osBuild'            = $true
        'os.builds'                   = $true
        'os.buildMismatch'            = $true
        'hostname.duplicateCount'     = $true
        'compliance.disagrees'        = $true
        'match.method'                = $true
        'match.confidence'            = $true
    }
    foreach ($name in (Get-QuorumConditionFact $Condition)) { $wanted[$name] = $true }
    $ordered = [ordered]@{}
    foreach ($name in @($wanted.Keys | Sort-Object)) {
        if (-not $Fact.ContainsKey($name)) { continue }
        $value = $Fact[$name]
        if ($null -eq $value) { continue }
        if ($value -is [bool]) {
            if ($value) { $ordered[$name] = 'true' } else { $ordered[$name] = 'false' }
            continue
        }
        $ordered[$name] = [string]$value
    }
    return $ordered
}

function Get-QuorumConditionFact {
    param($Condition)
    $names = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Condition) { return ,$names.ToArray() }
    if ($Condition -is [System.Collections.IDictionary]) {
        if ($Condition.Contains('fact') -and $Condition['fact']) { $names.Add([string]$Condition['fact']) }
        foreach ($key in @('all', 'any', 'not')) {
            if (-not $Condition.Contains($key) -or $null -eq $Condition[$key]) { continue }
            foreach ($child in (ConvertTo-QuorumConditionItems $Condition[$key])) {
                foreach ($name in (Get-QuorumConditionFact $child)) { $names.Add($name) }
            }
        }
    }
    return ,$names.ToArray()
}

function Test-QuorumCondition {
    param($Condition, $Fact, $Parameter, [string]$RuleId)
    if ($null -eq $Condition -or -not ($Condition -is [System.Collections.IDictionary])) {
        throw "Rule ${RuleId} has a condition that is not a mapping."
    }
    if ($Condition.Contains('all')) {
        $items = ConvertTo-QuorumConditionItems $Condition['all']
        if ($items.Count -eq 0) { return $true }
        foreach ($item in $items) {
            if (-not (Test-QuorumCondition -Condition $item -Fact $Fact -Parameter $Parameter -RuleId $RuleId)) { return $false }
        }
        return $true
    }
    if ($Condition.Contains('any')) {
        $items = ConvertTo-QuorumConditionItems $Condition['any']
        foreach ($item in $items) {
            if (Test-QuorumCondition -Condition $item -Fact $Fact -Parameter $Parameter -RuleId $RuleId) { return $true }
        }
        return $false
    }
    if ($Condition.Contains('not')) {
        return -not (Test-QuorumCondition -Condition $Condition['not'] -Fact $Fact -Parameter $Parameter -RuleId $RuleId)
    }
    if ($Condition.Contains('fact')) {
        return (Test-QuorumPredicate -Predicate $Condition -Fact $Fact -Parameter $Parameter -RuleId $RuleId)
    }
    throw "Rule ${RuleId} has a condition without all, any, not, or fact."
}

function ConvertTo-QuorumConditionItems {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary]) {
        $box = New-Object object[] 1
        $box[0] = $Value
        return ,$box
    }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Value)) {
        if ($null -ne $item) { $items.Add($item) }
    }
    return ,$items.ToArray()
}

function Test-QuorumPredicate {
    param($Predicate, $Fact, $Parameter, [string]$RuleId)
    $name = [string]$Predicate['fact']
    if (-not $Predicate.Contains('op') -or -not $Predicate['op']) {
        throw "Rule ${RuleId} fact '$name' is missing an op."
    }
    $op = ([string]$Predicate['op']).Trim().ToLowerInvariant()
    $has = $Fact.ContainsKey($name)
    $actual = $null
    if ($has) { $actual = $Fact[$name] }
    $expected = $null
    if ($Predicate.Contains('valueFrom') -and $Predicate['valueFrom']) {
        $paramName = [string]$Predicate['valueFrom']
        if (-not $Parameter.ContainsKey($paramName)) {
            throw "Rule ${RuleId} references parameter '$paramName', which is not defined."
        }
        $expected = $Parameter[$paramName]
    }
    elseif ($Predicate.Contains('value')) {
        $expected = $Predicate['value']
    }
    elseif ($op -ne 'exists') {
        throw "Rule ${RuleId} fact '$name' needs value or valueFrom."
    }

    switch ($op) {
        'eq' { return (Compare-QuorumEqual $actual $expected) }
        'ne' { return -not (Compare-QuorumEqual $actual $expected) }
        'gt' { return (Compare-QuorumNumber $actual $expected { param($a, $b) $a -gt $b }) }
        'gte' { return (Compare-QuorumNumber $actual $expected { param($a, $b) $a -ge $b }) }
        'lt' { return (Compare-QuorumNumber $actual $expected { param($a, $b) $a -lt $b }) }
        'lte' { return (Compare-QuorumNumber $actual $expected { param($a, $b) $a -le $b }) }
        'contains' {
            if ($null -eq $actual -or $null -eq $expected) { return $false }
            return ([string]$actual).ToLowerInvariant().Contains(([string]$expected).ToLowerInvariant())
        }
        'in' { return (Test-QuorumIn $actual $expected) }
        'nin' { return -not (Test-QuorumIn $actual $expected) }
        'exists' {
            $want = ConvertTo-QuorumNullableBool $expected
            if ($null -eq $want) { throw "Rule ${RuleId} fact '$name' uses exists without true or false." }
            $present = $has -and $null -ne $actual -and -not ($actual -is [string] -and [string]::IsNullOrWhiteSpace([string]$actual))
            return ($present -eq $want)
        }
        default { throw "Rule ${RuleId} uses unknown operator '$op'." }
    }
}

function Compare-QuorumEqual {
    param($Left, $Right)
    if ($null -eq $Left -and $null -eq $Right) { return $true }
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    $leftBool = ConvertTo-QuorumNullableBool $Left
    $rightBool = ConvertTo-QuorumNullableBool $Right
    if ($null -ne $leftBool -and $null -ne $rightBool) { return ($leftBool -eq $rightBool) }
    if ((Test-QuorumNumber $Left) -and (Test-QuorumNumber $Right)) {
        return ([double]$Left) -eq ([double]$Right)
    }
    return [string]::Compare([string]$Left, [string]$Right, [System.StringComparison]::OrdinalIgnoreCase) -eq 0
}

function Compare-QuorumNumber {
    param($Left, $Right, [scriptblock]$Compare)
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    if (-not (Test-QuorumNumber $Left) -or -not (Test-QuorumNumber $Right)) { return $false }
    $a = [double]$Left
    $b = [double]$Right
    return [bool](& $Compare $a $b)
}

function Test-QuorumIn {
    param($Actual, $Expected)
    if ($null -eq $Actual -or $null -eq $Expected) { return $false }
    $items = ConvertTo-QuorumConditionItems $Expected
    foreach ($item in @($items)) {
        if (Compare-QuorumEqual $Actual $item) { return $true }
    }
    return $false
}