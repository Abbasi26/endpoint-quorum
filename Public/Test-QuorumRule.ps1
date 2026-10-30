Set-StrictMode -Version 1.0

$script:QuorumKnownFacts = @(
    'intune.present', 'intune.complianceState', 'intune.lastSyncAgeDays', 'intune.osBuild',
    'entra.present', 'entra.enabled', 'entra.isCompliant', 'entra.isManaged', 'entra.trustType',
    'entra.operatingSystem', 'entra.lastSignInAgeDays', 'entra.osBuild',
    'defender.present', 'defender.healthStatus', 'defender.riskScore', 'defender.exposureLevel',
    'defender.onboardingStatus', 'defender.lastSeenAgeDays', 'defender.osBuild',
    'os.buildMismatch', 'os.builds', 'compliance.disagrees',
    'hostname.key', 'hostname.duplicate', 'hostname.duplicateCount',
    'match.method', 'match.confidence', 'match.score', 'sources.count'
)
$script:QuorumKnownOps = @('eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'contains', 'in', 'nin', 'exists')

function Test-QuorumRule {
    <#
    .SYNOPSIS
        Lint Quorum rule files before you run them.

    .DESCRIPTION
        Checks every YAML rule in a directory (or one file) for the required fields,
        a valid severity and id, duplicate ids, unknown facts, unknown operators,
        predicates without a value, and valueFrom references to parameters that do
        not exist. An unknown fact never matches at run time, so a typo would
        otherwise silently disable a rule. Nothing is evaluated against devices.

        Returns one object per file with Path, Id, Valid, and Errors. With -Quiet it
        returns a single boolean.

    .PARAMETER Path
        A rules directory or a single YAML file. Defaults to the module rules directory.

    .PARAMETER Quiet
        Return $true when every file is valid, otherwise $false.

    .EXAMPLE
        Test-QuorumRule -Path ./rules | Where-Object { -not $_.Valid }

    .EXAMPLE
        if (-not (Test-QuorumRule -Path ./my-rules -Quiet)) { exit 1 }
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Quiet
    )
    if (-not $Path) { $Path = Join-QuorumPath $script:QuorumModuleRoot 'rules' }
    $files = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $files = @(Get-Item -LiteralPath $Path)
    }
    elseif (Test-Path -LiteralPath $Path -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $Path -File |
            Where-Object { $_.Extension -eq '.yaml' -or $_.Extension -eq '.yml' } |
            Sort-Object Name)
    }
    else {
        throw "Rules path not found: $Path"
    }
    if ($files.Count -eq 0) { throw "No YAML rules found in $Path" }

    $results = New-Object System.Collections.Generic.List[object]
    $ids = @{}
    foreach ($file in $files) {
        $errors = New-Object System.Collections.Generic.List[string]
        $id = $null
        try {
            $doc = ConvertFrom-QuorumYaml -Path $file.FullName
            $rule = ConvertTo-QuorumRule $doc $file.FullName
            $id = $rule.Id
            if ($ids.ContainsKey($id)) {
                $errors.Add("Duplicate rule id '$id' (also in $($ids[$id])).")
            }
            else {
                $ids[$id] = $file.Name
            }
            Test-QuorumRuleCondition -Condition $rule.Condition -Parameter $rule.Parameters -Errors $errors -Where 'condition'
            if ($rule.GroupBy -and $script:QuorumKnownFacts -notcontains $rule.GroupBy) {
                $errors.Add("groupBy uses unknown fact '$($rule.GroupBy)'.")
            }
            if (-not (Test-QuorumRuleRemediation $rule.Remediation)) {
                $errors.Add("remediation is too short to be actionable. Write at least one full sentence that names a console and a check.")
            }
        }
        catch {
            $errors.Add((Get-QuorumErrorMessage $_))
        }
        $results.Add([pscustomobject]@{
            PSTypeName = 'Quorum.RuleCheck'
            Path       = $file.FullName
            Id         = $id
            Valid      = ($errors.Count -eq 0)
            Errors     = $errors.ToArray()
        })
    }
    if ($Quiet) {
        return (@($results | Where-Object { -not $_.Valid }).Count -eq 0)
    }
    return $results.ToArray()
}

function Test-QuorumRuleCondition {
    param($Condition, $Parameter, $Errors, [string]$Where)
    if ($null -eq $Condition -or -not ($Condition -is [System.Collections.IDictionary])) {
        $Errors.Add("$Where is not a mapping.")
        return
    }
    $keys = @('all', 'any', 'not', 'fact') | Where-Object { $Condition.Contains($_) }
    if (@($keys).Count -ne 1) {
        $Errors.Add("$Where needs exactly one of all, any, not, or fact.")
        return
    }
    switch (@($keys)[0]) {
        'all' { $i = 0; foreach ($item in (ConvertTo-QuorumConditionItems $Condition['all'])) { Test-QuorumRuleCondition $item $Parameter $Errors "$Where.all[$i]"; $i++ } }
        'any' { $i = 0; foreach ($item in (ConvertTo-QuorumConditionItems $Condition['any'])) { Test-QuorumRuleCondition $item $Parameter $Errors "$Where.any[$i]"; $i++ } }
        'not' { Test-QuorumRuleCondition $Condition['not'] $Parameter $Errors "$Where.not" }
        'fact' {
            $name = [string]$Condition['fact']
            if ($script:QuorumKnownFacts -notcontains $name) {
                $Errors.Add("$Where uses unknown fact '$name'. It would never match.")
            }
            $op = $null
            if ($Condition.Contains('op') -and $Condition['op']) { $op = ([string]$Condition['op']).Trim().ToLowerInvariant() }
            if (-not $op) { $Errors.Add("$Where fact '$name' is missing an op.") }
            elseif ($script:QuorumKnownOps -notcontains $op) { $Errors.Add("$Where uses unknown operator '$op'.") }
            if ($Condition.Contains('valueFrom') -and $Condition['valueFrom']) {
                $ref = [string]$Condition['valueFrom']
                if (-not $Parameter.ContainsKey($ref)) { $Errors.Add("$Where references parameter '$ref', which is not defined.") }
            }
            elseif (-not $Condition.Contains('value') -and $op -ne 'exists') {
                $Errors.Add("$Where fact '$name' needs value or valueFrom.")
            }
            elseif ($op -eq 'exists' -and $null -eq (ConvertTo-QuorumNullableBool $Condition['value'])) {
                $Errors.Add("$Where uses exists without true or false.")
            }
        }
    }
}

function Test-QuorumRuleRemediation {
    param([string]$Remediation)
    if ([string]::IsNullOrEmpty($Remediation)) { return $false }
    $text = $Remediation.Trim()
    if ($text -eq '') { return $false }
    $words = $text -split '\s+'
    if (@($words).Count -lt 4) { return $false }
    if (-not ($text -match '\.' -or $text -match '\?' -or $text -match '!')) { return $false }
    return $true
}
