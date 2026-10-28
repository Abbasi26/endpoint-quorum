Set-StrictMode -Version 1.0

function Invoke-Quorum {
    <#
    .SYNOPSIS
        Compare Intune, Entra ID, and Defender for Endpoint and report the contradictions.

    .DESCRIPTION
        Quorum reads device state from each source, matches records, and evaluates the YAML
        rules in the rules directory. It writes an HTML report, a Markdown summary, and
        CSV and JSON findings. Nothing is sent anywhere except the read calls you ask for,
        and -Demo does not touch the network at all.

        Live collection is read-only. Delegated sign-in uses the device-code flow so it
        works in PowerShell 7 on Windows, macOS, and Linux. Certificate sign-in uses an
        application registration and a client-credentials JWT.

    .PARAMETER Demo
        Run offline against the bundled synthetic inventory.

    .PARAMETER Redact
        Pseudonymize hostnames, user names, UPNs, and IP addresses consistently inside
        this run. A reversal map is written next to the report. Do not share the map.

    .PARAMETER TenantId
        Entra tenant id or verified domain for a live collection.

    .PARAMETER ClientId
        Application (client) id of the app registration that holds only the read permissions.

    .PARAMETER CertificateThumbprint
        Windows certificate-store thumbprint for app-only sign-in.

    .PARAMETER CertificatePath
        Path to a PFX certificate for app-only sign-in. Use this on macOS and Linux.

    .PARAMETER CertificatePassword
        Password for the PFX, as a SecureString.

    .PARAMETER OutputPath
        Directory for the report files. Defaults to .\quorum-out.

    .PARAMETER RulesPath
        A rules directory or a single YAML file. Defaults to the module rules directory.

    .PARAMETER DemoDataPath
        Alternate synthetic inventory. Used by tests. Ignored unless -Demo is set.

    .PARAMETER InventoryPath
        Evaluate an exported inventory offline. Same shape as data/demo-inventory.json:
        an object with intune, entra, and defender arrays of raw API objects and an
        optional asOf timestamp. No sign-in, no network.

    .PARAMETER IntunePath
        Offline Intune export: a JSON file with the managedDevices objects, either as an
        array or as a Graph response page with a value property. Can be combined with
        -EntraPath and -DefenderPath; a source you leave out is reported as not collected.

    .PARAMETER EntraPath
        Offline Entra ID devices export (array or Graph page with value).

    .PARAMETER DefenderPath
        Offline Defender for Endpoint machines export (array or API page with value).

    .PARAMETER AsOf
        Reference time for ages in an offline import. Defaults to the inventory asOf,
        or the current UTC time.

    .PARAMETER FailOnSeverity
        After the report is written, throw if any finding is at this severity or worse
        (critical, high, medium, low, info). Use it in scheduled tasks and pipelines.

    .PARAMETER GraphBaseUri
        Microsoft Graph base URI, including the version. Default: https://graph.microsoft.com/v1.0

    .PARAMETER DefenderBaseUri
        Defender for Endpoint API host. Default: https://api.security.microsoft.com

    .PARAMETER AuthorityHost
        Entra token authority host. Default: https://login.microsoftonline.com

    .EXAMPLE
        Import-Module ./Quorum.psd1
        Invoke-Quorum -Demo

        Writes quorum-out\Quorum-Report.html from fictional devices.

    .EXAMPLE
        Invoke-Quorum -IntunePath .\managedDevices.json -EntraPath .\devices.json -DefenderPath .\machines.json -Redact

        Evaluates exports you already have (for example from Graph Explorer) without an app registration.

    .EXAMPLE
        Invoke-Quorum -Demo -FailOnSeverity high

        Writes the report, then throws because the demo has high findings.

    .EXAMPLE
        Invoke-Quorum -TenantId 00000000-0000-0000-0000-000000000000 -ClientId 11111111-1111-1111-1111-111111111111

        Signs in with two device codes (Graph, then Defender) and writes a live report.

    .EXAMPLE
        $secret = Read-Host -AsSecureString -Prompt 'PFX password'
        Invoke-Quorum -TenantId contoso.onmicrosoft.com -ClientId 11111111-1111-1111-1111-111111111111 -CertificatePath .\quorum.pfx -CertificatePassword $secret -Redact
    #>
    [CmdletBinding()]
    param(
        [switch]$Demo,
        [switch]$Redact,
        [string]$TenantId,
        [string]$ClientId,
        [string]$CertificateThumbprint,
        [string]$CertificatePath,
        [securestring]$CertificatePassword,
        [string]$OutputPath,
        [string]$RulesPath,
        [string]$DemoDataPath,
        [string]$InventoryPath,
        [string]$IntunePath,
        [string]$EntraPath,
        [string]$DefenderPath,
        [Nullable[datetime]]$AsOf,
        [ValidateSet('critical', 'high', 'medium', 'low', 'info')]
        [string]$FailOnSeverity,
        [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',
        [string]$DefenderBaseUri = 'https://api.security.microsoft.com',
        [string]$AuthorityHost = 'https://login.microsoftonline.com'
    )

    $ErrorActionPreference = 'Stop'
    $import = [bool]($InventoryPath -or $IntunePath -or $EntraPath -or $DefenderPath)
    if ($InventoryPath -and ($IntunePath -or $EntraPath -or $DefenderPath)) {
        throw 'Use -InventoryPath or the per-source -IntunePath/-EntraPath/-DefenderPath, not both.'
    }
    if ($Demo -and $TenantId) { throw '-Demo cannot be combined with -TenantId.' }
    $modeCount = @($Demo.IsPresent, [bool]$TenantId, $import) | Where-Object { $_ }
    if (@($modeCount).Count -gt 1) { throw 'Choose one of -Demo, an offline import (-InventoryPath or -IntunePath/-EntraPath/-DefenderPath), or -TenantId.' }
    if (-not $Demo -and -not $TenantId -and -not $import) {
        throw 'Specify -Demo for the offline sample, -InventoryPath or -IntunePath/-EntraPath/-DefenderPath for exported files, or -TenantId and -ClientId for a live read-only collection.'
    }
    if ($TenantId -and -not $ClientId) { throw '-ClientId is required for a live collection.' }
    if ($CertificateThumbprint -and $CertificatePath) {
        throw 'Use either -CertificateThumbprint or -CertificatePath, not both.'
    }

    if (-not $OutputPath) {
        $OutputPath = [System.IO.Path]::Combine([string](Get-Location), 'quorum-out')
    }
    if (-not $RulesPath) {
        $RulesPath = Join-QuorumPath $script:QuorumModuleRoot 'rules'
    }
    $rules = Import-QuorumRule -Path $RulesPath
    $mode = 'Live'
    $tenantLabel = $TenantId
    $asOfOverride = $AsOf
    $asOf = [datetime]::UtcNow
    $collectors = @()

    if ($Demo) {
        $mode = 'Demo'
        $tenantLabel = 'Quorum demo (synthetic)'
        if (-not $DemoDataPath) {
            $DemoDataPath = Join-QuorumPath $script:QuorumModuleRoot 'data' 'demo-inventory.json'
        }
        if (-not (Test-Path -LiteralPath $DemoDataPath)) { throw "Demo inventory not found: $DemoDataPath" }
        $inventory = [System.IO.File]::ReadAllText($DemoDataPath) | ConvertFrom-Json
        $parsedAsOf = ConvertTo-QuorumDate $inventory.asOf
        if ($null -eq $parsedAsOf) { throw 'Demo inventory is missing a valid asOf timestamp.' }
        $asOf = $parsedAsOf
        if ($inventory.tenantLabel) { $tenantLabel = [string]$inventory.tenantLabel }
        $intune = @(ConvertTo-QuorumIntuneRecord -Item $inventory.intune)
        $entra = @(ConvertTo-QuorumEntraRecord -Item $inventory.entra)
        $defender = @(ConvertTo-QuorumDefenderRecord -Item $inventory.defender)
        $collectors = @(
            [pscustomobject]@{ Source = 'Intune'; Records = $intune; Error = $null }
            [pscustomobject]@{ Source = 'Entra'; Records = $entra; Error = $null }
            [pscustomobject]@{ Source = 'Defender'; Records = $defender; Error = $null }
        )
    }
    elseif ($import) {
        $mode = 'Import'
        $tenantLabel = 'Offline import'
        $intuneItems = $null; $entraItems = $null; $defenderItems = $null
        $haveIntune = $false; $haveEntra = $false; $haveDefender = $false
        if ($InventoryPath) {
            $inventory = Read-QuorumExportFile -Path $InventoryPath
            if (($inventory -is [System.Array]) -or (($null -eq $inventory.PSObject.Properties['intune']) -and ($null -eq $inventory.PSObject.Properties['entra']) -and ($null -eq $inventory.PSObject.Properties['defender']))) {
                throw "Inventory file $InventoryPath needs intune, entra, or defender arrays."
            }
            if ($inventory.PSObject.Properties['asOf'] -and $inventory.asOf) {
                $parsedAsOf = ConvertTo-QuorumDate $inventory.asOf
                if ($null -eq $parsedAsOf) { throw "Inventory file $InventoryPath has an invalid asOf timestamp." }
                $asOf = $parsedAsOf
            }
            if ($inventory.PSObject.Properties['tenantLabel'] -and $inventory.tenantLabel) { $tenantLabel = [string]$inventory.tenantLabel }
            if ($inventory.PSObject.Properties['intune']) { $haveIntune = $true; $intuneItems = $inventory.intune }
            if ($inventory.PSObject.Properties['entra']) { $haveEntra = $true; $entraItems = $inventory.entra }
            if ($inventory.PSObject.Properties['defender']) { $haveDefender = $true; $defenderItems = $inventory.defender }
        }
        else {
            if ($IntunePath) { $haveIntune = $true; $intuneItems = Get-QuorumExportItems (Read-QuorumExportFile -Path $IntunePath) $IntunePath }
            if ($EntraPath) { $haveEntra = $true; $entraItems = Get-QuorumExportItems (Read-QuorumExportFile -Path $EntraPath) $EntraPath }
            if ($DefenderPath) { $haveDefender = $true; $defenderItems = Get-QuorumExportItems (Read-QuorumExportFile -Path $DefenderPath) $DefenderPath }
        }
        $notCollected = 'Not provided in this offline import.'
        $collectors = @(
            [pscustomobject]@{ Source = 'Intune'; Records = $(if ($haveIntune) { @(ConvertTo-QuorumIntuneRecord -Item $intuneItems) } else { @() }); Error = $(if ($haveIntune) { $null } else { $notCollected }) }
            [pscustomobject]@{ Source = 'Entra'; Records = $(if ($haveEntra) { @(ConvertTo-QuorumEntraRecord -Item $entraItems) } else { @() }); Error = $(if ($haveEntra) { $null } else { $notCollected }) }
            [pscustomobject]@{ Source = 'Defender'; Records = $(if ($haveDefender) { @(ConvertTo-QuorumDefenderRecord -Item $defenderItems) } else { @() }); Error = $(if ($haveDefender) { $null } else { $notCollected }) }
        )
    }
    else {
        $token = Get-QuorumAccessToken -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -AuthorityHost $AuthorityHost
        $graphToken = [string]$token.Graph
        $defenderToken = [string]$token.Defender
        $graphUri = $GraphBaseUri
        $defenderUri = $DefenderBaseUri
        $collectors = @(
            (Invoke-QuorumCollector -Name 'Intune' -Action { Get-QuorumIntuneDevice -AccessToken $graphToken -BaseUri $graphUri }.GetNewClosure())
            (Invoke-QuorumCollector -Name 'Entra' -Action { Get-QuorumEntraDevice -AccessToken $graphToken -BaseUri $graphUri }.GetNewClosure())
            (Invoke-QuorumCollector -Name 'Defender' -Action { Get-QuorumDefenderMachine -AccessToken $defenderToken -BaseUri $defenderUri }.GetNewClosure())
        )
    }

    if ($null -ne $asOfOverride) { $asOf = ([datetime]$asOfOverride).ToUniversalTime() }

    $records = New-Object System.Collections.Generic.List[object]
    $failed = 0
    foreach ($collector in $collectors) {
        if ($collector.Error) { $failed++ }
        foreach ($record in @($collector.Records)) {
            if ($null -ne $record) { $records.Add($record) }
        }
    }

    $devices = Merge-QuorumDevice -Record $records.ToArray()
    $findings = Invoke-QuorumRule -Device $devices -Rule $rules -AsOf $asOf
    $model = New-QuorumViewModel -Device $devices -Finding $findings -Rule $rules -Collector $collectors -AsOf $asOf -Mode $mode -TenantLabel $tenantLabel -Redacted $Redact.IsPresent
    $map = $null
    if ($Redact) {
        $map = Protect-QuorumReport -Model $model
    }
    $written = New-QuorumReport -Model $model -OutputPath $OutputPath -RedactionMap $map
    $highest = $null
    foreach ($finding in @($model['findings'])) {
        $sev = [string]$finding['severity']
        if ($null -eq $highest -or (Get-QuorumSeverityRank $sev) -lt (Get-QuorumSeverityRank $highest)) { $highest = $sev }
    }

    if ($mode -eq 'Live' -and $failed -eq $collectors.Count) {
        throw "Every collector failed. A partial report was still written to $($written.HtmlPath)."
    }

    Write-Host ("Quorum wrote {0} findings for {1} devices." -f $model['meta']['findingCount'], $model['meta']['deviceCount'])
    Write-Host ("HTML report: {0}" -f $written.HtmlPath)

    $result = [pscustomobject]@{
        PSTypeName       = 'Quorum.Result'
        Mode             = $mode
        DeviceCount      = [int]$model['meta']['deviceCount']
        FindingCount     = [int]$model['meta']['findingCount']
        OutputPath       = $OutputPath
        HtmlPath         = $written.HtmlPath
        MarkdownPath     = $written.MarkdownPath
        CsvPath          = $written.CsvPath
        JsonPath         = $written.JsonPath
        RedactionMapPath = $written.RedactionMapPath
        CollectorStatus  = @($model['collectors'])
        Findings         = @($model['findings'])
        Devices          = @($model['devices'])
        HighestSeverity  = $highest
    }
    if ($FailOnSeverity) {
        $limit = Get-QuorumSeverityRank $FailOnSeverity
        $over = @($model['findings'] | Where-Object { (Get-QuorumSeverityRank ([string]$_['severity'])) -le $limit })
        if ($over.Count -gt 0) {
            throw ("Quorum found {0} finding(s) at severity {1} or worse. The report was written to {2}." -f $over.Count, $FailOnSeverity, $written.HtmlPath)
        }
    }
    return $result
}

function Read-QuorumExportFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Export file not found: $Path" }
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath)
    try { $parsed = ConvertFrom-Json -InputObject $text }
    catch { throw "Export file $Path is not valid JSON: $(Get-QuorumErrorMessage $_)" }
    # Keep one-element and empty arrays as arrays on every PowerShell version.
    if ($text.TrimStart().StartsWith('[')) { return ,([object[]]@($parsed)) }
    return $parsed
}

function Get-QuorumExportItems {
    param($Document, [string]$Path)
    if ($null -eq $Document) { return @() }
    if ($Document -is [System.Array]) { return ,$Document }
    if ($Document.PSObject.Properties['value']) { return ,@($Document.value) }
    throw "Export file $Path must be a JSON array or an API response with a value array."
}

function Invoke-QuorumCollector {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    try {
        $records = @(& $Action)
        return [pscustomobject]@{ Source = $Name; Records = $records; Error = $null }
    }
    catch {
        $message = Get-QuorumErrorMessage $_
        Write-Warning ("{0} collector failed: {1}" -f $Name, $message)
        return [pscustomobject]@{ Source = $Name; Records = @(); Error = $message }
    }
}