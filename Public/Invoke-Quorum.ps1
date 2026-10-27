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
        [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',
        [string]$DefenderBaseUri = 'https://api.security.microsoft.com',
        [string]$AuthorityHost = 'https://login.microsoftonline.com'
    )

    $ErrorActionPreference = 'Stop'
    if ($Demo -and $TenantId) { throw '-Demo cannot be combined with -TenantId.' }
    if (-not $Demo -and -not $TenantId) {
        throw 'Specify -Demo for the offline sample, or -TenantId and -ClientId for a live read-only collection.'
    }
    if (-not $Demo -and -not $ClientId) { throw '-ClientId is required for a live collection.' }
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

    if (-not $Demo -and $failed -eq $collectors.Count) {
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
    }
    return $result
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