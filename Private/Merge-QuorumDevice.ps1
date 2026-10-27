Set-StrictMode -Version 1.0

function Merge-QuorumDevice {
    param($Record)

    $incoming = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Record) {
        foreach ($one in @($Record)) {
            if ($null -ne $one) { $incoming.Add($one) }
        }
    }

    $clusters = New-Object System.Collections.Generic.List[object]
    $byId = @{}
    $unmatched = New-Object System.Collections.Generic.List[object]

    foreach ($rec in $incoming) {
        if ($rec.DeviceId) {
            if (-not $byId.ContainsKey($rec.DeviceId)) {
                $cluster = New-QuorumCluster -Form 'deviceId'
                $byId[$rec.DeviceId] = $cluster
                $clusters.Add($cluster)
            }
            $byId[$rec.DeviceId].Records.Add($rec)
        }
        else {
            $unmatched.Add($rec)
        }
    }

    $stillLoose = New-Object System.Collections.Generic.List[object]
    foreach ($rec in $unmatched) {
        if (-not $rec.HostnameKey) {
            $cluster = New-QuorumCluster -Form 'single'
            $cluster.Records.Add($rec)
            $clusters.Add($cluster)
            continue
        }
        $candidates = New-Object System.Collections.Generic.List[object]
        foreach ($cluster in $clusters) {
            if ((Test-QuorumClusterHasKey $cluster $rec.HostnameKey) -and -not (Test-QuorumClusterHasSource $cluster $rec.Source)) {
                $candidates.Add($cluster)
            }
        }
        if ($candidates.Count -eq 1) {
            $how = 'hostname'
            if (-not (Test-QuorumClusterExactHostname $candidates[0] $rec.HostnameRaw)) {
                $how = 'hostname-normalized'
            }
            $candidates[0].Links.Add($how)
            $candidates[0].Records.Add($rec)
        }
        else {
            $stillLoose.Add($rec)
        }
    }

    $looseGroups = @{}
    foreach ($rec in $stillLoose) {
        $key = $rec.HostnameKey
        if (-not $key) { $key = '' }
        if (-not $looseGroups.ContainsKey($key)) {
            $looseGroups[$key] = New-Object System.Collections.Generic.List[object]
        }
        $looseGroups[$key].Add($rec)
    }
    foreach ($key in @($looseGroups.Keys)) {
        $group = $looseGroups[$key]
        if ($key -eq '') {
            foreach ($rec in $group) {
                $cluster = New-QuorumCluster -Form 'single'
                $cluster.Records.Add($rec)
                $clusters.Add($cluster)
            }
            continue
        }
        $buckets = New-Object System.Collections.Generic.List[object]
        foreach ($rec in $group) {
            $placed = $false
            foreach ($bucket in $buckets) {
                if (-not (Test-QuorumClusterHasSource $bucket $rec.Source)) {
                    $bucket.Records.Add($rec)
                    $placed = $true
                    break
                }
            }
            if (-not $placed) {
                $bucket = New-QuorumCluster -Form 'hostname'
                $bucket.Records.Add($rec)
                $buckets.Add($bucket)
            }
        }
        foreach ($bucket in $buckets) {
            $raws = @{}
            foreach ($rec in $bucket.Records) {
                if ($rec.HostnameRaw) { $raws[$rec.HostnameRaw] = $true }
            }
            if ($bucket.Records.Count -ge 2 -and $raws.Count -gt 1) {
                $bucket.Form = 'hostname-normalized'
            }
            elseif ($bucket.Records.Count -lt 2) {
                $bucket.Form = 'single'
            }
            $clusters.Add($bucket)
        }
    }

    $devices = New-Object System.Collections.Generic.List[object]
    foreach ($cluster in $clusters) {
        $devices.Add((Complete-QuorumCluster $cluster))
    }

    $nameGroups = @{}
    foreach ($device in $devices) {
        if (-not $device.HostnameKey) { continue }
        if (-not $nameGroups.ContainsKey($device.HostnameKey)) {
            $nameGroups[$device.HostnameKey] = New-Object System.Collections.Generic.List[object]
        }
        $nameGroups[$device.HostnameKey].Add($device)
    }
    foreach ($key in @($nameGroups.Keys)) {
        $set = $nameGroups[$key]
        $count = $set.Count
        foreach ($device in $set) {
            $device.DuplicateCount = $count
            $device.Duplicate = ($count -ge 2)
        }
    }

    return ,$devices.ToArray()
}

function New-QuorumCluster {
    param([string]$Form)
    [pscustomobject]@{
        Records = New-Object System.Collections.Generic.List[object]
        Links   = New-Object System.Collections.Generic.List[string]
        Form    = $Form
    }
}

function Test-QuorumClusterHasKey {
    param($Cluster, [string]$Key)
    foreach ($rec in $Cluster.Records) {
        if ($rec.HostnameKey -and $rec.HostnameKey -eq $Key) { return $true }
    }
    return $false
}

function Test-QuorumClusterHasSource {
    param($Cluster, [string]$Source)
    foreach ($rec in $Cluster.Records) {
        if ($rec.Source -eq $Source) { return $true }
    }
    return $false
}

function Test-QuorumClusterExactHostname {
    param($Cluster, $Raw)
    if (-not $Raw) { return $false }
    foreach ($rec in $Cluster.Records) {
        if ($rec.HostnameRaw -and $rec.HostnameRaw -eq $Raw) { return $true }
    }
    return $false
}

function Complete-QuorumCluster {
    param($Cluster)
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($rec in $Cluster.Records) { $records.Add($rec) }
    $records = $records.ToArray()
    $sharedId = $false
    $idCounts = @{}
    foreach ($rec in $records) {
        if (-not $rec.DeviceId) { continue }
        if (-not $idCounts.ContainsKey($rec.DeviceId)) { $idCounts[$rec.DeviceId] = 0 }
        $idCounts[$rec.DeviceId]++
        if ($idCounts[$rec.DeviceId] -ge 2) { $sharedId = $true }
    }
    $sawNorm = $false
    $sawHost = $false
    foreach ($link in @($Cluster.Links)) {
        if ($link -eq 'hostname-normalized') { $sawNorm = $true }
        if ($link -eq 'hostname') { $sawHost = $true }
    }
    if ($Cluster.Form -eq 'hostname' -and $records.Count -ge 2) { $sawHost = $true }
    if ($Cluster.Form -eq 'hostname-normalized' -and $records.Count -ge 2) { $sawNorm = $true }

    $method = 'single'
    $confidence = 'uncorroborated'
    $score = $null
    if ($records.Count -ge 2) {
        if ($sawNorm -and $sharedId) {
            $method = 'mixed'; $confidence = 'low'; $score = 0.45
        }
        elseif ($sawNorm) {
            $method = 'hostname-normalized'; $confidence = 'low'; $score = 0.45
        }
        elseif ($sawHost -and $sharedId) {
            $method = 'mixed'; $confidence = 'medium'; $score = 0.70
        }
        elseif ($sawHost) {
            $method = 'hostname'; $confidence = 'medium'; $score = 0.70
        }
        elseif ($sharedId) {
            $method = 'deviceId'; $confidence = 'high'; $score = 0.95
        }
    }

    $key = Get-QuorumCanonicalKey $records
    $display = Get-QuorumDisplayHostname $records $key
    $parts = New-Object System.Collections.Generic.List[string]
    $sorted = @($records | Sort-Object `
        @{ Expression = { [string]$_.Source } }, `
        @{ Expression = { [string]$_.SourceObjectId } }, `
        @{ Expression = { [string]$_.DeviceId } }, `
        @{ Expression = { [string]$_.HostnameKey } })
    foreach ($rec in $sorted) {
        $parts.Add(('{0}|{1}|{2}|{3}' -f $rec.Source, [string]$rec.DeviceId, [string]$rec.HostnameKey, [string]$rec.SourceObjectId))
    }
    $bySource = @{
        Intune   = @($records | Where-Object { $_.Source -eq 'Intune' })
        Entra    = @($records | Where-Object { $_.Source -eq 'Entra' })
        Defender = @($records | Where-Object { $_.Source -eq 'Defender' })
    }

    [pscustomobject]@{
        Id                = (Get-QuorumStableId ($parts -join "`n"))
        Records           = $records
        BySource          = $bySource
        MatchMethod       = $method
        MatchConfidence   = $confidence
        MatchScore        = $score
        HostnameKey       = $key
        HostnameDisplay   = $display
        Duplicate         = $false
        DuplicateCount    = 1
    }
}

function Get-QuorumCanonicalKey {
    param($Records)
    $counts = @{}
    foreach ($rec in $Records) {
        if (-not $rec.HostnameKey) { continue }
        if (-not $counts.ContainsKey($rec.HostnameKey)) { $counts[$rec.HostnameKey] = 0 }
        $counts[$rec.HostnameKey]++
    }
    $best = $null
    $bestCount = -1
    foreach ($key in @($counts.Keys)) {
        $count = $counts[$key]
        $replace = $false
        if ($count -gt $bestCount) { $replace = $true }
        elseif ($count -eq $bestCount -and $null -ne $best -and $key -lt $best) { $replace = $true }
        elseif ($null -eq $best) { $replace = $true }
        if ($replace) { $best = $key; $bestCount = $count }
    }
    return $best
}

function Get-QuorumDisplayHostname {
    param($Records, $Key)
    $originals = New-Object System.Collections.Generic.List[string]
    foreach ($rec in $Records) {
        if ($rec.HostnameOriginal) { $originals.Add([string]$rec.HostnameOriginal) }
    }
    if (-not $Key) {
        if ($originals.Count -gt 0) { return $originals[0] }
        return '(unnamed device)'
    }
    foreach ($name in $originals) {
        if ($name.ToLowerInvariant() -eq $Key) { return $name }
    }
    $best = $null
    foreach ($name in $originals) {
        if ($null -eq $best -or $name.Length -lt $best.Length) { $best = $name }
    }
    if ($best) { return $best }
    return [string]$Key
}