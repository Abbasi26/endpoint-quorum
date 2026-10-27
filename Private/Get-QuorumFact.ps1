Set-StrictMode -Version 1.0

function Get-QuorumFact {
    param($Device, [datetime]$AsOf)

    $intune = Select-QuorumLatestRecord @($Device.BySource.Intune)
    $entra = Select-QuorumLatestRecord @($Device.BySource.Entra)
    $defender = Select-QuorumLatestRecord @($Device.BySource.Defender)
    $facts = @{}

    $facts['intune.present'] = ($null -ne $intune)
    $facts['intune.complianceState'] = $(if ($intune) { $intune.ComplianceState } else { $null })
    $facts['intune.lastSyncAgeDays'] = $(if ($intune) { Get-QuorumAgeDays $intune.ObservedAt $AsOf } else { $null })
    $facts['intune.osBuild'] = $(if ($intune) { $intune.OsBuild } else { $null })

    $facts['entra.present'] = ($null -ne $entra)
    $facts['entra.enabled'] = $(if ($entra) { $entra.AccountEnabled } else { $null })
    $facts['entra.isCompliant'] = $(if ($entra) { $entra.IsCompliant } else { $null })
    $facts['entra.isManaged'] = $(if ($entra) { $entra.IsManaged } else { $null })
    $facts['entra.trustType'] = $(if ($entra) { $entra.TrustType } else { $null })
    $facts['entra.operatingSystem'] = $(if ($entra) { $entra.OperatingSystem } else { $null })
    $facts['entra.lastSignInAgeDays'] = $(if ($entra) { Get-QuorumAgeDays $entra.ObservedAt $AsOf } else { $null })
    $facts['entra.osBuild'] = $(if ($entra) { $entra.OsBuild } else { $null })

    $facts['defender.present'] = ($null -ne $defender)
    $facts['defender.healthStatus'] = $(if ($defender) { $defender.HealthStatus } else { $null })
    $facts['defender.riskScore'] = $(if ($defender) { $defender.RiskScore } else { $null })
    $facts['defender.exposureLevel'] = $(if ($defender) { $defender.ExposureLevel } else { $null })
    $facts['defender.onboardingStatus'] = $(if ($defender) { $defender.OnboardingStatus } else { $null })
    $facts['defender.lastSeenAgeDays'] = $(if ($defender) { Get-QuorumAgeDays $defender.ObservedAt $AsOf } else { $null })
    $facts['defender.osBuild'] = $(if ($defender) { $defender.OsBuild } else { $null })

    $builds = New-Object System.Collections.Generic.List[string]
    foreach ($build in @($facts['intune.osBuild'], $facts['entra.osBuild'], $facts['defender.osBuild'])) {
        if ($build -and -not $builds.Contains([string]$build)) { $builds.Add([string]$build) }
    }
    $sortedBuilds = @($builds | Sort-Object)
    $facts['os.buildMismatch'] = ($sortedBuilds.Count -ge 2)
    if ($sortedBuilds.Count -gt 0) { $facts['os.builds'] = ($sortedBuilds -join ',') }
    else { $facts['os.builds'] = $null }

    $intuneSays = $facts['intune.complianceState']
    $entraSays = $facts['entra.isCompliant']
    $disagrees = $false
    if ($facts['intune.present'] -and $facts['entra.present'] -and $null -ne $entraSays) {
        if ($intuneSays -eq 'compliant' -and $entraSays -eq $false) { $disagrees = $true }
        if ($intuneSays -eq 'noncompliant' -and $entraSays -eq $true) { $disagrees = $true }
    }
    $facts['compliance.disagrees'] = $disagrees

    $facts['hostname.key'] = $Device.HostnameKey
    $facts['hostname.duplicate'] = [bool]$Device.Duplicate
    $facts['hostname.duplicateCount'] = [int]$Device.DuplicateCount
    $facts['match.method'] = [string]$Device.MatchMethod
    $facts['match.confidence'] = [string]$Device.MatchConfidence
    $facts['match.score'] = $Device.MatchScore

    $sourceCount = 0
    if ($intune) { $sourceCount++ }
    if ($entra) { $sourceCount++ }
    if ($defender) { $sourceCount++ }
    $facts['sources.count'] = $sourceCount
    return $facts
}

function Select-QuorumLatestRecord {
    param($Record)
    $best = $null
    foreach ($rec in @($Record)) {
        if ($null -eq $rec) { continue }
        if ($null -eq $best) { $best = $rec; continue }
        if ($null -eq $best.ObservedAt -and $null -ne $rec.ObservedAt) { $best = $rec; continue }
        if ($null -ne $rec.ObservedAt -and $null -ne $best.ObservedAt -and $rec.ObservedAt -gt $best.ObservedAt) {
            $best = $rec
        }
    }
    return $best
}