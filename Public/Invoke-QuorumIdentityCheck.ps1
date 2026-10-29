Set-StrictMode -Version 1.0

function Invoke-QuorumIdentityCheck {
    <#
    .SYNOPSIS
        Evaluate announced Microsoft Entra identity retirements from JSON exports.

    .DESCRIPTION
        Quorum reads identity exports you already have and checks them against two
        announced Microsoft Entra retirements. Nothing is sent anywhere. The command
        never calls Microsoft Graph itself; it only reads the JSON files you point it
        at, and -Demo does not touch the network at all.

        E001 flags an account whose MFA relies only on SMS or voice.
        E002 flags a dynamic membership rule that uses the memberOf operator.

    .PARAMETER RegistrationDetailsPath
        Offline export of GET https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails.
        A plain JSON array or a Graph response page with a value array.

    .PARAMETER GroupsPath
        Offline export of the dynamic membership groups of
        GET https://graph.microsoft.com/v1.0/groups?$filter=groupTypes/any(c:c eq 'DynamicMembership')&$select=id,displayName,groupTypes,membershipRule,membershipRuleProcessingState

    .PARAMETER AdministrativeUnitsPath
        Offline export of
        GET https://graph.microsoft.com/v1.0/directory/administrativeUnits?$select=id,displayName,membershipType,membershipRule,membershipRuleProcessingState

    .PARAMETER AsOf
        Reference date for DaysUntilRetirement and for the Status field. Defaults to now.
        Only the date part is used. A finding whose retirement date is before the
        reference date has the status retired.

    .PARAMETER OutputPath
        Directory for the report files. Defaults to .\quorum-out.

    .PARAMETER Redact
        Pseudonymize user principal names consistently inside this run. A reversal map
        is written next to the findings. Do not share the map.

    .PARAMETER Demo
        Run offline against the bundled synthetic exports in data/demo-identity.

    .PARAMETER FailOnSeverity
        After the files are written, throw if any finding is at this severity or worse
        (critical, high, medium, low, info). Use it in scheduled tasks and pipelines.

    .EXAMPLE
        Import-Module ./Quorum.psd1
        Invoke-QuorumIdentityCheck -Demo

        Writes quorum-out\Quorum-IdentityFindings.json, Quorum-IdentityFindings.csv,
        and Quorum-IdentitySummary.md from fictional accounts.

    .EXAMPLE
        Invoke-QuorumIdentityCheck -RegistrationDetailsPath .\userRegistrationDetails.json -GroupsPath .\groups.json -AdministrativeUnitsPath .\administrativeUnits.json -Redact

        Evaluates exports you already have without an app registration.

    .EXAMPLE
        Invoke-QuorumIdentityCheck -Demo -FailOnSeverity high

        Writes the files, then throws because the demo has high findings.
    #>
    [CmdletBinding()]
    param(
        [string]$RegistrationDetailsPath,
        [string]$GroupsPath,
        [string]$AdministrativeUnitsPath,
        [Nullable[datetime]]$AsOf,
        [string]$OutputPath,
        [switch]$Redact,
        [switch]$Demo,
        [ValidateSet('critical', 'high', 'medium', 'low', 'info')]
        [string]$FailOnSeverity
    )

    $ErrorActionPreference = 'Stop'
    if ($Demo) {
        if ($RegistrationDetailsPath -or $GroupsPath -or $AdministrativeUnitsPath) {
            throw '-Demo cannot be combined with an export path.'
        }
        $demoPath = Join-QuorumPath $script:QuorumModuleRoot 'data' 'demo-identity'
        $RegistrationDetailsPath = Join-QuorumPath $demoPath 'userRegistrationDetails.json'
        $GroupsPath = Join-QuorumPath $demoPath 'groups.json'
        $AdministrativeUnitsPath = Join-QuorumPath $demoPath 'administrativeUnits.json'
    }
    if (-not $RegistrationDetailsPath -and -not $GroupsPath -and -not $AdministrativeUnitsPath) {
        throw 'Specify -RegistrationDetailsPath, -GroupsPath, or -AdministrativeUnitsPath, or -Demo for the bundled sample.'
    }
    if (-not $OutputPath) {
        $OutputPath = [System.IO.Path]::Combine([string](Get-Location), 'quorum-out')
    }

    $mode = 'Import'
    if ($Demo) { $mode = 'Demo' }
    $asOf = ConvertTo-QuorumIdentityAsOf $AsOf
    $data = Read-QuorumIdentityData -RegistrationDetailsPath $RegistrationDetailsPath -GroupsPath $GroupsPath -AdministrativeUnitsPath $AdministrativeUnitsPath

    $collected = New-Object System.Collections.Generic.List[object]
    $definitions = Get-QuorumIdentityCheckDefinitions
    foreach ($definition in @($definitions)) {
        $items = Invoke-QuorumIdentityEvaluator -Definition $definition -Data $data -AsOf $asOf
        foreach ($finding in @($items)) {
            $collected.Add($finding)
        }
    }
    $sorted = @($collected.ToArray() | Sort-Object -Property `
        @{ Expression = { [string](Get-QuorumProperty $_ 'CheckId') } }, `
        @{ Expression = { [string](Get-QuorumProperty $_ 'UserPrincipalName') } }, `
        @{ Expression = { [string](Get-QuorumProperty $_ 'DisplayName') } }, `
        @{ Expression = { [string](Get-QuorumProperty $_ 'Id') } })
    $findings = @($sorted)

    $map = $null
    if ($Redact) {
        $map = Protect-QuorumIdentity -Findings $findings -Notes $data.Notes
    }

    $summaryItems = New-QuorumIdentitySummary -Definitions @($definitions) -Findings $findings -AsOf $asOf
    $summary = @($summaryItems)
    $written = Write-QuorumIdentityReport -OutputPath $OutputPath -Findings $findings -Summary $summary -Notes @($data.Notes.ToArray()) -AsOf $asOf -Mode $mode -Redacted $Redact.IsPresent -RedactionMap $map

    $highest = $null
    foreach ($finding in @($findings)) {
        $severity = [string](Get-QuorumProperty $finding 'Severity')
        if ($null -eq $highest -or (Get-QuorumSeverityRank $severity) -lt (Get-QuorumSeverityRank $highest)) {
            $highest = $severity
        }
    }

    Write-Host ("Quorum identity check wrote {0} findings." -f @($findings).Count)
    Write-Host ("Identity summary: {0}" -f $written.MarkdownPath)

    $result = [pscustomobject]@{
        PSTypeName       = 'Quorum.IdentityResult'
        Mode             = $mode
        AsOf             = $asOf
        FindingCount     = @($findings).Count
        Findings         = @($findings)
        Summary          = @($summary)
        Notes            = @($data.Notes.ToArray())
        HighestSeverity  = $highest
        OutputPath       = $OutputPath
        JsonPath         = $written.JsonPath
        CsvPath          = $written.CsvPath
        MarkdownPath     = $written.MarkdownPath
        RedactionMapPath = $written.RedactionMapPath
    }
    if ($FailOnSeverity) {
        $limit = Get-QuorumSeverityRank $FailOnSeverity
        $over = @(@($findings) | Where-Object { (Get-QuorumSeverityRank ([string](Get-QuorumProperty $_ 'Severity'))) -le $limit })
        if ($over.Count -gt 0) {
            throw ("Quorum identity check found {0} finding(s) at severity {1} or worse. The findings were written to {2}." -f $over.Count, $FailOnSeverity, $written.JsonPath)
        }
    }
    return $result
}
