Set-StrictMode -Version 1.0

# Read-only. Permission: DeviceManagementManagedDevices.Read.All
# GET https://graph.microsoft.com/v1.0/deviceManagement/managedDevices
function Get-QuorumIntuneDevice {
    param(
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [string]$BaseUri = 'https://graph.microsoft.com/v1.0'
    )
    $uri = $BaseUri.TrimEnd('/') + '/deviceManagement/managedDevices?' + '$top=100'
    $items = Get-QuorumPagedValue -Uri $uri -Token $AccessToken
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        foreach ($record in @(ConvertTo-QuorumIntuneRecord -Item $item)) {
            $records.Add($record)
        }
    }
    return ,$records.ToArray()
}