Set-StrictMode -Version 1.0

# Conditional Access policy plans (Microsoft Graph beta only; preview).
# Rules with subject: conditionalAccessPlan evaluate these objects.
# Live collection does not read plans.

$script:QuorumConditionalAccessPlanFacts = @(
    'plan.displayName', 'plan.description', 'plan.ownerCount', 'plan.hasOwners',
    'plan.tagCount', 'plan.version', 'plan.templateId',
    'plan.ruleCount', 'plan.enforcingRuleCount', 'plan.reportOnlyRuleCount',
    'plan.disabledRuleCount', 'plan.hasEnforcingRule', 'plan.hasSharedConditions',
    'plan.rulesExpanded'
)

function ConvertTo-QuorumConditionalAccessPlan {
    param($Plan)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($raw in @($Plan)) {
        if ($null -eq $raw) { continue }
        $items.Add((ConvertTo-QuorumConditionalAccessPlanRecord $raw))
    }
    return $items.ToArray()
}

function ConvertTo-QuorumConditionalAccessPlanRecord {
    param($Raw)
    $id = ''
    $rawId = Get-QuorumProperty $Raw 'id'
    if ($null -ne $rawId) { $id = [string]$rawId }
    $name = $id
    $display = Get-QuorumProperty $Raw 'displayName'
    if ($null -ne $display) { $name = [string]$display }

    $ownersPresent = $false
    $ownerCount = $null
    if ($null -ne $Raw -and $Raw.PSObject.Properties['owners']) {
        $ownersPresent = $true
        $ownerCount = Get-QuorumItemCount $Raw.owners
        if ($null -eq $ownerCount) { $ownerCount = 0 }
    }

    $tagCount = $null
    if ($null -ne $Raw -and $Raw.PSObject.Properties['tags']) {
        $tagCount = Get-QuorumItemCount $Raw.tags
        if ($null -eq $tagCount) { $tagCount = 0 }
    }

    $version = Get-QuorumProperty $Raw 'version'
    $templateId = Get-QuorumProperty $Raw 'templateId'
    $description = Get-QuorumProperty $Raw 'description'

    $hasShared = $false
    $shared = Get-QuorumProperty $Raw 'sharedConditions'
    if ($null -ne $shared) {
        $props = @($shared.PSObject.Properties | Where-Object { $_.Name -notmatch '^@odata' })
        if ($props.Count -gt 0) { $hasShared = $true }
    }

    $rulesExpanded = $false
    $ruleCount = $null
    $enforcing = $null
    $reportOnly = $null
    $disabled = $null
    if ($null -ne $Raw -and $Raw.PSObject.Properties['rules']) {
        $rulesExpanded = $true
        $enforcing = 0
        $reportOnly = 0
        $disabled = 0
        $n = 0
        foreach ($rule in @($Raw.rules)) {
            if ($null -eq $rule) { continue }
            $n++
            $state = ConvertTo-QuorumToken (Get-QuorumProperty $rule 'state')
            if ($state -eq 'enabled') { $enforcing++ }
            elseif ($state -eq 'enabledforreportingbutnotenforced') { $reportOnly++ }
            else { $disabled++ }
        }
        $ruleCount = $n
    }
    else {
        $odataCount = Get-QuorumProperty $Raw 'rules@odata.count'
        if ($null -ne $odataCount -and (Test-QuorumNumber $odataCount)) {
            $ruleCount = [int][double]$odataCount
        }
    }

    $hasEnforcing = $null
    if ($rulesExpanded) { $hasEnforcing = ($enforcing -gt 0) }
    elseif ($null -ne $ruleCount -and $ruleCount -eq 0) { $hasEnforcing = $false }

    $hasOwners = $null
    if ($ownersPresent) { $hasOwners = ($ownerCount -gt 0) }

    $facts = @{
        'plan.displayName'         = $name
        'plan.description'         = $(if ($null -ne $description) { [string]$description } else { $null })
        'plan.ownerCount'          = $ownerCount
        'plan.hasOwners'           = $hasOwners
        'plan.tagCount'            = $tagCount
        'plan.version'             = $version
        'plan.templateId'          = $(if ($null -ne $templateId) { [string]$templateId } else { $null })
        'plan.ruleCount'           = $ruleCount
        'plan.enforcingRuleCount'  = $enforcing
        'plan.reportOnlyRuleCount' = $reportOnly
        'plan.disabledRuleCount'   = $disabled
        'plan.hasEnforcingRule'    = $hasEnforcing
        'plan.hasSharedConditions' = $hasShared
        'plan.rulesExpanded'       = $rulesExpanded
    }
    return ConvertTo-QuorumEvalSubject -Subject 'conditionalAccessPlan' -Id ('plan:{0}' -f $id) -Kind 'conditionalAccessPlan' -DisplayName $name -Source 'Entra' -Facts $facts
}
