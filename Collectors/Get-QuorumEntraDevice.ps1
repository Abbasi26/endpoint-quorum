Set-StrictMode -Version 1.0

# Read-only. Permission: Device.Read.All
# GET https://graph.microsoft.com/v1.0/devices
function Get-QuorumEntraDevice {
    param(
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [string]$BaseUri = 'https://graph.microsoft.com/v1.0'
    )
    $uri = $BaseUri.TrimEnd('/') + '/devices?' + '$top=999'
    $items = Get-QuorumPagedValue -Uri $uri -Token $AccessToken
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        foreach ($record in @(ConvertTo-QuorumEntraRecord -Item $item)) {
            $records.Add($record)
        }
    }
    return ,$records.ToArray()
}