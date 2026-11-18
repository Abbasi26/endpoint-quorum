Set-StrictMode -Version 1.0

# Entra Agent ID lifecycle policies (Microsoft Graph v1.0 and beta).
# subject: lifecyclePolicy evaluates each agentIdentityLifecyclePolicy.
# subject: lifecyclePolicySet evaluates one tenant-level summary of those policies.
# Guest lifecycle policies are ignored. Live collection does not read these objects.

$script:QuorumLifecyclePolicyFacts = @(
    'lifecyclePolicy.displayName', 'lifecyclePolicy.isAgentIdentity',
    'lifecyclePolicy.isEnabled', 'lifecyclePolicy.isSystemDefault',
    'lifecyclePolicy.policySource', 'lifecyclePolicy.enforcementKind',
    'lifecyclePolicy.gracePeriodInDays', 'lifecyclePolicy.ruleCount',
    'lifecyclePolicy.enabledRuleCount', 'lifecyclePolicy.versionNumber'
)

$script:QuorumLifecyclePolicySetFacts = @(
    'lifecyclePolicySet.agentPolicyCount', 'lifecyclePolicySet.enabledAgentPolicyCount',
    'lifecyclePolicySet.defaultPresent', 'lifecyclePolicySet.defaultEnabled'
)

function ConvertTo-QuorumLifecyclePolicy {
    param($Policy)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($raw in @($Policy)) {
        if ($null -eq $raw) { continue }
        $items.Add((New-QuorumLifecyclePolicy $raw))
    }
    return $items.ToArray()
}

function New-QuorumLifecyclePolicy {
    param($Raw)
    $id = ''
    $rawId = Get-QuorumProperty $Raw 'id'
    if ($null -ne $rawId) { $id = [string]$rawId }
    $name = $id
    $display = Get-QuorumProperty $Raw 'displayName'
    if ($null -ne $display) { $name = [string]$display }

    $isAgent = [bool](Test-QuorumODataTypeContains $Raw 'agentIdentityLifecyclePolicy')
    $source = ConvertTo-QuorumToken (Get-QuorumProperty $Raw 'policySource')
    $isDefault = ($source -eq 'systemdefault')
    $isEnabled = ConvertTo-QuorumNullableBool (Get-QuorumProperty $Raw 'isEnabled')

    $enforcementKind = $null
    $action = Get-QuorumProperty $Raw 'enforcementAction'
    if ($null -ne $action) {
        if (Test-QuorumODataTypeContains $action 'disableThenDeleteEnforcementAction') { $enforcementKind = 'disableThenDelete' }
        elseif (Test-QuorumODataTypeContains $action 'disableOnlyEnforcementAction') { $enforcementKind = 'disable' }
        elseif (Test-QuorumODataTypeContains $action 'deleteOnlyEnforcementAction') { $enforcementKind = 'delete' }
    }

    $grace = Get-QuorumProperty $Raw 'gracePeriodInDays'
    $version = Get-QuorumProperty $Raw 'versionNumber'

    $ruleCount = $null
    $enabledRuleCount = $null
    if ($null -ne $Raw -and $Raw.PSObject.Properties['rules']) {
        $ruleCount = 0
        $enabledRuleCount = 0
        foreach ($rule in @($Raw.rules)) {
            if ($null -eq $rule) { continue }
            $ruleCount++
            $flag = ConvertTo-QuorumNullableBool (Get-QuorumProperty $rule 'isEnabled')
            if ($flag -eq $true) { $enabledRuleCount++ }
        }
    }

    $facts = @{
        'lifecyclePolicy.displayName'        = $name
        'lifecyclePolicy.isAgentIdentity'    = $isAgent
        'lifecyclePolicy.isEnabled'          = $isEnabled
        'lifecyclePolicy.isSystemDefault'    = $isDefault
        'lifecyclePolicy.policySource'       = $source
        'lifecyclePolicy.enforcementKind'    = $enforcementKind
        'lifecyclePolicy.gracePeriodInDays'  = $grace
        'lifecyclePolicy.ruleCount'          = $ruleCount
        'lifecyclePolicy.enabledRuleCount'   = $enabledRuleCount
        'lifecyclePolicy.versionNumber'      = $version
    }
    return New-QuorumEvalSubject -Subject 'lifecyclePolicy' -Id ('lifecyclePolicy:{0}' -f $id) -Kind 'lifecyclePolicy' -DisplayName $name -Source 'Entra' -Facts $facts
}

function New-QuorumLifecyclePolicySet {
    param($Policy)
    $policies = @(ConvertTo-QuorumLifecyclePolicy -Policy $Policy)
    $agentCount = 0
    $enabledCount = 0
    $defaultPresent = $false
    $defaultEnabled = $false
    foreach ($one in $policies) {
        if ($one.Facts['lifecyclePolicy.isAgentIdentity'] -ne $true) { continue }
        $agentCount++
        if ($one.Facts['lifecyclePolicy.isEnabled'] -eq $true) { $enabledCount++ }
        if ($one.Facts['lifecyclePolicy.isSystemDefault'] -eq $true) {
            $defaultPresent = $true
            if ($one.Facts['lifecyclePolicy.isEnabled'] -eq $true) { $defaultEnabled = $true }
        }
    }
    $facts = @{
        'lifecyclePolicySet.agentPolicyCount'        = $agentCount
        'lifecyclePolicySet.enabledAgentPolicyCount' = $enabledCount
        'lifecyclePolicySet.defaultPresent'          = $defaultPresent
        'lifecyclePolicySet.defaultEnabled'          = $defaultEnabled
    }
    $set = New-QuorumEvalSubject -Subject 'lifecyclePolicySet' -Id 'lifecyclePolicySet:agentIdentity' -Kind 'lifecyclePolicySet' -DisplayName 'Agent ID lifecycle policies' -Source 'Entra' -Facts $facts
    [pscustomobject]@{
        Policies = $policies
        Set      = $set
    }
}
