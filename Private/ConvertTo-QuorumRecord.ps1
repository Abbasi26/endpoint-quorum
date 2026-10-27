Set-StrictMode -Version 1.0

function ConvertTo-QuorumBlankNull {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
    return $Value
}

function New-QuorumRecord {
    param(
        [string]$Source,
        $SourceObjectId,
        $DeviceId,
        $HostnameOriginal,
        $HostnameRaw,
        $HostnameKey,
        $UserPrincipalName,
        $UserDisplayName,
        $IpAddress,
        $OsBuild,
        $OsVersion,
        $OsName,
        $ObservedAt,
        $ComplianceState,
        $AccountEnabled,
        $IsCompliant,
        $IsManaged,
        $TrustType,
        $OperatingSystem,
        $HealthStatus,
        $RiskScore,
        $ExposureLevel,
        $OnboardingStatus,
        $Attributes
    )
    if ($null -eq $Attributes) { $Attributes = @() }
    [pscustomobject]@{
        Source              = [string]$Source
        SourceObjectId      = ConvertTo-QuorumBlankNull $SourceObjectId
        DeviceId            = ConvertTo-QuorumBlankNull $DeviceId
        HostnameOriginal    = ConvertTo-QuorumBlankNull $HostnameOriginal
        HostnameRaw         = ConvertTo-QuorumBlankNull $HostnameRaw
        HostnameKey         = ConvertTo-QuorumBlankNull $HostnameKey
        UserPrincipalName   = ConvertTo-QuorumBlankNull $UserPrincipalName
        UserDisplayName     = ConvertTo-QuorumBlankNull $UserDisplayName
        IpAddress           = ConvertTo-QuorumBlankNull $IpAddress
        OsBuild             = ConvertTo-QuorumBlankNull $OsBuild
        OsVersion           = ConvertTo-QuorumBlankNull $OsVersion
        OsName              = ConvertTo-QuorumBlankNull $OsName
        ObservedAt          = $ObservedAt
        ComplianceState     = ConvertTo-QuorumBlankNull $ComplianceState
        AccountEnabled      = $AccountEnabled
        IsCompliant         = $IsCompliant
        IsManaged           = $IsManaged
        TrustType           = ConvertTo-QuorumBlankNull $TrustType
        OperatingSystem     = ConvertTo-QuorumBlankNull $OperatingSystem
        HealthStatus        = ConvertTo-QuorumBlankNull $HealthStatus
        RiskScore           = ConvertTo-QuorumBlankNull $RiskScore
        ExposureLevel       = ConvertTo-QuorumBlankNull $ExposureLevel
        OnboardingStatus    = ConvertTo-QuorumBlankNull $OnboardingStatus
        Attributes          = @($Attributes)
    }
}

function ConvertTo-QuorumIntuneRecord {
    param($Item)
    foreach ($one in (ConvertTo-QuorumItemList $Item)) {
        $name = Get-QuorumHostnameParts (Get-QuorumProperty $one 'deviceName')
        $attrs = New-Object System.Collections.Generic.List[object]
        $compliance = ConvertTo-QuorumToken (Get-QuorumProperty $one 'complianceState')
        $osVersion = Get-QuorumProperty $one 'osVersion'
        $build = ConvertTo-QuorumOsBuild $osVersion
        $sync = ConvertTo-QuorumDate (Get-QuorumProperty $one 'lastSyncDateTime')
        $upn = Get-QuorumProperty $one 'userPrincipalName'
        $user = Get-QuorumProperty $one 'userDisplayName'
        $deviceId = ConvertTo-QuorumDeviceId (Get-QuorumProperty $one 'azureADDeviceId')
        if ($null -ne $name) { Add-QuorumAttribute $attrs 'Device name' $name.Original 'hostname' }
        Add-QuorumAttribute $attrs 'Azure AD device id' $deviceId 'deviceId'
        Add-QuorumAttribute $attrs 'User principal name' $upn 'upn'
        Add-QuorumAttribute $attrs 'User' $user 'user'
        Add-QuorumAttribute $attrs 'Compliance' $compliance 'compliance'
        Add-QuorumAttribute $attrs 'Operating system' (Get-QuorumProperty $one 'operatingSystem') 'os'
        Add-QuorumAttribute $attrs 'OS version' $osVersion 'osVersion'
        Add-QuorumAttribute $attrs 'OS build' $build 'osBuild'
        if ($null -ne $sync) { Add-QuorumAttribute $attrs 'Last sync' (ConvertTo-QuorumTimestamp $sync) 'lastSync' }
        Add-QuorumAttribute $attrs 'Owner' (ConvertTo-QuorumToken (Get-QuorumProperty $one 'managedDeviceOwnerType')) 'owner'
        Add-QuorumAttribute $attrs 'Enrollment' (Get-QuorumProperty $one 'deviceEnrollmentType') 'enrollment'
        Add-QuorumAttribute $attrs 'Encrypted' (Format-QuorumBool (Get-QuorumProperty $one 'isEncrypted')) 'encrypted'
        Add-QuorumAttribute $attrs 'Serial number' (Get-QuorumProperty $one 'serialNumber') 'serial'
        Add-QuorumAttribute $attrs 'Model' (Get-QuorumProperty $one 'model') 'model'
        Add-QuorumAttribute $attrs 'Manufacturer' (Get-QuorumProperty $one 'manufacturer') 'manufacturer'
        New-QuorumRecord -Source 'Intune' `
            -SourceObjectId ([string](Get-QuorumProperty $one 'id')) `
            -DeviceId $deviceId `
            -HostnameOriginal $(if ($name) { $name.Original } else { $null }) `
            -HostnameRaw $(if ($name) { $name.Raw } else { $null }) `
            -HostnameKey $(if ($name) { $name.Key } else { $null }) `
            -UserPrincipalName $(if ($upn) { [string]$upn } else { $null }) `
            -UserDisplayName $(if ($user) { [string]$user } else { $null }) `
            -OsBuild $build `
            -OsVersion $(if ($osVersion) { [string]$osVersion } else { $null }) `
            -OsName $(if ((Get-QuorumProperty $one 'operatingSystem')) { [string](Get-QuorumProperty $one 'operatingSystem') } else { $null }) `
            -ObservedAt $sync `
            -ComplianceState $compliance `
            -Attributes $attrs.ToArray()
    }
}

function ConvertTo-QuorumEntraRecord {
    param($Item)
    foreach ($one in (ConvertTo-QuorumItemList $Item)) {
        $name = Get-QuorumHostnameParts (Get-QuorumProperty $one 'displayName')
        $attrs = New-Object System.Collections.Generic.List[object]
        $deviceId = ConvertTo-QuorumDeviceId (Get-QuorumProperty $one 'deviceId')
        $osVersion = Get-QuorumProperty $one 'operatingSystemVersion'
        $build = ConvertTo-QuorumOsBuild $osVersion
        $enabled = ConvertTo-QuorumNullableBool (Get-QuorumProperty $one 'accountEnabled')
        $compliant = ConvertTo-QuorumNullableBool (Get-QuorumProperty $one 'isCompliant')
        $managed = ConvertTo-QuorumNullableBool (Get-QuorumProperty $one 'isManaged')
        $signIn = ConvertTo-QuorumDate (Get-QuorumProperty $one 'approximateLastSignInDateTime')
        $registered = ConvertTo-QuorumDate (Get-QuorumProperty $one 'registrationDateTime')
        $os = Get-QuorumProperty $one 'operatingSystem'
        $trust = ConvertTo-QuorumToken (Get-QuorumProperty $one 'trustType')
        if ($null -ne $name) { Add-QuorumAttribute $attrs 'Display name' $name.Original 'hostname' }
        Add-QuorumAttribute $attrs 'Device id' $deviceId 'deviceId'
        Add-QuorumAttribute $attrs 'Enabled' (Format-QuorumBool $enabled) 'enabled'
        Add-QuorumAttribute $attrs 'Compliant' (Format-QuorumBool $compliant) 'isCompliant'
        Add-QuorumAttribute $attrs 'Operating system' $os 'os'
        Add-QuorumAttribute $attrs 'OS version' $osVersion 'osVersion'
        Add-QuorumAttribute $attrs 'OS build' $build 'osBuild'
        Add-QuorumAttribute $attrs 'Trust type' $trust 'trust'
        Add-QuorumAttribute $attrs 'Managed' (Format-QuorumBool $managed) 'managed'
        if ($null -ne $signIn) { Add-QuorumAttribute $attrs 'Last sign-in' (ConvertTo-QuorumTimestamp $signIn) 'lastSignIn' }
        if ($null -ne $registered) { Add-QuorumAttribute $attrs 'Registered' (ConvertTo-QuorumTimestamp $registered) 'registered' }
        Add-QuorumAttribute $attrs 'Ownership' (Get-QuorumProperty $one 'deviceOwnership') 'ownership'
        Add-QuorumAttribute $attrs 'Profile' (Get-QuorumProperty $one 'profileType') 'profile'
        New-QuorumRecord -Source 'Entra' `
            -SourceObjectId ([string](Get-QuorumProperty $one 'id')) `
            -DeviceId $deviceId `
            -HostnameOriginal $(if ($name) { $name.Original } else { $null }) `
            -HostnameRaw $(if ($name) { $name.Raw } else { $null }) `
            -HostnameKey $(if ($name) { $name.Key } else { $null }) `
            -OsBuild $build `
            -OsVersion $(if ($osVersion) { [string]$osVersion } else { $null }) `
            -OsName $(if ($os) { [string]$os } else { $null }) `
            -ObservedAt $signIn `
            -AccountEnabled $enabled `
            -IsCompliant $compliant `
            -IsManaged $managed `
            -TrustType $trust `
            -OperatingSystem $(if ($os) { ([string]$os).ToLowerInvariant() } else { $null }) `
            -Attributes $attrs.ToArray()
    }
}

function ConvertTo-QuorumDefenderRecord {
    param($Item)
    foreach ($one in (ConvertTo-QuorumItemList $Item)) {
        $dns = Get-QuorumProperty $one 'computerDnsName'
        $name = Get-QuorumHostnameParts $dns
        $attrs = New-Object System.Collections.Generic.List[object]
        $deviceId = ConvertTo-QuorumDeviceId (Get-QuorumProperty $one 'aadDeviceId')
        $osVersion = Get-QuorumProperty $one 'osVersion'
        $build = ConvertTo-QuorumOsBuild (Get-QuorumProperty $one 'osBuild')
        if (-not $build) { $build = ConvertTo-QuorumOsBuild $osVersion }
        $seen = ConvertTo-QuorumDate (Get-QuorumProperty $one 'lastSeen')
        $health = ConvertTo-QuorumToken (Get-QuorumProperty $one 'healthStatus')
        $risk = ConvertTo-QuorumToken (Get-QuorumProperty $one 'riskScore')
        $exposure = ConvertTo-QuorumToken (Get-QuorumProperty $one 'exposureLevel')
        $onboarding = ConvertTo-QuorumToken (Get-QuorumProperty $one 'onboardingStatus')
        $ip = Get-QuorumProperty $one 'lastIpAddress'
        if ($null -ne $name) { Add-QuorumAttribute $attrs 'DNS name' $name.Original 'hostname' }
        Add-QuorumAttribute $attrs 'Entra device id' $deviceId 'deviceId'
        Add-QuorumAttribute $attrs 'Onboarding' $onboarding 'onboarding'
        Add-QuorumAttribute $attrs 'Health' $health 'health'
        Add-QuorumAttribute $attrs 'Risk' $risk 'risk'
        Add-QuorumAttribute $attrs 'Exposure' $exposure 'exposure'
        Add-QuorumAttribute $attrs 'Platform' (Get-QuorumProperty $one 'osPlatform') 'platform'
        Add-QuorumAttribute $attrs 'OS version' $osVersion 'osVersion'
        Add-QuorumAttribute $attrs 'OS build' $build 'osBuild'
        if ($null -ne $seen) { Add-QuorumAttribute $attrs 'Last seen' (ConvertTo-QuorumTimestamp $seen) 'lastSeen' }
        Add-QuorumAttribute $attrs 'Last IP' $ip 'ip'
        New-QuorumRecord -Source 'Defender' `
            -SourceObjectId ([string](Get-QuorumProperty $one 'id')) `
            -DeviceId $deviceId `
            -HostnameOriginal $(if ($name) { $name.Original } else { $null }) `
            -HostnameRaw $(if ($name) { $name.Raw } else { $null }) `
            -HostnameKey $(if ($name) { $name.Key } else { $null }) `
            -IpAddress $(if ($ip) { [string]$ip } else { $null }) `
            -OsBuild $build `
            -OsVersion $(if ($osVersion) { [string]$osVersion } else { $null }) `
            -OsName $(if ((Get-QuorumProperty $one 'osPlatform')) { [string](Get-QuorumProperty $one 'osPlatform') } else { $null }) `
            -ObservedAt $seen `
            -HealthStatus $health `
            -RiskScore $risk `
            -ExposureLevel $exposure `
            -OnboardingStatus $onboarding `
            -Attributes $attrs.ToArray()
    }
}

function ConvertTo-QuorumItemList {
    param($Item)
    if ($null -eq $Item) { return }
    foreach ($one in @($Item)) {
        if ($null -ne $one) { Write-Output $one }
    }
}