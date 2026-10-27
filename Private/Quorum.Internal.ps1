Set-StrictMode -Version 1.0

function Join-QuorumPath {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Child,
        [string]$Extra
    )
    if ($Extra) {
        return [System.IO.Path]::Combine($Base, $Child, $Extra)
    }
    return [System.IO.Path]::Combine($Base, $Child)
}

function Write-QuorumTextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Get-QuorumProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object -or [string]::IsNullOrEmpty($Name)) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    $value = $prop.Value
    if ($null -eq $value) { return $null }
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value
}

function ConvertTo-QuorumToken {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Trim()
    if ($text -eq '') { return $null }
    return $text.ToLowerInvariant()
}

function ConvertTo-QuorumNullableBool {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = ([string]$Value).Trim()
    if ($text -eq 'true' -or $text -eq 'True' -or $text -eq 'TRUE') { return $true }
    if ($text -eq 'false' -or $text -eq 'False' -or $text -eq 'FALSE') { return $false }
    return $null
}

function ConvertTo-QuorumDeviceId {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -eq '' -or $text -eq '00000000-0000-0000-0000-000000000000') { return $null }
    if ($text -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $null }
    return $text
}

function ConvertTo-QuorumDate {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [datetime]) {
        return [datetime]::SpecifyKind($Value.ToUniversalTime(), [DateTimeKind]::Utc)
    }
    $text = ([string]$Value).Trim()
    if ($text -eq '') { return $null }
    $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $ok = [datetime]::TryParse(
        $text,
        [System.Globalization.CultureInfo]::InvariantCulture,
        $styles,
        [ref]$parsed
    )
    if (-not $ok) { return $null }
    return [datetime]::SpecifyKind($parsed.ToUniversalTime(), [DateTimeKind]::Utc)
}

function ConvertTo-QuorumTimestamp {
    param($Value)
    $date = ConvertTo-QuorumDate $Value
    if ($null -eq $date) { return $null }
    return $date.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) + ' UTC'
}

function Get-QuorumAgeDays {
    param($When, [datetime]$AsOf)
    $date = ConvertTo-QuorumDate $When
    if ($null -eq $date) { return $null }
    $origin = $AsOf
    if ($origin.Kind -eq [DateTimeKind]::Unspecified) {
        $origin = [datetime]::SpecifyKind($origin, [DateTimeKind]::Utc)
    }
    $span = $origin.ToUniversalTime() - $date.ToUniversalTime()
    if ($span.TotalDays -lt 0) { return 0 }
    return [int][math]::Floor($span.TotalDays)
}

function ConvertTo-QuorumAgeLabel {
    param($Days)
    if ($null -eq $Days -or $Days -eq '') { return $null }
    $n = [int]$Days
    if ($n -eq 0) { return 'today' }
    if ($n -eq 1) { return '1 day ago' }
    return "$n days ago"
}

function ConvertTo-QuorumOsBuild {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int64] -or $Value -is [double] -or $Value -is [decimal]) {
        $number = [int64]$Value
        if ($number -le 0) { return $null }
        return [string]$number
    }
    $text = ([string]$Value).Trim()
    if ($text -eq '') { return $null }
    if ($text -match '^\d+$') { return $text }
    if ($text -match '\d+\.\d+\.(\d+)') { return $Matches[1] }
    return $null
}

function Get-QuorumHostnameParts {
    param($Value)
    if ($null -eq $Value) { return $null }
    $original = ([string]$Value).Trim().TrimEnd('.')
    if ($original -eq '') { return $null }
    $raw = $original.ToLowerInvariant()
    $key = $raw
    $isIpv4 = $raw -match '^\d{1,3}(\.\d{1,3}){3}$'
    if (-not $isIpv4 -and $raw.Contains('.')) {
        $key = $raw.Split('.')[0]
    }
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }
    return [pscustomobject]@{
        Original = $original
        Raw      = $raw
        Key      = $key
    }
}

function Format-QuorumBool {
    param($Value)
    $bool = ConvertTo-QuorumNullableBool $Value
    if ($null -eq $bool) { return $null }
    if ($bool) { return 'Yes' }
    return 'No'
}

function New-QuorumAttribute {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        $Value,
        [Parameter(Mandatory = $true)][string]$Key
    )
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return [ordered]@{
        label    = $Label
        value    = $text
        key      = $Key
        conflict = $false
    }
}

function Add-QuorumAttribute {
    param($List, $Label, $Value, $Key)
    $attr = New-QuorumAttribute -Label $Label -Value $Value -Key $Key
    if ($null -ne $attr) { $List.Add($attr) }
}

function Test-QuorumNumber {
    param($Value)
    if ($null -eq $Value) { return $false }
    return $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [decimal] -or $Value -is [single] -or $Value -is [double]
}

function Get-QuorumStableId {
    param([Parameter(Mandatory = $true)][string]$Material)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Material))
    }
    finally {
        $sha.Dispose()
    }
    $hex = -join ($bytes[0..7] | ForEach-Object { $_.ToString('x2') })
    return "q-$hex"
}

function ConvertTo-QuorumJsonString {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -eq 34) { [void]$sb.Append('\"'); continue }
        if ($code -eq 92) { [void]$sb.Append('\\'); continue }
        if ($code -eq 8) { [void]$sb.Append('\b'); continue }
        if ($code -eq 9) { [void]$sb.Append('\t'); continue }
        if ($code -eq 10) { [void]$sb.Append('\n'); continue }
        if ($code -eq 12) { [void]$sb.Append('\f'); continue }
        if ($code -eq 13) { [void]$sb.Append('\r'); continue }
        if ($code -lt 32 -or $code -eq 60 -or $code -eq 8232 -or $code -eq 8233) {
            [void]$sb.AppendFormat('\u{0:x4}', $code)
            continue
        }
        [void]$sb.Append($ch)
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-QuorumJson {
    param($Value, [int]$Depth = 0)
    $pad = '  ' * $Depth
    $padIn = '  ' * ($Depth + 1)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [string]) { return (ConvertTo-QuorumJsonString $Value) }
    if (Test-QuorumNumber $Value) {
        if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
            return ([double]$Value).ToString('G15', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        return ([int64]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetime]) {
        $stamp = $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        return (ConvertTo-QuorumJsonString $stamp)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($key in @($Value.Keys)) {
            $encoded = (ConvertTo-QuorumJsonString ([string]$key)) + ': ' + (ConvertTo-QuorumJson $Value[$key] ($Depth + 1))
            $parts.Add($padIn + $encoded)
        }
        if ($parts.Count -eq 0) { return '{}' }
        return "{`n" + ($parts -join ",`n") + "`n" + $pad + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($item in $Value) {
            $parts.Add($padIn + (ConvertTo-QuorumJson $item ($Depth + 1)))
        }
        if ($parts.Count -eq 0) { return '[]' }
        return "[`n" + ($parts -join ",`n") + "`n" + $pad + ']'
    }
    $map = [ordered]@{}
    foreach ($prop in @($Value.PSObject.Properties)) {
        $map[$prop.Name] = $prop.Value
    }
    return (ConvertTo-QuorumJson $map $Depth)
}

function Get-QuorumErrorMessage {
    param($ErrorRecord)
    $msg = [string]$ErrorRecord.Exception.Message
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $msg = [string]$ErrorRecord.ErrorDetails.Message
    }
    $msg = [regex]::Replace($msg, 'Bearer\s+\S+', 'Bearer [redacted]')
    if ($msg.Length -gt 600) { $msg = $msg.Substring(0, 600) }
    return $msg
}

function Get-QuorumPermission {
    # Read scopes only. Do not add write, readwrite, or broader directory scopes.
    [pscustomobject]@{
        GraphDelegatedScopes      = @(
            'https://graph.microsoft.com/Device.Read.All'
            'https://graph.microsoft.com/DeviceManagementManagedDevices.Read.All'
        )
        GraphApplicationScope     = 'https://graph.microsoft.com/.default'
        DefenderDelegatedScopes   = @(
            'https://api.securitycenter.microsoft.com/Machine.Read'
        )
        DefenderApplicationScope  = 'https://api.securitycenter.microsoft.com/.default'
    }
}

function Get-QuorumVersion {
    $manifestPath = Join-QuorumPath $script:QuorumModuleRoot 'Quorum.psd1'
    $data = Import-PowerShellDataFile -LiteralPath $manifestPath
    return [string]$data.ModuleVersion
}