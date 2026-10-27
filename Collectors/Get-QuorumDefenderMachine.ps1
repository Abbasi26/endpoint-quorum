Set-StrictMode -Version 1.0

# Read-only. Delegated permission: Machine.Read
# Application permission: Machine.Read.All on Windows Defender ATP.
# GET https://api.security.microsoft.com/api/machines
# Machine.Read is narrower than the Graph hunting permission ThreatHunting.Read.All,
# so Quorum uses the Defender API instead of Microsoft Graph for this source.
function Get-QuorumDefenderMachine {
    param(
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [string]$BaseUri = 'https://api.security.microsoft.com'
    )
    $uri = $BaseUri.TrimEnd('/') + '/api/machines'
    $items = Get-QuorumPagedValue -Uri $uri -Token $AccessToken
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        foreach ($record in @(ConvertTo-QuorumDefenderRecord -Item $item)) {
            $records.Add($record)
        }
    }
    return ,$records.ToArray()
}