Set-StrictMode -Version 1.0

# Entra Agent ID identities (Microsoft Graph v1.0 and beta).
# Rules with subject: agentIdentity evaluate these objects.
# Sponsors, owners, and lifecycle are optional expanded properties on the export.
# Live collection does not read agent identities.

$script:QuorumAgentIdentityFacts = @(
    'agent.displayName', 'agent.accountEnabled', 'agent.blueprintId',
    'agent.sponsorCount', 'agent.hasSponsors', 'agent.ownerCount', 'agent.hasOwners',
    'agent.lifecyclePresent', 'agent.hasEffectiveGoverningPolicy',
    'agent.complianceIssueCount', 'agent.lastAttestationAgeDays',
    'agent.disabledByMicrosoft'
)

function ConvertTo-QuorumAgentIdentity {
    param($Identity, [datetime]$AsOf)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($raw in @($Identity)) {
        if ($null -eq $raw) { continue }
        $items.Add((New-QuorumAgentIdentity $raw $AsOf))
    }
    return $items.ToArray()
}

function New-QuorumAgentIdentity {
    param($Raw, [datetime]$AsOf)
    $id = ''
    $rawId = Get-QuorumProperty $Raw 'id'
    if ($null -ne $rawId) { $id = [string]$rawId }
    $name = $id
    $display = Get-QuorumProperty $Raw 'displayName'
    if ($null -ne $display) { $name = [string]$display }

    $enabled = ConvertTo-QuorumNullableBool (Get-QuorumProperty $Raw 'accountEnabled')
    $blueprint = Get-QuorumProperty $Raw 'agentIdentityBlueprintId'
    $disabledBy = Get-QuorumProperty $Raw 'disabledByMicrosoftStatus'

    $sponsorCount = $null
    $hasSponsors = $null
    if ($null -ne $Raw -and $Raw.PSObject.Properties['sponsors']) {
        $sponsorCount = Get-QuorumItemCount $Raw.sponsors
        if ($null -eq $sponsorCount) { $sponsorCount = 0 }
        $hasSponsors = ($sponsorCount -gt 0)
    }

    $ownerCount = $null
    $hasOwners = $null
    if ($null -ne $Raw -and $Raw.PSObject.Properties['owners']) {
        $ownerCount = Get-QuorumItemCount $Raw.owners
        if ($null -eq $ownerCount) { $ownerCount = 0 }
        $hasOwners = ($ownerCount -gt 0)
    }

    $lifecyclePresent = $false
    $hasPolicy = $null
    $issueCount = $null
    $attestAge = $null
    $lifecycle = Get-QuorumProperty $Raw 'lifecycle'
    if ($null -ne $lifecycle) {
        $lifecyclePresent = $true
        if ($lifecycle.PSObject.Properties['effectiveGoverningPolicy']) {
            $policy = $lifecycle.effectiveGoverningPolicy
            $hasPolicy = ($null -ne $policy -and $null -ne (Get-QuorumProperty $policy 'id'))
            if ($hasPolicy -eq $false -and $null -ne $policy) {
                # A non-null policy object without an id still counts as present.
                $hasPolicy = $true
            }
        }
        if ($lifecycle.PSObject.Properties['complianceIssues']) {
            $issueCount = Get-QuorumItemCount $lifecycle.complianceIssues
            if ($null -eq $issueCount) { $issueCount = 0 }
        }
        $lastAttest = Get-QuorumProperty $lifecycle 'lastAttestationDateTime'
        if ($null -ne $lastAttest -and $null -ne $AsOf) {
            $attestAge = Get-QuorumAgeDays $lastAttest $AsOf
        }
    }

    $facts = @{
        'agent.displayName'                   = $name
        'agent.accountEnabled'                = $enabled
        'agent.blueprintId'                   = $(if ($null -ne $blueprint) { [string]$blueprint } else { $null })
        'agent.sponsorCount'                  = $sponsorCount
        'agent.hasSponsors'                   = $hasSponsors
        'agent.ownerCount'                    = $ownerCount
        'agent.hasOwners'                     = $hasOwners
        'agent.lifecyclePresent'              = $lifecyclePresent
        'agent.hasEffectiveGoverningPolicy'   = $hasPolicy
        'agent.complianceIssueCount'          = $issueCount
        'agent.lastAttestationAgeDays'        = $attestAge
        'agent.disabledByMicrosoft'           = $(if ($null -ne $disabledBy) { [string]$disabledBy } else { $null })
    }
    return New-QuorumEvalSubject -Subject 'agentIdentity' -Id ('agent:{0}' -f $id) -Kind 'agentIdentity' -DisplayName $name -Source 'Entra' -Facts $facts
}
