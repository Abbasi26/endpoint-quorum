Set-StrictMode -Version 1.0

function Invoke-QuorumRest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Token
    )
    $headers = @{
        Authorization = 'Bearer ' + $Token
        Accept        = 'application/json'
        'User-Agent'  = 'Quorum/0.1'
    }
    $attempt = 0
    while ($attempt -lt 4) {
        $attempt++
        try {
            return Invoke-RestMethod -Method GET -Uri $Uri -Headers $headers
        }
        catch {
            $status = Get-QuorumHttpStatus $_
            if ($status -eq 429 -and $attempt -lt 4) {
                Start-Sleep -Seconds (5 * $attempt)
                continue
            }
            throw
        }
    }
}

function Get-QuorumHttpStatus {
    param($ErrorRecord)
    $response = $null
    try { $response = $ErrorRecord.Exception.Response } catch { return $null }
    if ($null -eq $response) { return $null }
    try { return [int]$response.StatusCode } catch { return $null }
}

function Get-QuorumNextLink {
    param($Page)
    if ($null -eq $Page) { return $null }
    foreach ($name in @('@odata.nextLink', 'odata.nextLink', 'nextLink')) {
        $prop = $Page.PSObject.Properties[$name]
        if ($prop -and $prop.Value) { return [string]$prop.Value }
    }
    return $null
}

function Get-QuorumPagedValue {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Token
    )
    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    $guard = 0
    while ($next -and $guard -lt 2000) {
        $guard++
        $page = Invoke-QuorumRest -Uri $next -Token $Token
        if ($null -eq $page) { break }
        $valueProp = $page.PSObject.Properties['value']
        if ($valueProp -and $null -ne $valueProp.Value) {
            foreach ($one in @($valueProp.Value)) {
                if ($null -ne $one) { $items.Add($one) }
            }
        }
        $next = Get-QuorumNextLink $page
    }
    if ($next -and $guard -ge 2000) { throw "Stopped paging after 2000 pages: $Uri" }
    return ,$items.ToArray()
}
