Set-StrictMode -Version 1.0

function New-QuorumViewModel {
    param(
        $Device,
        $Finding,
        $Rule,
        $Collector,
        [datetime]$AsOf,
        [string]$Mode,
        [string]$TenantLabel,
        [bool]$Redacted
    )

    $devices = @($Device | Sort-Object HostnameDisplay, Id)
    $findings = @($Finding)
    $rules = @($Rule)
    $deviceViews = New-Object System.Collections.Generic.List[object]
    $deviceIndex = @{}
    foreach ($one in $devices) {
        $view = ConvertTo-QuorumDeviceView -Device $one -AsOf $AsOf
        $deviceViews.Add($view)
        $deviceIndex[$view['id']] = $view
    }

    $findingViews = New-Object System.Collections.Generic.List[object]
    foreach ($one in $findings) {
        $view = ConvertTo-QuorumFindingView $one
        $findingViews.Add($view)
        foreach ($id in @($view['quorumIds'])) {
            if ($deviceIndex.ContainsKey($id)) {
                $deviceIndex[$id]['findingRuleIds'].Add([string]$view['ruleId'])
            }
        }
    }

    $ranked = @($findingViews | Sort-Object @{ Expression = { Get-QuorumSeverityRank $_['severity'] } }, @{ Expression = { $_['ruleId'] } }, @{ Expression = { $_['hostname'] } })
    $clear = 0
    foreach ($view in $deviceViews) {
        if ($view['findingRuleIds'].Count -eq 0) { $clear++ }
    }
    $generated = [datetime]::UtcNow
    $note = 'Read-only collection. This file stays on the machine that created it.'
    if ($Mode -eq 'Demo') {
        $note = 'Synthetic data. Every name, address, and identifier in this run is fictional.'
    }
    if ($Redacted) {
        $note = $note + ' Hostnames, user names, UPNs, and IP addresses were pseudonymized for this run. A reversal map was written next to the report; do not share the map.'
    }

    $ruleViews = New-Object System.Collections.Generic.List[object]
    foreach ($rule in @($rules | Sort-Object Id)) {
        if (-not $rule.Enabled) { continue }
        $ruleViews.Add([ordered]@{
            id            = $rule.Id
            title         = $rule.Title
            severity      = $rule.Severity
            description   = $rule.Description
            whyItMatters  = $rule.WhyItMatters
            remediation   = $rule.Remediation
        })
    }

    $collectorViews = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Collector)) {
        $status = 'ok'
        $errorText = $null
        if ($item.Error) { $status = 'error'; $errorText = [string]$item.Error }
        $collectorViews.Add([ordered]@{
            source      = [string]$item.Source
            recordCount = [int]@($item.Records).Count
            status      = $status
            error       = $errorText
        })
    }

    [ordered]@{
        meta = [ordered]@{
            version      = (Get-QuorumVersion)
            mode         = $Mode
            generatedAt  = (ConvertTo-QuorumTimestamp $generated)
            asOf         = (ConvertTo-QuorumTimestamp $AsOf)
            redacted     = [bool]$Redacted
            deviceCount  = $deviceViews.Count
            findingCount = $ranked.Count
            clearCount   = $clear
            tenantLabel  = $TenantLabel
            note         = $note
        }
        collectors = $collectorViews.ToArray()
        rules      = $ruleViews.ToArray()
        findings   = @($ranked)
        devices    = $deviceViews.ToArray()
    }
}

function ConvertTo-QuorumDeviceView {
    param($Device, [datetime]$AsOf)
    $facts = Get-QuorumFact -Device $Device -AsOf $AsOf
    $intune = ConvertTo-QuorumSourceView -Record @($Device.BySource.Intune) -Fact $facts -Source 'Intune'
    $entra = ConvertTo-QuorumSourceView -Record @($Device.BySource.Entra) -Fact $facts -Source 'Entra'
    $defender = ConvertTo-QuorumSourceView -Record @($Device.BySource.Defender) -Fact $facts -Source 'Defender'
    $sources = New-Object System.Collections.Generic.List[string]
    if ($intune['present']) { $sources.Add('Intune') }
    if ($entra['present']) { $sources.Add('Entra') }
    if ($defender['present']) { $sources.Add('Defender') }
    $score = $null
    if ($null -ne $Device.MatchScore) {
        $score = ([double]$Device.MatchScore).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    [ordered]@{
        id               = [string]$Device.Id
        hostname         = [string]$Device.HostnameDisplay
        matchMethod      = [string]$Device.MatchMethod
        matchConfidence  = [string]$Device.MatchConfidence
        matchScore       = $score
        duplicate        = [bool]$Device.Duplicate
        duplicateCount   = [int]$Device.DuplicateCount
        sources          = $sources.ToArray()
        findingRuleIds   = (New-Object System.Collections.Generic.List[string])
        intune           = $intune
        entra            = $entra
        defender         = $defender
    }
}

function ConvertTo-QuorumSourceView {
    param($Record, $Fact, [string]$Source)
    $records = @($Record | Where-Object { $_ })
    if ($records.Count -eq 0) {
        return [ordered]@{ present = $false; attributes = @() }
    }
    $attrs = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($rec in $records) {
        $index++
        if ($records.Count -gt 1) {
            $attrs.Add([ordered]@{
                label = 'Record'
                value = ("{0} of {1}" -f $index, $records.Count)
                key = 'record'
                conflict = $false
            })
        }
        foreach ($attr in @($rec.Attributes)) {
            $copy = [ordered]@{
                label    = [string]$attr['label']
                value    = [string]$attr['value']
                key      = [string]$attr['key']
                conflict = $false
            }
            $attrs.Add($copy)
        }
    }
    Add-QuorumAgeSuffix $attrs 'lastSync' $Fact['intune.lastSyncAgeDays']
    Add-QuorumAgeSuffix $attrs 'lastSignIn' $Fact['entra.lastSignInAgeDays']
    Add-QuorumAgeSuffix $attrs 'lastSeen' $Fact['defender.lastSeenAgeDays']
    $conflictKeys = New-Object System.Collections.Generic.List[string]
    if ($Fact['os.buildMismatch']) { $conflictKeys.Add('osBuild') }
    if ($Fact['compliance.disagrees']) {
        $conflictKeys.Add('compliance')
        $conflictKeys.Add('isCompliant')
    }
    if ($Fact['defender.riskScore'] -eq 'high' -and $Fact['intune.complianceState'] -eq 'compliant') {
        $conflictKeys.Add('risk')
        $conflictKeys.Add('compliance')
    }
    if ($Fact['entra.enabled'] -eq $false -and $Fact['intune.complianceState'] -eq 'compliant') {
        $conflictKeys.Add('enabled')
        $conflictKeys.Add('compliance')
    }
    foreach ($attr in $attrs) {
        if ($conflictKeys.Contains([string]$attr['key'])) { $attr['conflict'] = $true }
    }
    return [ordered]@{ present = $true; attributes = $attrs.ToArray() }
}

function Add-QuorumAgeSuffix {
    param($Attributes, [string]$Key, $Days)
    if ($null -eq $Days -or $Days -eq '') { return }
    $label = ConvertTo-QuorumAgeLabel $Days
    foreach ($attr in $Attributes) {
        if ($attr['key'] -eq $Key -and $attr['value'] -notmatch 'ago\)' -and $attr['value'] -notmatch '\(today\)') {
            $attr['value'] = $attr['value'] + ' (' + $label + ')'
        }
    }
}

function ConvertTo-QuorumFindingView {
    param($Finding)
    $evidence = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($Finding.Evidence.Keys)) {
        $evidence.Add([ordered]@{
            key   = [string]$key
            label = (Get-QuorumFactLabel $key)
            value = (Format-QuorumEvidenceValue $key $Finding.Evidence[$key])
        })
    }
    $score = $null
    if ($null -ne $Finding.MatchScore) {
        $score = ([double]$Finding.MatchScore).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    [ordered]@{
        ruleId           = [string]$Finding.RuleId
        severity         = [string]$Finding.Severity
        title            = [string]$Finding.Title
        description      = [string]$Finding.Description
        whyItMatters     = [string]$Finding.WhyItMatters
        remediation      = [string]$Finding.Remediation
        hostname         = [string]$Finding.Hostname
        quorumIds        = @($Finding.QuorumIds)
        matchMethod      = [string]$Finding.MatchMethod
        matchConfidence  = [string]$Finding.MatchConfidence
        matchScore       = $score
        sources          = @($Finding.Sources)
        evidence         = $evidence.ToArray()
    }
}

function Get-QuorumFactLabel {
    param([string]$Key)
    $labels = @{
        'intune.complianceState'    = 'Intune compliance'
        'intune.lastSyncAgeDays'    = 'Intune last sync'
        'intune.osBuild'            = 'Intune OS build'
        'entra.enabled'             = 'Entra enabled'
        'entra.isCompliant'         = 'Entra compliant'
        'entra.lastSignInAgeDays'   = 'Entra last sign-in'
        'entra.operatingSystem'     = 'Entra operating system'
        'entra.osBuild'             = 'Entra OS build'
        'defender.riskScore'        = 'Defender risk'
        'defender.healthStatus'     = 'Defender health'
        'defender.onboardingStatus' = 'Defender onboarding'
        'defender.lastSeenAgeDays'  = 'Defender last seen'
        'defender.osBuild'          = 'Defender OS build'
        'os.builds'                 = 'OS builds'
        'os.buildMismatch'          = 'OS build mismatch'
        'hostname.duplicateCount'   = 'Devices with this hostname'
        'compliance.disagrees'      = 'Compliance disagrees'
        'match.method'              = 'Match method'
        'match.confidence'          = 'Match confidence'
        'quorum.ids'                = 'Quorum ids'
        'device.count'              = 'Device count'
        'hostname.names'            = 'Hostnames'
    }
    if ($labels.ContainsKey($Key)) { return $labels[$Key] }
    return $Key
}

function Format-QuorumEvidenceValue {
    param([string]$Key, $Value)
    if ($null -eq $Value) { return '' }
    if ($Key -match 'AgeDays$' -and ([string]$Value) -match '^\d+$') {
        return (ConvertTo-QuorumAgeLabel ([int]$Value))
    }
    return [string]$Value
}

function Get-QuorumSeverityRank {
    param([string]$Severity)
    switch ($Severity) {
        'critical' { return 0 }
        'high' { return 1 }
        'medium' { return 2 }
        'low' { return 3 }
        'info' { return 4 }
        default { return 9 }
    }
}