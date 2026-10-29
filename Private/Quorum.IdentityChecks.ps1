Set-StrictMode -Version 1.0

# Identity retirement checks are data plus one evaluator each. Adding a check means
# adding one definition here, one evaluator function, and one case in
# Invoke-QuorumIdentityEvaluator.
# Sources: https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sms-voice-retirement
# https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-rule-member-of
# https://learn.microsoft.com/en-us/intune/device-security/security-baselines/overview
$script:QuorumIdentityChecks = @(
    [pscustomobject][ordered]@{
        Id             = 'E001'
        Title          = 'MFA relies only on SMS or voice'
        Severity       = 'high'
        SourceUrl      = 'https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sms-voice-retirement'
        RetirementDate = '2027-02-01'
        Description    = 'The account registers a telephony method (mobilePhone, alternateMobilePhone, or officePhone) and no other method that can act as MFA.'
        WhyItMatters   = 'Microsoft retires Microsoft-provided telephony delivery for SMS and voice on 2027-02-01 for all users except Global Administrators and external users, who retire on 2027-07-01. After the date, a user whose only available MFA method is SMS or voice has to register a passkey during sign-in, and that prompt blocks.'
        Remediation    = 'Register a passkey or another strong MFA method for the account. Tenants that configure a telephony provider through Microsoft Security Store keep SMS and voice working, and the export cannot show that.'
    },
    [pscustomobject][ordered]@{
        Id             = 'E002'
        Title          = 'Dynamic membership rule uses memberOf'
        Severity       = 'high'
        SourceUrl      = 'https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-rule-member-of'
        RetirementDate = '2026-11-03'
        Description    = 'The membership rule of a group or an administrative unit uses the memberOf operator.'
        WhyItMatters   = 'The public preview of the memberOf rule operator is ending. After 2026-11-03, dynamic membership groups, dynamic administrative units, and entitlement management auto-assignment policies that use the memberOf operator stop updating and remain in their last known state.'
        Remediation    = 'Replace the memberOf condition with a rule the service still evaluates, or plan for the membership to stay frozen. Entitlement management auto-assignment policies are out of scope for this check.'
    },
    [pscustomobject][ordered]@{
        Id             = 'E003'
        Title          = 'Windows security baseline profile is older than the expected version'
        Severity       = 'medium'
        SourceUrl      = 'https://learn.microsoft.com/en-us/intune/device-security/security-baselines/overview https://learn.microsoft.com/en-us/intune/whats-new/'
        RetirementDate = ''
        Description    = 'An Intune profile based on the Security Baseline for Windows 10 and later uses a baseline version older than the expected one (default 26H2).'
        WhyItMatters   = 'The Windows security baseline for Windows 11, version 26H2 is available in Intune, and existing baseline profiles do not update to a new version automatically. When a new version becomes available, settings in profiles based on older versions become read-only, and you cannot create new profiles from the older versions.'
        Remediation    = 'Review the profile customizations, then update the profile to the current baseline version or create a new profile from it. This is a version check, not a retirement, so it has no date.'
    }
)

# Telephony method names in methodsRegistered.
$script:QuorumIdentityTelephonyMethods = @('mobilePhone', 'alternateMobilePhone', 'officePhone')

# Registered values that are not an MFA method: email OTP is SSPR and guest
# sign-in only, security questions are not an MFA method, and a password is not MFA.
$script:QuorumIdentityNonMfaMethods = @('email', 'securityQuestion', 'securityQuestions', 'password')

# Other known MFA method names. A name outside all three lists is treated as a
# non-telephony MFA method, so the user is not flagged, and the name is listed
# in the run notes.
$script:QuorumIdentityKnownMfaMethods = @('microsoftAuthenticatorPush', 'passKeyDeviceBound')

# E003: default expected Windows security baseline version, and baseline display
# names that are not the Windows baseline.
$script:QuorumIdentityDefaultWindowsBaseline = '26H2'
$script:QuorumIdentityOtherBaselineMarkers = @('Defender for Endpoint', 'Edge', 'Microsoft 365')

function Get-QuorumIdentityCheckDefinitions {
    return $script:QuorumIdentityChecks
}

function Get-QuorumIdentityCheckDefinition {
    param([Parameter(Mandatory = $true)][string]$Id)
    foreach ($definition in @($script:QuorumIdentityChecks)) {
        if ($definition.Id -eq $Id) { return $definition }
    }
    throw "Unknown identity check '$Id'."
}

function Invoke-QuorumIdentityEvaluator {
    param(
        $Definition,
        $Data,
        [datetime]$AsOf
    )
    switch ($Definition.Id) {
        'E001' { return (Test-QuorumIdentitySmsVoice -Definition $Definition -Data $Data -AsOf $AsOf) }
        'E002' { return (Test-QuorumIdentityMemberOf -Definition $Definition -Data $Data -AsOf $AsOf) }
        'E003' { return (Test-QuorumIdentityWindowsBaseline -Definition $Definition -Data $Data -AsOf $AsOf) }
        default { throw "No evaluator for identity check '$($Definition.Id)'." }
    }
}

function ConvertTo-QuorumIdentityAsOf {
    param($Value)
    if ($null -eq $Value) { return [datetime]::UtcNow.Date }
    $date = [datetime]$Value
    if ($date.Kind -eq [DateTimeKind]::Local) { $date = $date.ToUniversalTime() }
    return $date.Date
}

function Get-QuorumIdentityStatus {
    param([datetime]$AsOf, [string]$RetirementDate)
    if ([string]::IsNullOrWhiteSpace($RetirementDate)) { return 'no date' }
    $date = ConvertTo-QuorumDate $RetirementDate
    if ($null -eq $date) { return 'upcoming' }
    if ($AsOf.Date -gt $date.Date) { return 'retired' }
    return 'upcoming'
}

function Get-QuorumIdentityDaysUntilRetirement {
    param([datetime]$AsOf, [string]$RetirementDate)
    if ([string]::IsNullOrWhiteSpace($RetirementDate)) { return $null }
    $date = ConvertTo-QuorumDate $RetirementDate
    if ($null -eq $date) { return 0 }
    return ($date.Date - $AsOf.Date).Days
}

function Read-QuorumIdentityData {
    param(
        [string]$RegistrationDetailsPath,
        [string]$GroupsPath,
        [string]$AdministrativeUnitsPath,
        [string]$ConfigurationPoliciesPath,
        [string]$ExpectedWindowsBaseline
    )
    if ([string]::IsNullOrWhiteSpace($ExpectedWindowsBaseline)) { $ExpectedWindowsBaseline = $script:QuorumIdentityDefaultWindowsBaseline }
    $notes = New-Object System.Collections.Generic.List[string]
    $registrations = @()
    $groups = @()
    $units = @()
    if ($RegistrationDetailsPath) {
        $items = Get-QuorumExportItems (Read-QuorumExportFile -Path $RegistrationDetailsPath) $RegistrationDetailsPath
        $registrations = @($items)
    }
    else {
        $notes.Add('No user registration details export was provided, so check E001 was not evaluated.')
    }
    if ($GroupsPath) {
        $items = Get-QuorumExportItems (Read-QuorumExportFile -Path $GroupsPath) $GroupsPath
        $groups = @($items)
    }
    else {
        $notes.Add('No groups export was provided, so the group part of check E002 was not evaluated.')
    }
    if ($AdministrativeUnitsPath) {
        $items = Get-QuorumExportItems (Read-QuorumExportFile -Path $AdministrativeUnitsPath) $AdministrativeUnitsPath
        $units = @($items)
    }
    else {
        $notes.Add('No administrative units export was provided, so the administrative unit part of check E002 was not evaluated.')
    }
    $policies = @()
    if ($ConfigurationPoliciesPath) {
        $items = Get-QuorumExportItems (Read-QuorumExportFile -Path $ConfigurationPoliciesPath) $ConfigurationPoliciesPath
        $policies = @($items)
        $notes.Add('Check E003 reads configurationPolicies only. Baseline profiles created before May 2023 use the older intents format and were not evaluated.')
    }
    else {
        $notes.Add('No configuration policies export was provided, so check E003 was not evaluated.')
    }
    return [pscustomobject][ordered]@{
        RegistrationDetails = @($registrations)
        Groups              = @($groups)
        AdministrativeUnits = @($units)
        ConfigurationPolicies = @($policies)
        ExpectedWindowsBaseline = $ExpectedWindowsBaseline
        Notes               = $notes
    }
}

function Get-QuorumIdentityMethodNames {
    param($User)
    $names = New-Object System.Collections.Generic.List[string]
    $raw = Get-QuorumProperty $User 'methodsRegistered'
    if ($null -eq $raw) { return $names.ToArray() }
    foreach ($item in @($raw)) {
        if ($null -eq $item) { continue }
        $text = ([string]$item).Trim()
        if ($text -eq '') { continue }
        $names.Add($text)
    }
    return $names.ToArray()
}

function Test-QuorumIdentitySmsVoice {
    param(
        $Definition,
        $Data,
        [datetime]$AsOf
    )
    $findings = New-Object System.Collections.Generic.List[object]
    $known = @($script:QuorumIdentityTelephonyMethods + $script:QuorumIdentityNonMfaMethods + $script:QuorumIdentityKnownMfaMethods)
    foreach ($user in @($Data.RegistrationDetails)) {
        if ($null -eq $user) { continue }
        $methods = @(Get-QuorumIdentityMethodNames $user)
        $telephony = @($methods | Where-Object { $script:QuorumIdentityTelephonyMethods -contains $_ })
        if ($telephony.Count -eq 0) { continue }
        $others = @($methods | Where-Object { $script:QuorumIdentityTelephonyMethods -notcontains $_ })
        foreach ($name in @($others | Where-Object { $known -notcontains $_ })) {
            $note = "Unknown authentication method '$name' was treated as a non-telephony MFA method, so the account was not flagged."
            if (-not $Data.Notes.Contains($note)) { $Data.Notes.Add($note) }
        }
        $blocking = @($others | Where-Object { $script:QuorumIdentityNonMfaMethods -notcontains $_ })
        if ($blocking.Count -gt 0) { continue }

        $isAdmin = ConvertTo-QuorumNullableBool (Get-QuorumProperty $user 'isAdmin')
        $isAdminValue = ($null -ne $isAdmin -and $isAdmin)
        $userType = [string](Get-QuorumProperty $user 'userType')
        $noteParts = New-Object System.Collections.Generic.List[string]
        if ($isAdminValue -or $userType -eq 'guest') {
            $noteParts.Add('The date may be 2027-07-01 if this account is a Global Administrator or an external user. The export cannot tell a Global Administrator from another admin role, nor an external user from an internal guest.')
        }
        $noteParts.Add('Tenants that configure a telephony provider through Microsoft Security Store are not affected, and the export cannot show that.')

        $findings.Add([pscustomobject][ordered]@{
            CheckId             = $Definition.Id
            Id                  = [string](Get-QuorumProperty $user 'id')
            Title               = $Definition.Title
            Severity            = $Definition.Severity
            SourceUrl           = $Definition.SourceUrl
            Description         = $Definition.Description
            WhyItMatters        = $Definition.WhyItMatters
            Remediation         = $Definition.Remediation
            UserPrincipalName   = [string](Get-QuorumProperty $user 'userPrincipalName')
            UserType            = $userType
            IsAdmin             = $isAdminValue
            Methods             = $methods
            RetirementDate      = $Definition.RetirementDate
            DaysUntilRetirement = (Get-QuorumIdentityDaysUntilRetirement -AsOf $AsOf -RetirementDate $Definition.RetirementDate)
            Status              = (Get-QuorumIdentityStatus -AsOf $AsOf -RetirementDate $Definition.RetirementDate)
            Note                = ($noteParts -join ' ')
        })
    }
    return $findings.ToArray()
}

function Test-QuorumIdentityMemberOf {
    param(
        $Definition,
        $Data,
        [datetime]$AsOf
    )
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($Data.Groups)) {
        if ($null -eq $group) { continue }
        $rule = [string](Get-QuorumProperty $group 'membershipRule')
        if (-not (Test-QuorumIdentityMemberOfRule $rule)) { continue }
        $findings.Add((New-QuorumIdentityMemberOfFinding -Definition $Definition -AsOf $AsOf -ObjectType 'group' -Item $group -MembershipRule $rule))
    }
    foreach ($unit in @($Data.AdministrativeUnits)) {
        if ($null -eq $unit) { continue }
        $rule = [string](Get-QuorumProperty $unit 'membershipRule')
        if (-not (Test-QuorumIdentityMemberOfRule $rule)) { continue }
        $findings.Add((New-QuorumIdentityMemberOfFinding -Definition $Definition -AsOf $AsOf -ObjectType 'administrativeUnit' -Item $unit -MembershipRule $rule))
    }
    return $findings.ToArray()
}

function Test-QuorumIdentityMemberOfRule {
    param([string]$Rule)
    if ([string]::IsNullOrWhiteSpace($Rule)) { return $false }
    if ($Rule -match '(?i)\b(user|device)\.memberof\b') { return $true }
    if ($Rule -match '(?i)\bmemberof\s+-any\b') { return $true }
    return $false
}

function New-QuorumIdentityMemberOfFinding {
    param(
        $Definition,
        [datetime]$AsOf,
        [string]$ObjectType,
        $Item,
        [string]$MembershipRule
    )
    return [pscustomobject][ordered]@{
        CheckId             = $Definition.Id
        Id                  = [string](Get-QuorumProperty $Item 'id')
        Title               = $Definition.Title
        Severity            = $Definition.Severity
        SourceUrl           = $Definition.SourceUrl
        Description         = $Definition.Description
        WhyItMatters        = $Definition.WhyItMatters
        Remediation         = $Definition.Remediation
        ObjectType          = $ObjectType
        DisplayName         = [string](Get-QuorumProperty $Item 'displayName')
        MembershipType      = [string](Get-QuorumProperty $Item 'membershipType')
        ProcessingState     = [string](Get-QuorumProperty $Item 'membershipRuleProcessingState')
        MembershipRule      = $MembershipRule
        RetirementDate      = $Definition.RetirementDate
        DaysUntilRetirement = (Get-QuorumIdentityDaysUntilRetirement -AsOf $AsOf -RetirementDate $Definition.RetirementDate)
        Status              = (Get-QuorumIdentityStatus -AsOf $AsOf -RetirementDate $Definition.RetirementDate)
        Note                = 'After the retirement date the membership rule stops updating and the object stays in its last known state.'
    }
}

function Test-QuorumIdentityWindowsBaselineName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -match '(?i)Security Baseline for Windows 10 and later') { return $true }
    if ($Name -notmatch '(?i)Windows' -or $Name -notmatch '(?i)Security Baseline') { return $false }
    foreach ($marker in $script:QuorumIdentityOtherBaselineMarkers) {
        if ($Name.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
    }
    return $true
}

function ConvertTo-QuorumBaselineVersion {
    # Returns @(year, half) for a token such as 24H2, or $null.
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(?i)\b(\d{2})H([12])\b')
    if (-not $m.Success) { return $null }
    return @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value)
}

function Test-QuorumIdentityWindowsBaseline {
    param(
        $Definition,
        $Data,
        [datetime]$AsOf
    )
    $findings = New-Object System.Collections.Generic.List[object]
    $expectedText = [string]$Data.ExpectedWindowsBaseline
    if ([string]::IsNullOrWhiteSpace($expectedText)) { $expectedText = $script:QuorumIdentityDefaultWindowsBaseline }
    $expected = ConvertTo-QuorumBaselineVersion $expectedText
    foreach ($policy in @($Data.ConfigurationPolicies)) {
        if ($null -eq $policy) { continue }
        $reference = Get-QuorumProperty $policy 'templateReference'
        if ($null -eq $reference) { continue }
        if ([string](Get-QuorumProperty $reference 'templateFamily') -ne 'baseline') { continue }
        $templateName = [string](Get-QuorumProperty $reference 'templateDisplayName')
        if (-not (Test-QuorumIdentityWindowsBaselineName $templateName)) { continue }

        $displayVersion = [string](Get-QuorumProperty $reference 'templateDisplayVersion')
        $current = ConvertTo-QuorumBaselineVersion $displayVersion
        if ($null -eq $current) { $current = ConvertTo-QuorumBaselineVersion $templateName }
        $severity = $Definition.Severity
        $note = 'Profile settings are read-only on older versions; update the profile or create a new one after reviewing customizations.'
        if ($null -ne $current) {
            if ($current[0] -gt $expected[0]) { continue }
            if ($current[0] -eq $expected[0] -and $current[1] -ge $expected[1]) { continue }
        }
        elseif ([string]::IsNullOrWhiteSpace($displayVersion)) {
            $severity = 'low'
            $note = 'Version could not be determined from the export.'
        }
        # A non-empty version without a yyHn token, such as November 2021, predates 23H2.

        $findings.Add([pscustomobject][ordered]@{
            CheckId             = $Definition.Id
            Id                  = [string](Get-QuorumProperty $policy 'id')
            Title               = $Definition.Title
            Severity            = $severity
            SourceUrl           = $Definition.SourceUrl
            Description         = $Definition.Description
            WhyItMatters        = $Definition.WhyItMatters
            Remediation         = $Definition.Remediation
            PolicyId            = [string](Get-QuorumProperty $policy 'id')
            PolicyName          = [string](Get-QuorumProperty $policy 'name')
            TemplateDisplayName = $templateName
            CurrentVersion      = $displayVersion
            ExpectedVersion     = $expectedText
            RetirementDate      = ''
            DaysUntilRetirement = $null
            Status              = 'outdated'
            Note                = $note
        })
    }
    return $findings.ToArray()
}

function New-QuorumIdentitySummary {
    param(
        $Definitions,
        $Findings,
        [datetime]$AsOf
    )
    $summary = New-Object System.Collections.Generic.List[object]
    foreach ($definition in @($Definitions)) {
        $mine = @(@($Findings) | Where-Object { (Get-QuorumProperty $_ 'CheckId') -eq $definition.Id })
        $summary.Add([pscustomobject][ordered]@{
            Id                 = $definition.Id
            Title              = $definition.Title
            Severity           = $definition.Severity
            SourceUrl          = $definition.SourceUrl
            RetirementDate     = $definition.RetirementDate
            Status             = (Get-QuorumIdentityStatus -AsOf $AsOf -RetirementDate $definition.RetirementDate)
            DaysUntilRetirement = (Get-QuorumIdentityDaysUntilRetirement -AsOf $AsOf -RetirementDate $definition.RetirementDate)
            FindingCount       = $mine.Count
            Description        = $definition.Description
            WhyItMatters       = $definition.WhyItMatters
            Remediation        = $definition.Remediation
        })
    }
    return $summary.ToArray()
}

function Get-QuorumIdentityDetailColumns {
    param($Findings)
    $skip = @(
        'CheckId', 'Title', 'Severity', 'SourceUrl', 'Description', 'WhyItMatters',
        'Remediation', 'RetirementDate', 'DaysUntilRetirement', 'Status'
    )
    $columns = New-Object System.Collections.Generic.List[string]
    foreach ($finding in @($Findings)) {
        foreach ($prop in @($finding.PSObject.Properties)) {
            if ($skip -contains $prop.Name) { continue }
            if (-not $columns.Contains($prop.Name)) { $columns.Add($prop.Name) }
        }
        break
    }
    return $columns.ToArray()
}

function ConvertTo-QuorumIdentityCell {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) {
        if ($Value) { return 'Yes' }
        return 'No'
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($item in @($Value)) { $parts.Add([string]$item) }
        return ($parts -join '|')
    }
    return [string]$Value
}

function New-QuorumIdentityCsv {
    param($Findings)
    $detailColumns = Get-QuorumIdentityDetailColumns -Findings @($Findings)
    $columns = @('CheckId', 'Severity', 'Title', 'Status', 'RetirementDate', 'DaysUntilRetirement')
    $columns += @($detailColumns)
    $columns += @('SourceUrl')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(($columns -join ','))
    foreach ($finding in @($Findings)) {
        $encoded = New-Object System.Collections.Generic.List[string]
        foreach ($column in $columns) {
            $encoded.Add((ConvertTo-QuorumCsvField (ConvertTo-QuorumIdentityCell (Get-QuorumProperty $finding $column))))
        }
        $lines.Add(($encoded -join ','))
    }
    return (($lines -join "`n") + "`n")
}

function New-QuorumIdentityMarkdown {
    param(
        $Findings,
        $Summary,
        $Notes,
        [datetime]$AsOf,
        [string]$Mode,
        [bool]$Redacted
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Quorum identity check summary')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| | |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine('| Mode | ' + $Mode + ' |')
    [void]$sb.AppendLine('| Reference date | ' + $AsOf.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) + ' |')
    [void]$sb.AppendLine('| Report built | ' + [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture) + ' |')
    [void]$sb.AppendLine('| Findings | ' + @($Findings).Count + ' |')
    [void]$sb.AppendLine('| Redacted | ' + $(if ($Redacted) { 'yes' } else { 'no' }) + ' |')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Checks')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Id | Severity | Title | Retirement date | Status | Findings | Source |')
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- | ---: | --- |')
    foreach ($check in @($Summary)) {
        [void]$sb.AppendLine('| ' + $check.Id + ' | ' + $check.Severity + ' | ' + (ConvertTo-QuorumMarkdownCell $check.Title) + ' | ' + $check.RetirementDate + ' | ' + $check.Status + ' | ' + $check.FindingCount + ' | ' + $check.SourceUrl + ' |')
    }
    [void]$sb.AppendLine('')
    if (@($Notes).Count -gt 0) {
        [void]$sb.AppendLine('## Notes')
        [void]$sb.AppendLine('')
        foreach ($note in @($Notes)) {
            [void]$sb.AppendLine('- ' + (ConvertTo-QuorumMarkdownCell $note))
        }
        [void]$sb.AppendLine('')
    }
    foreach ($check in @($Summary)) {
        $mine = @(@($Findings) | Where-Object { (Get-QuorumProperty $_ 'CheckId') -eq $check.Id })
        if ($mine.Count -eq 0) { continue }
        [void]$sb.AppendLine('## ' + $check.Id + ' - ' + $check.Title)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Severity: ' + $check.Severity)
        [void]$sb.AppendLine('')
        if ([string]::IsNullOrWhiteSpace([string]$check.RetirementDate)) {
            [void]$sb.AppendLine('Retirement date: none (version check)')
        }
        else {
            [void]$sb.AppendLine('Retirement date: ' + $check.RetirementDate + ' (' + $check.Status + ')')
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Source: ' + $check.SourceUrl)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine((ConvertTo-QuorumMarkdownCell $check.Description))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('**Why it matters.** ' + (ConvertTo-QuorumMarkdownCell $check.WhyItMatters))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('**What to do.** ' + (ConvertTo-QuorumMarkdownCell $check.Remediation))
        [void]$sb.AppendLine('')
        $detailColumns = Get-QuorumIdentityDetailColumns -Findings $mine
        $columns = @($detailColumns)
        [void]$sb.AppendLine('| ' + ($columns -join ' | ') + ' |')
        [void]$sb.AppendLine('| ' + (@($columns | ForEach-Object { '---' }) -join ' | ') + ' |')
        foreach ($finding in $mine) {
            $cells = New-Object System.Collections.Generic.List[string]
            foreach ($column in $columns) {
                $cells.Add((ConvertTo-QuorumMarkdownCell (ConvertTo-QuorumIdentityCell (Get-QuorumProperty $finding $column))))
            }
            [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
        }
        [void]$sb.AppendLine('')
    }
    return $sb.ToString()
}

function Write-QuorumIdentityReport {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        $Findings,
        $Summary,
        $Notes,
        [datetime]$AsOf,
        [string]$Mode,
        [bool]$Redacted,
        $RedactionMap
    )
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }
    $jsonPath = Join-QuorumPath $OutputPath 'Quorum-IdentityFindings.json'
    $csvPath = Join-QuorumPath $OutputPath 'Quorum-IdentityFindings.csv'
    $markdownPath = Join-QuorumPath $OutputPath 'Quorum-IdentitySummary.md'
    $mapPath = $null

    $doc = [ordered]@{
        meta = [ordered]@{
            mode         = $Mode
            asOf         = $AsOf.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            generatedAt  = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            findingCount = @($Findings).Count
            checkCount   = @($Summary).Count
            redacted     = $Redacted
        }
        checks   = @($Summary)
        findings = @($Findings)
        notes    = @($Notes)
    }
    $json = ConvertTo-QuorumJson $doc
    Write-QuorumTextFile -Path $jsonPath -Content ($json + "`n")
    Write-QuorumTextFile -Path $csvPath -Content (New-QuorumIdentityCsv -Findings @($Findings))
    Write-QuorumTextFile -Path $markdownPath -Content (New-QuorumIdentityMarkdown -Findings @($Findings) -Summary @($Summary) -Notes @($Notes) -AsOf $AsOf -Mode $Mode -Redacted $Redacted)
    if ($null -ne $RedactionMap) {
        $mapPath = Join-QuorumPath $OutputPath 'Quorum-IdentityRedactionMap.json'
        $mapDoc = [ordered]@{
            warning = 'Do not share this file. It reverses the pseudonyms in the Quorum identity findings written beside it.'
            entries = @($RedactionMap)
        }
        Write-QuorumTextFile -Path $mapPath -Content ((ConvertTo-QuorumJson $mapDoc) + "`n")
    }
    [pscustomobject]@{
        JsonPath         = $jsonPath
        CsvPath          = $csvPath
        MarkdownPath     = $markdownPath
        RedactionMapPath = $mapPath
    }
}
