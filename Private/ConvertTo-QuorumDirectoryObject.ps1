Set-StrictMode -Version 1.0

# Directory objects (groups and administrative units) are evaluated by rules with
# `subject: directoryObject`. They are not devices: they never join the device
# matcher and never count as devices in the report.

$script:QuorumDirectoryFacts = @(
    'directory.kind', 'directory.displayName', 'directory.dynamic',
    'directory.membershipRule', 'directory.processingState', 'directory.usesMemberOf'
)

function Test-QuorumMemberOfRule {
    param([string]$Rule)
    if ([string]::IsNullOrWhiteSpace($Rule)) { return $false }
    # Microsoft documents the operator as user.memberof or device.memberof,
    # for example: user.memberof -any (group.objectId -in ['<id>'])
    return [regex]::IsMatch($Rule, '(?i)\b(?:user|device)\s*\.\s*memberof\b')
}

function ConvertTo-QuorumDirectoryObject {
    param($Group, $AdministrativeUnit)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($raw in @($Group)) {
        if ($null -eq $raw) { continue }
        $types = @()
        if ($raw.PSObject.Properties['groupTypes'] -and $null -ne $raw.groupTypes) { $types = @($raw.groupTypes | ForEach-Object { [string]$_ }) }
        $dynamic = [bool](@($types | Where-Object { $_ -eq 'DynamicMembership' }).Count -gt 0)
        $items.Add((New-QuorumDirectoryObject -Raw $raw -Kind 'group' -Dynamic $dynamic))
    }
    foreach ($raw in @($AdministrativeUnit)) {
        if ($null -eq $raw) { continue }
        $type = ''
        if ($raw.PSObject.Properties['membershipType'] -and $null -ne $raw.membershipType) { $type = [string]$raw.membershipType }
        $dynamic = ($type -eq 'Dynamic')
        $items.Add((New-QuorumDirectoryObject -Raw $raw -Kind 'administrativeUnit' -Dynamic $dynamic))
    }
    return $items.ToArray()
}

function New-QuorumDirectoryObject {
    param($Raw, [string]$Kind, [bool]$Dynamic)
    $id = ''
    if ($Raw.PSObject.Properties['id'] -and $Raw.id) { $id = [string]$Raw.id }
    $name = $id
    if ($Raw.PSObject.Properties['displayName'] -and $Raw.displayName) { $name = [string]$Raw.displayName }
    $rule = $null
    if ($Raw.PSObject.Properties['membershipRule'] -and $Raw.membershipRule) { $rule = [string]$Raw.membershipRule }
    $state = $null
    if ($Raw.PSObject.Properties['membershipRuleProcessingState'] -and $Raw.membershipRuleProcessingState) {
        $state = ([string]$Raw.membershipRuleProcessingState).ToLowerInvariant()
    }
    $prefix = 'group'
    if ($Kind -eq 'administrativeUnit') { $prefix = 'au' }
    $facts = @{
        'directory.kind'            = $Kind
        'directory.displayName'     = $name
        'directory.dynamic'         = $Dynamic
        'directory.membershipRule'  = $rule
        'directory.processingState' = $state
        'directory.usesMemberOf'    = ($Dynamic -and (Test-QuorumMemberOfRule $rule))
    }
    [pscustomobject]@{
        PSTypeName      = 'Quorum.DirectoryObject'
        Id              = ('{0}:{1}' -f $prefix, $id)
        Kind            = $Kind
        HostnameDisplay = $name
        MatchMethod     = 'directory'
        MatchConfidence = 'n/a'
        MatchScore      = $null
        Records         = @([pscustomobject]@{ Source = 'Entra' })
        Facts           = $facts
    }
}
