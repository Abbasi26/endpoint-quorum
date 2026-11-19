Set-StrictMode -Version 1.0

# Windows Server SKU numbers and assignment-filter names, from Microsoft Learn:
# https://learn.microsoft.com/en-us/intune/fundamentals/filters/ref-device-properties
# https://learn.microsoft.com/en-us/intune/solutions/end-to-end-guides/windows-server-endpoints-get-started
# skuNumber is also documented on Graph beta managedDevice (not listed on the v1.0 page):
# https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice?view=graph-rest-beta
# GetProductInfo product-type values: https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getproductinfo
#
# ServerRdsh (175) is Windows 10/11 Enterprise multi-session, not Windows Server.
$script:QuorumWindowsServerSkuNumber = @{
    7   = 'ServerStandard'
    8   = 'ServerDatacenter'
    79  = 'ServerStandardEval'
    80  = 'ServerDatacenterEval'
    407 = 'ServerTurbine'
}
$script:QuorumWindowsServerSkuName = @{
    'serverstandard'        = 7
    'serverdatacenter'      = 8
    'serverstandardeval'    = 79
    'serverdatacentereval'  = 80
    'serverturbine'         = 407
}

function Get-QuorumDeviceClass {
    param(
        $Record,
        $Device
    )

    $records = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Device) {
        foreach ($group in @($Device.BySource.Intune, $Device.BySource.Entra, $Device.BySource.Defender)) {
            $latest = Select-QuorumLatestRecord @($group)
            if ($null -ne $latest) { $records.Add($latest) }
        }
    }
    elseif ($null -ne $Record) {
        foreach ($one in @($Record)) {
            if ($null -ne $one) { $records.Add($one) }
        }
    }

    $sawWindows = $false
    foreach ($one in $records) {
        $class = Get-QuorumRecordDeviceClass $one
        if ($class -eq 'windows-server') { return 'windows-server' }
        if ($class -eq 'windows') { $sawWindows = $true }
    }
    if ($sawWindows) { return 'windows' }

    foreach ($one in $records) {
        $class = Get-QuorumRecordDeviceClass $one
        if ($class -and $class -ne 'unknown') { return $class }
    }
    return 'unknown'
}

function Get-QuorumRecordDeviceClass {
    param($Record)
    if ($null -eq $Record) { return 'unknown' }

    if (Test-QuorumWindowsServerSignal $Record) { return 'windows-server' }

    $labels = @(
        $Record.OperatingSystem
        $Record.OsName
        (Get-QuorumAttributeValue $Record 'os')
        (Get-QuorumAttributeValue $Record 'platform')
    )
    foreach ($label in $labels) {
        $class = ConvertTo-QuorumOsDeviceClass $label
        if ($class -eq 'windows-server') { return 'windows-server' }
    }
    foreach ($label in $labels) {
        $class = ConvertTo-QuorumOsDeviceClass $label
        if ($class -eq 'windows') { return 'windows' }
    }
    foreach ($label in $labels) {
        $class = ConvertTo-QuorumOsDeviceClass $label
        if ($class -and $class -ne 'unknown') { return $class }
    }
    return 'unknown'
}

function Test-QuorumWindowsServerSignal {
    param($Record)
    $skuNumber = Get-QuorumSkuNumberValue $Record
    if ($null -ne $skuNumber -and $script:QuorumWindowsServerSkuNumber.ContainsKey([int]$skuNumber)) {
        return $true
    }

    foreach ($name in @(
            (Get-QuorumAttributeValue $Record 'osSku')
            (Get-QuorumAttributeValue $Record 'operatingSystemSKU')
        )) {
        if (Test-QuorumWindowsServerSkuName $name) { return $true }
    }

    foreach ($label in @(
            $Record.OperatingSystem
            $Record.OsName
            (Get-QuorumAttributeValue $Record 'os')
            (Get-QuorumAttributeValue $Record 'platform')
        )) {
        if (Test-QuorumWindowsServerLabel $label) { return $true }
    }
    return $false
}

function Get-QuorumSkuNumberValue {
    param($Record)
    foreach ($raw in @(
            (Get-QuorumAttributeValue $Record 'skuNumber')
            (Get-QuorumNoteProperty $Record 'SkuNumber')
        )) {
        $number = ConvertTo-QuorumSkuNumber $raw
        if ($null -ne $number) { return $number }
    }
    return $null
}

function ConvertTo-QuorumSkuNumber {
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        return $null
    }
    $text = [string]$Value
    $parsed = 0
    if ([int]::TryParse($text, [ref]$parsed)) { return $parsed }
    return $null
}

function Test-QuorumWindowsServerSkuName {
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$Value))) {
        return $false
    }
    $key = ([string]$Value).Trim().ToLowerInvariant()
    return $script:QuorumWindowsServerSkuName.ContainsKey($key)
}

function Test-QuorumWindowsServerLabel {
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$Value))) {
        return $false
    }
    $text = ([string]$Value).Trim()
    if ($text.Equals('Windows Server', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    # Defender machine osPlatform values are not enumerated on the official
    # machine resource page. Compact values such as WindowsServer2022 appear in
    # API examples; accept a WindowsServer prefix, but not client platforms.
    $compact = $text -replace '\s', ''
    if ($compact -match '^(?i)WindowsServer([0-9].*)?$') {
        return $true
    }
    return $false
}

function ConvertTo-QuorumOsDeviceClass {
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$Value))) {
        return 'unknown'
    }
    $text = ([string]$Value).Trim()
    if (Test-QuorumWindowsServerLabel $text) { return 'windows-server' }

    $compact = ($text -replace '\s', '').ToLowerInvariant()
    if ($compact.StartsWith('windows')) { return 'windows' }

    if ($compact.StartsWith('macos') -or $compact -eq 'mac' -or $compact.StartsWith('osx')) { return 'macos' }
    if ($compact.StartsWith('ios') -or $compact.StartsWith('ipados') -or $compact -eq 'iphone' -or $compact -eq 'ipad') { return 'ios' }
    if ($compact.StartsWith('android')) { return 'android' }
    if ($compact.StartsWith('linux') -or $compact -eq 'ubuntu' -or $compact -eq 'rhel') { return 'linux' }
    return 'unknown'
}

function Get-QuorumAttributeValue {
    param($Record, [string]$Key)
    if ($null -eq $Record) { return $null }
    foreach ($attr in @($Record.Attributes)) {
        if ($null -eq $attr) { continue }
        $attrKey = $null
        if ($attr -is [hashtable] -or $attr -is [System.Collections.Specialized.OrderedDictionary]) {
            $attrKey = [string]$attr['key']
            if ($attrKey -eq $Key) { return $attr['value'] }
        }
        else {
            try { $attrKey = [string]$attr.key } catch { $attrKey = $null }
            if ($attrKey -eq $Key) {
                try { return $attr.value } catch { return $null }
            }
        }
    }
    return $null
}

function Get-QuorumNoteProperty {
    param($Record, [string]$Name)
    if ($null -eq $Record) { return $null }
    $prop = $Record.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}
