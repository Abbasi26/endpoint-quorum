Set-StrictMode -Version 1.0

function Protect-QuorumReport {
    param($Model)
    $bag = @{}
    $texts = New-Object System.Collections.Generic.List[string]
    Add-QuorumSecretText $Model $texts
    foreach ($text in $texts) {
        $email = [regex]::Matches($text, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
        foreach ($match in $email) { Add-QuorumSecret $bag $match.Value 'user' }
        $ip = [regex]::Matches($text, '(?<![0-9.])(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(?![0-9.])')
        foreach ($match in $ip) { Add-QuorumSecret $bag $match.Value 'ip' }
    }
    Add-QuorumIdentitySecret $Model $bag

    $salt = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($salt) } finally { $rng.Dispose() }

    $entries = New-Object System.Collections.Generic.List[object]
    $lookup = @{}
    foreach ($item in @($bag.Values)) {
        $token = New-QuorumPseudonym -Salt $salt -Value $item.Lookup -Kind $item.Kind
        $lookup[$item.Lookup] = $token
        $entries.Add([ordered]@{
            kind     = $item.Kind
            original = $item.Value
            token    = $token
        })
    }
    $ordered = @($entries | Sort-Object { $_.original.Length } -Descending)
    $pattern = ''
    if ($ordered.Count -gt 0) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $ordered) { $parts.Add([regex]::Escape([string]$entry.original)) }
        $pattern = $parts -join '|'
    }
    $plan = @{
        Pattern = $pattern
        Map     = $lookup
    }
    Update-QuorumSecretValue $Model $plan | Out-Null
    return ,$ordered
}

function Protect-QuorumIdentity {
    param($Findings, $Notes)
    $bag = @{}
    foreach ($finding in @($Findings)) {
        Add-QuorumSecret $bag (Get-QuorumProperty $finding 'UserPrincipalName') 'user'
    }
    if ($bag.Count -eq 0) { return ,@() }

    $salt = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($salt) } finally { $rng.Dispose() }

    $entries = New-Object System.Collections.Generic.List[object]
    $lookup = @{}
    foreach ($item in @($bag.Values)) {
        $token = New-QuorumPseudonym -Salt $salt -Value $item.Lookup -Kind $item.Kind
        $lookup[$item.Lookup] = $token
        $entries.Add([ordered]@{
            kind     = $item.Kind
            original = $item.Value
            token    = $token
        })
    }
    $ordered = @($entries | Sort-Object { $_.original.Length } -Descending)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $ordered) { $parts.Add([regex]::Escape([string]$entry.original)) }
    $plan = @{
        Pattern = ($parts -join '|')
        Map     = $lookup
    }
    foreach ($finding in @($Findings)) {
        Update-QuorumIdentitySecretValue -Finding $finding -Plan $plan | Out-Null
    }
    if ($null -ne $Notes) {
        for ($i = 0; $i -lt $Notes.Count; $i++) {
            $Notes[$i] = Update-QuorumSecretString $Notes[$i] $plan
        }
    }
    return ,$ordered
}

function Update-QuorumIdentitySecretValue {
    param($Finding, $Plan)
    foreach ($prop in @($Finding.PSObject.Properties)) {
        $value = $prop.Value
        if ($value -is [string]) {
            $prop.Value = Update-QuorumSecretString $value $Plan
            continue
        }
        if ($value -is [System.Collections.IList]) {
            for ($i = 0; $i -lt $value.Count; $i++) {
                if ($value[$i] -is [string]) { $value[$i] = Update-QuorumSecretString $value[$i] $Plan }
            }
        }
    }
    return $Finding
}

function Add-QuorumIdentitySecret {
    param($Model, $Bag)
    foreach ($device in @($Model['devices'])) {
        Add-QuorumSecret $Bag $device['hostname'] 'host'
        foreach ($sourceName in @('intune', 'entra', 'defender')) {
            $source = $device[$sourceName]
            if ($null -eq $source -or -not $source['present']) { continue }
            foreach ($attr in @($source['attributes'])) {
                $key = [string]$attr['key']
                if ($key -eq 'hostname') { Add-QuorumSecret $Bag $attr['value'] 'host' }
                elseif ($key -eq 'upn' -or $key -eq 'user') { Add-QuorumSecret $Bag $attr['value'] 'user' }
                elseif ($key -eq 'ip') { Add-QuorumSecret $Bag $attr['value'] 'ip' }
            }
        }
    }
}

function Add-QuorumSecretText {
    param($Value, $Texts)
    if ($null -eq $Value) { return }
    if ($Value -is [string]) {
        if ($Value.Length -gt 0) { $Texts.Add($Value) }
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) { Add-QuorumSecretText $Value[$key] $Texts }
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        foreach ($item in $Value) { Add-QuorumSecretText $item $Texts }
    }
}

function Add-QuorumSecret {
    param($Bag, $Value, [string]$Kind)
    if ($null -eq $Value) { return }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -lt 3) { return }
    $lookup = $text.ToLowerInvariant()
    if ($Bag.ContainsKey($lookup)) { return }
    $Bag[$lookup] = @{ Kind = $Kind; Value = $text; Lookup = $lookup }
}

function New-QuorumPseudonym {
    param([byte[]]$Salt, [string]$Value, [string]$Kind)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 (, $Salt)
    try {
        $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
    }
    finally { $hmac.Dispose() }
    $hex = -join ($hash[0..5] | ForEach-Object { $_.ToString('x2') })
    $prefix = 'id'
    if ($Kind -eq 'host') { $prefix = 'host' }
    elseif ($Kind -eq 'user') { $prefix = 'user' }
    elseif ($Kind -eq 'ip') { $prefix = 'ip' }
    return "$prefix-$hex"
}

function Update-QuorumSecretValue {
    param($Value, $Plan)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (Update-QuorumSecretString $Value $Plan) }
    if ($Value -is [bool] -or (Test-QuorumNumber $Value)) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            $Value[$key] = Update-QuorumSecretValue $Value[$key] $Plan
        }
        return $Value
    }
    if ($Value -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Value.Count; $i++) {
            $Value[$i] = Update-QuorumSecretValue $Value[$i] $Plan
        }
        return $Value
    }
    if ($Value -is [System.Collections.IEnumerable]) { return $Value }
    return $Value
}

function Update-QuorumSecretString {
    param([string]$Text, $Plan)
    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($Plan.Pattern)) { return $Text }
    $regex = New-Object System.Text.RegularExpressions.Regex ($Plan.Pattern, ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant))
    $matches = $regex.Matches($Text)
    if ($matches.Count -eq 0) { return $Text }
    $sb = New-Object System.Text.StringBuilder
    $cursor = 0
    foreach ($match in $matches) {
        if ($match.Index -gt $cursor) {
            [void]$sb.Append($Text.Substring($cursor, $match.Index - $cursor))
        }
        if ($match.Index -ge $cursor) {
            $key = $match.Value.ToLowerInvariant()
            if ($Plan.Map.ContainsKey($key)) { [void]$sb.Append([string]$Plan.Map[$key]) }
            else { [void]$sb.Append($match.Value) }
            $cursor = $match.Index + $match.Length
        }
    }
    if ($cursor -lt $Text.Length) { [void]$sb.Append($Text.Substring($cursor)) }
    return $sb.ToString()
}
