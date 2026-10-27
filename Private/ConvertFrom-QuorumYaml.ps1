Set-StrictMode -Version 1.0

function ConvertFrom-QuorumYaml {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $Content = [System.IO.File]::ReadAllText($Path)
    }
    if ($null -eq $Content -or $Content.Trim() -eq '') {
        throw 'YAML content is empty.'
    }

    $Content = $Content.TrimStart([char]0xFEFF)
    $rawLines = [regex]::Split($Content, "\r\n|\n|\r")
    $lines = New-Object System.Collections.Generic.List[object]
    $number = 0
    foreach ($raw in $rawLines) {
        $number++
        if ($raw -match '^\t' -or $raw -match '^[ ]*\t') {
            throw "Line ${number}: tabs are not allowed in Quorum YAML. Use spaces."
        }
        $lines.Add([pscustomobject]@{ Number = $number; Text = $raw })
    }

    $parser = @{
        Lines = $lines
        Index = 0
    }
    $doc = Read-QuorumYamlBlock -Parser $parser -MinIndent 0
    return $doc
}

function Find-QuorumYamlContent {
    param($Parser)
    while ($Parser.Index -lt $Parser.Lines.Count) {
        $item = $Parser.Lines[$Parser.Index]
        if ($item.Text -match '^\s*(#|$)') {
            $Parser.Index++
            continue
        }
        return $item
    }
    return $null
}

function Get-QuorumYamlIndent {
    param([string]$Text)
    if ($Text -match '^( *)') { return $Matches[1].Length }
    return 0
}

function Remove-QuorumYamlComment {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $inQuote = $false
    $quote = [char]0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inQuote) {
            if ($ch -eq $quote) { $inQuote = $false }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") {
            $inQuote = $true
            $quote = $ch
            continue
        }
        if ($ch -eq '#') { return $Text.Substring(0, $i).Trim() }
    }
    return $Text.Trim()
}

function ConvertFrom-QuorumYamlScalar {
    param([string]$Raw)
    if ($null -eq $Raw) { return $null }
    $text = $Raw.Trim()
    if ($text -eq '' -or $text -eq '~' -or $text -eq 'null' -or $text -eq 'Null' -or $text -eq 'NULL') { return $null }
    if ($text -eq 'true' -or $text -eq 'True' -or $text -eq 'TRUE') { return $true }
    if ($text -eq 'false' -or $text -eq 'False' -or $text -eq 'FALSE') { return $false }
    if ($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')) {
        $inner = $text.Substring(1, $text.Length - 2)
        return $inner.Replace('\n', "`n").Replace('\t', "`t").Replace('\"', '"').Replace('\\', '\')
    }
    if ($text.Length -ge 2 -and $text.StartsWith("'") -and $text.EndsWith("'")) {
        $inner = $text.Substring(1, $text.Length - 2)
        return $inner.Replace("''", "'")
    }
    if ($text -match '^-?\d+$') { return [int64]$text }
    if ($text -match '^-?\d+\.\d+$') {
        return [double]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $text
}

function Split-QuorumYamlKey {
    param([string]$Text, [int]$Number)
    $inQuote = $false
    $quote = [char]0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inQuote) {
            if ($ch -eq $quote) { $inQuote = $false }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") {
            $inQuote = $true
            $quote = $ch
            continue
        }
        if ($ch -eq ':') {
            $key = $Text.Substring(0, $i).Trim()
            $rest = Remove-QuorumYamlComment $Text.Substring($i + 1)
            if ($key.Length -ge 2 -and (($key.StartsWith('"') -and $key.EndsWith('"')) -or ($key.StartsWith("'") -and $key.EndsWith("'")))) {
                $key = [string](ConvertFrom-QuorumYamlScalar $key)
            }
            if ([string]::IsNullOrWhiteSpace($key)) {
                throw "Line ${Number}: missing key."
            }
            return [pscustomobject]@{ Key = $key; Rest = $rest }
        }
    }
    throw "Line ${Number}: expected 'key: value'."
}

function Read-QuorumYamlBlockScalar {
    param($Parser, [int]$MinIndent, [bool]$Fold)
    $lines = New-Object System.Collections.Generic.List[string]
    $contentIndent = -1
    while ($Parser.Index -lt $Parser.Lines.Count) {
        $item = $Parser.Lines[$Parser.Index]
        $text = [string]$item.Text
        if ($text -match '^\s*$') {
            if ($lines.Count -gt 0) { $lines.Add('') }
            $Parser.Index++
            continue
        }
        $indent = Get-QuorumYamlIndent $text
        if ($contentIndent -lt 0) {
            if ($indent -lt $MinIndent) { break }
            $contentIndent = $indent
        }
        if ($indent -lt $contentIndent) { break }
        $lines.Add($text.Substring($contentIndent))
        $Parser.Index++
    }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
        $lines.RemoveAt($lines.Count - 1)
    }
    if (-not $Fold) { return ($lines -join "`n") }

    $paragraphs = New-Object System.Collections.Generic.List[string]
    $buffer = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -eq '') {
            if ($buffer.Count -gt 0) {
                $paragraphs.Add(($buffer -join ' '))
                $buffer.Clear()
            }
            continue
        }
        $buffer.Add($line.Trim())
    }
    if ($buffer.Count -gt 0) { $paragraphs.Add(($buffer -join ' ')) }
    return ($paragraphs -join "`n`n")
}

function Read-QuorumYamlBlock {
    param($Parser, [int]$MinIndent)
    $item = Find-QuorumYamlContent $Parser
    if ($null -eq $item) { return $null }
    $indent = Get-QuorumYamlIndent $item.Text
    if ($indent -lt $MinIndent) { return $null }
    $trim = $item.Text.Trim()
    if ($trim.StartsWith('-')) {
        $list = Read-QuorumYamlList $Parser $indent
        return ,$list
    }
    $map = Read-QuorumYamlMap $Parser $indent
    return ,$map
}

function Read-QuorumYamlMap {
    param($Parser, [int]$Indent)
    $map = [ordered]@{}
    while ($true) {
        $item = Find-QuorumYamlContent $Parser
        if ($null -eq $item) { break }
        $ind = Get-QuorumYamlIndent $item.Text
        if ($ind -lt $Indent) { break }
        if ($ind -gt $Indent) { throw "Line $($item.Number): unexpected indentation." }
        $trim = $item.Text.Substring($Indent)
        if ($trim.StartsWith('-')) { break }
        $pair = Split-QuorumYamlKey $trim $item.Number
        $Parser.Index++
        $map[$pair.Key] = (Read-QuorumYamlValue $Parser $Indent $pair.Rest $item.Number)
    }
    return ,$map
}

function Read-QuorumYamlValue {
    param($Parser, [int]$Indent, [string]$Rest, [int]$Number)
    if ($Rest -eq '|' -or $Rest -eq '|-' -or $Rest -eq '|+') {
        return (Read-QuorumYamlBlockScalar $Parser ($Indent + 1) $false)
    }
    if ($Rest -eq '>' -or $Rest -eq '>-' -or $Rest -eq '>+') {
        return (Read-QuorumYamlBlockScalar $Parser ($Indent + 1) $true)
    }
    if ($Rest -eq '') {
        $next = Find-QuorumYamlContent $Parser
        if ($null -eq $next) { return $null }
        $nextIndent = Get-QuorumYamlIndent $next.Text
        if ($nextIndent -gt $Indent) {
            $nested = Read-QuorumYamlBlock $Parser ($Indent + 1)
            if ($null -eq $nested) { return $null }
            return ,$nested
        }
        return $null
    }
    return (ConvertFrom-QuorumYamlScalar $Rest)
}

function Read-QuorumYamlList {
    param($Parser, [int]$Indent)
    $list = New-Object System.Collections.Generic.List[object]
    while ($true) {
        $item = Find-QuorumYamlContent $Parser
        if ($null -eq $item) { break }
        $ind = Get-QuorumYamlIndent $item.Text
        if ($ind -ne $Indent) { break }
        $trim = $item.Text.Substring($Indent)
        if (-not $trim.StartsWith('-')) { break }
        $rest = $trim.Substring(1).Trim()
        $Parser.Index++
        if ($rest -eq '') {
            $child = Read-QuorumYamlBlock $Parser ($Indent + 1)
            $list.Add($child)
            continue
        }
        if ($rest.StartsWith('-')) {
            throw "Line $($item.Number): nest a list under a key, not directly under another dash."
        }
        $colon = Test-QuorumYamlHasKey $rest
        if ($colon) {
            $keyIndent = $Indent + 2
            $map = [ordered]@{}
            $pair = Split-QuorumYamlKey $rest $item.Number
            $map[$pair.Key] = (Read-QuorumYamlValue $Parser $keyIndent $pair.Rest $item.Number)
            while ($true) {
                $nxt = Find-QuorumYamlContent $Parser
                if ($null -eq $nxt) { break }
                $nind = Get-QuorumYamlIndent $nxt.Text
                if ($nind -ne $keyIndent) { break }
                $ntrim = $nxt.Text.Substring($nind)
                if ($ntrim.StartsWith('-')) { break }
                $nextPair = Split-QuorumYamlKey $ntrim $nxt.Number
                $Parser.Index++
                $map[$nextPair.Key] = (Read-QuorumYamlValue $Parser $keyIndent $nextPair.Rest $nxt.Number)
            }
            $list.Add($map)
            continue
        }
        $list.Add((ConvertFrom-QuorumYamlScalar (Remove-QuorumYamlComment $rest)))
    }
    return ,$list.ToArray()
}

function Test-QuorumYamlHasKey {
    param([string]$Text)
    $inQuote = $false
    $quote = [char]0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inQuote) {
            if ($ch -eq $quote) { $inQuote = $false }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") { $inQuote = $true; $quote = $ch; continue }
        if ($ch -eq ':') { return $true }
    }
    return $false
}