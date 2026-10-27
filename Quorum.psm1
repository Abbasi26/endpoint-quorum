Set-StrictMode -Version 1.0

$script:QuorumModuleRoot = $PSScriptRoot

foreach ($dirName in @('Private', 'Collectors', 'Public')) {
    $dir = Join-Path $PSScriptRoot $dirName
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $files = Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | Sort-Object Name
    foreach ($file in $files) {
        . $file.FullName
    }
}

Update-TypeData -TypeName 'Quorum.Result' -DefaultDisplayPropertySet @(
    'Mode', 'DeviceCount', 'FindingCount', 'HtmlPath', 'MarkdownPath', 'CsvPath', 'JsonPath'
) -Force

Export-ModuleMember -Function 'Invoke-Quorum'