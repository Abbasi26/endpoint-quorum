Set-StrictMode -Version 1.0

function New-QuorumReport {
    param(
        [Parameter(Mandatory = $true)]$Model,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        $RedactionMap
    )
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }
    $htmlPath = Join-QuorumPath $OutputPath 'Quorum-Report.html'
    $markdownPath = Join-QuorumPath $OutputPath 'Quorum-Summary.md'
    $csvPath = Join-QuorumPath $OutputPath 'Quorum-Findings.csv'
    $jsonPath = Join-QuorumPath $OutputPath 'Quorum-Findings.json'
    $mapPath = $null

    $json = ConvertTo-QuorumJson $Model
    $templatePath = Join-QuorumPath $script:QuorumModuleRoot 'Private' 'report-template.html'
    $template = [System.IO.File]::ReadAllText($templatePath)
    if ($template.IndexOf('__QUORUM_DATA__') -lt 0) { throw 'Report template is missing the data placeholder.' }
    $html = $template.Replace('__QUORUM_DATA__', $json)
    Write-QuorumTextFile -Path $htmlPath -Content $html
    Write-QuorumTextFile -Path $markdownPath -Content (New-QuorumMarkdown $Model)
    Write-QuorumTextFile -Path $csvPath -Content (New-QuorumCsv $Model)
    Write-QuorumTextFile -Path $jsonPath -Content ($json + "`n")
    if ($null -ne $RedactionMap) {
        $mapPath = Join-QuorumPath $OutputPath 'Quorum-RedactionMap.json'
        $mapDoc = [ordered]@{
            warning = 'Do not share this file. It reverses the pseudonyms in the Quorum report written beside it.'
            entries = @($RedactionMap)
        }
        Write-QuorumTextFile -Path $mapPath -Content ((ConvertTo-QuorumJson $mapDoc) + "`n")
    }
    [pscustomobject]@{
        HtmlPath         = $htmlPath
        MarkdownPath     = $markdownPath
        CsvPath          = $csvPath
        JsonPath         = $jsonPath
        RedactionMapPath = $mapPath
    }
}

function New-QuorumMarkdown {
    param($Model)
    $meta = $Model['meta']
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Quorum summary')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| | |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine('| Mode | ' + (ConvertTo-QuorumMarkdownCell $meta['mode']) + ' |')
    [void]$sb.AppendLine('| Data clock | ' + (ConvertTo-QuorumMarkdownCell $meta['asOf']) + ' |')
    [void]$sb.AppendLine('| Report built | ' + (ConvertTo-QuorumMarkdownCell $meta['generatedAt']) + ' |')
    [void]$sb.AppendLine('| Devices | ' + $meta['deviceCount'] + ' |')
    [void]$sb.AppendLine('| Findings | ' + $meta['findingCount'] + ' |')
    [void]$sb.AppendLine('| Devices with no finding | ' + $meta['clearCount'] + ' |')
    [void]$sb.AppendLine('| Redacted | ' + $(if ($meta['redacted']) { 'yes' } else { 'no' }) + ' |')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine((ConvertTo-QuorumMarkdownCell $meta['note']))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Quorum reports disagreements between sources. A device that every source already calls unhealthy is not, by itself, a finding.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Severity')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Severity | Findings |')
    [void]$sb.AppendLine('| --- | ---: |')
    $sevCounts = @{}
    foreach ($finding in @($Model['findings'])) {
        $sev = [string]$finding['severity']
        if (-not $sevCounts.ContainsKey($sev)) { $sevCounts[$sev] = 0 }
        $sevCounts[$sev]++
    }
    foreach ($sev in @('critical', 'high', 'medium', 'low', 'info')) {
        $count = 0
        if ($sevCounts.ContainsKey($sev)) { $count = $sevCounts[$sev] }
        if ($count -gt 0) { [void]$sb.AppendLine('| ' + $sev + ' | ' + $count + ' |') }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Rules')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Rule | Severity | Findings | Title |')
    [void]$sb.AppendLine('| --- | --- | ---: | --- |')
    $byRule = @{}
    foreach ($finding in @($Model['findings'])) {
        $id = [string]$finding['ruleId']
        if (-not $byRule.ContainsKey($id)) { $byRule[$id] = 0 }
        $byRule[$id]++
    }
    foreach ($rule in @($Model['rules'])) {
        $count = 0
        if ($byRule.ContainsKey([string]$rule['id'])) { $count = $byRule[[string]$rule['id']] }
        [void]$sb.AppendLine('| ' + (ConvertTo-QuorumMarkdownCell $rule['id']) + ' | ' + (ConvertTo-QuorumMarkdownCell $rule['severity']) + ' | ' + $count + ' | ' + (ConvertTo-QuorumMarkdownCell $rule['title']) + ' |')
    }
    [void]$sb.AppendLine('')
    foreach ($rule in @($Model['rules'])) {
        $mine = @($Model['findings'] | Where-Object { $_['ruleId'] -eq $rule['id'] })
        if ($mine.Count -eq 0) { continue }
        [void]$sb.AppendLine('## ' + $rule['id'] + ' - ' + $rule['title'])
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($rule['description'])
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('**Why it matters.** ' + $rule['whyItMatters'])
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('**What to do.** ' + $rule['remediation'])
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Device | Match | Evidence |')
        [void]$sb.AppendLine('| --- | --- | --- |')
        foreach ($finding in $mine) {
            $ev = New-Object System.Collections.Generic.List[string]
            foreach ($item in @($finding['evidence'])) {
                $ev.Add(([string]$item['label'] + ': ' + [string]$item['value']))
            }
            $match = [string]$finding['matchMethod'] + ' / ' + [string]$finding['matchConfidence']
            [void]$sb.AppendLine('| ' + (ConvertTo-QuorumMarkdownCell $finding['hostname']) + ' | ' + (ConvertTo-QuorumMarkdownCell $match) + ' | ' + (ConvertTo-QuorumMarkdownCell ($ev -join '; ')) + ' |')
        }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('## Collectors')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Source | Records | Status |')
    [void]$sb.AppendLine('| --- | ---: | --- |')
    foreach ($collector in @($Model['collectors'])) {
        $status = [string]$collector['status']
        if ($collector['error']) { $status = $status + ': ' + [string]$collector['error'] }
        [void]$sb.AppendLine('| ' + (ConvertTo-QuorumMarkdownCell $collector['source']) + ' | ' + $collector['recordCount'] + ' | ' + (ConvertTo-QuorumMarkdownCell $status) + ' |')
    }
    [void]$sb.AppendLine('')
    return $sb.ToString()
}

function New-QuorumCsv {
    param($Model)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('RuleId,Severity,Title,Hostname,QuorumId,MatchMethod,MatchConfidence,Sources,Evidence,WhyItMatters,Remediation')
    foreach ($finding in @($Model['findings'])) {
        $ev = New-Object System.Collections.Generic.List[string]
        foreach ($item in @($finding['evidence'])) {
            $ev.Add(([string]$item['key'] + '=' + [string]$item['value']))
        }
        $fields = @(
            $finding['ruleId']
            $finding['severity']
            $finding['title']
            $finding['hostname']
            (@($finding['quorumIds']) -join '|')
            $finding['matchMethod']
            $finding['matchConfidence']
            (@($finding['sources']) -join '|')
            ($ev -join '; ')
            $finding['whyItMatters']
            $finding['remediation']
        )
        $encoded = New-Object System.Collections.Generic.List[string]
        foreach ($field in $fields) { $encoded.Add((ConvertTo-QuorumCsvField $field)) }
        $lines.Add($encoded -join ',')
    }
    return (($lines -join "`n") + "`n")
}

function ConvertTo-QuorumMarkdownCell {
    param($Value)
    if ($null -eq $Value) { return '' }
    return (([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' '))
}

function ConvertTo-QuorumCsvField {
    param($Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ($text.Contains('"') -or $text.Contains(',') -or $text.Contains("`n") -or $text.Contains("`r")) {
        return '"' + $text.Replace('"', '""') + '"'
    }
    return $text
}