param(
    [string]$OutputDirectory = 'SimpaninKeyboard',
    [int]$MaxCandidates = 180,
    [int]$MaxWordLength = 12,
    [int]$MaxZhwikiPerKey = 120,
    [int]$MaxWebSlangPerKey = 24,
    [switch]$KeepDownloads
)

$ErrorActionPreference = 'Stop'

$repo = Get-Location
$targetDirectory = Join-Path $repo $OutputDirectory
$tsvPath = Join-Path $targetDirectory 'PinyinLexicon.tsv'
$indexPath = Join-Path $targetDirectory 'PinyinLexicon.idx'
$tempDirectory = Join-Path $repo '.zhwiki-lexicon-tmp'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Load-ExistingKeys([string]$path) {
    $keys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($line in [System.IO.File]::ReadLines($path, $utf8NoBom)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $tab = $line.IndexOf("`t")
        if ($tab -le 0) { continue }
        $key = Normalize-Key $line.Substring(0, $tab)
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            [void]$keys.Add($key)
        }
    }
    return $keys
}

function Normalize-Key([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    return ([regex]::Replace($value.ToLowerInvariant(), '[^a-z]', ''))
}

function Normalize-Text([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    return ($value -replace "`t", ' ' -replace "`r|`n", '').Trim()
}

function Add-ExternalCandidate($store, $allowedKeys, [string]$key, [string]$text, [int]$weight, [int]$limit) {
    $key = Normalize-Key $key
    $text = Normalize-Text $text
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    if ($null -ne $allowedKeys -and -not $allowedKeys.Contains($key)) { return }
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    if ($text.Length -gt $MaxWordLength) { return }
    if ($utf8NoBom.GetByteCount($key) -gt 16) { return }

    if (-not $store.ContainsKey($key)) {
        $store[$key] = [System.Collections.Generic.List[string]]::new()
    }
    if ($store[$key].Count -ge $limit) { return }

    foreach ($field in $store[$key]) {
        if ($field.StartsWith($text + ':')) { return }
    }

    $store[$key].Add("$($text):$weight")
}

function Get-LatestAssetUrl([string]$pattern) {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/felixonmars/fcitx5-pinyin-zhwiki/releases/latest' -Headers @{ 'User-Agent' = 'aTool-ios-lexicon-builder' }
    $asset = $release.assets | Where-Object { $_.name -like $pattern } | Sort-Object name -Descending | Select-Object -First 1
    if (-not $asset) { throw "Could not find release asset matching $pattern" }
    return $asset.browser_download_url
}

function Download-Asset([string]$pattern, [string]$fileName) {
    New-Item -ItemType Directory -Force -Path $tempDirectory | Out-Null
    $path = Join-Path $tempDirectory $fileName
    if (Test-Path -LiteralPath $path) { return $path }

    $url = Get-LatestAssetUrl $pattern
    Invoke-WebRequest -Uri $url -OutFile $path -Headers @{ 'User-Agent' = 'aTool-ios-lexicon-builder' }
    return $path
}

function Import-RimeYamlLexicon($store, $allowedKeys, [string]$path, [int]$baseWeight, [int]$maxPerKey) {
    $inBody = $false
    $imported = 0

    foreach ($line in [System.IO.File]::ReadLines($path, $utf8NoBom)) {
        if (-not $inBody) {
            if ($line.Trim() -eq '...') { $inBody = $true }
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }

        $fields = $line.Split("`t")
        if ($fields.Count -lt 2) { continue }

        $key = Normalize-Key $fields[1]
        if ($null -ne $allowedKeys -and -not $allowedKeys.Contains($key)) { continue }
        $before = if ($store.ContainsKey($key)) { $store[$key].Count } else { 0 }
        $weight = $baseWeight + [Math]::Max(0, $maxPerKey - $before)
        Add-ExternalCandidate $store $allowedKeys $key $fields[0] $weight $maxPerKey
        if ($store.ContainsKey($key) -and $store[$key].Count -gt $before) { $imported += 1 }
    }

    return $imported
}

function Write-IndexRecord($indexStream, [string]$key, [UInt64]$offset, [int]$length) {
    $keyBytes = $utf8NoBom.GetBytes($key)
    if ($keyBytes.Length -gt 16) { return }

    $keyBuffer = New-Object byte[] 16
    [Array]::Copy($keyBytes, $keyBuffer, $keyBytes.Length)
    $offsetBytes = [BitConverter]::GetBytes($offset)
    $lengthBytes = [BitConverter]::GetBytes([UInt32]$length)

    $indexStream.Write($keyBuffer, 0, $keyBuffer.Length)
    $indexStream.Write($offsetBytes, 0, $offsetBytes.Length)
    $indexStream.Write($lengthBytes, 0, $lengthBytes.Length)
}

function Write-MergedLexicon($externalByKey, [string]$sourceTsv, [string]$targetTsv, [string]$targetIdx) {
    $tmpTsv = "$targetTsv.tmp"
    $tmpIdx = "$targetIdx.tmp"
    $existingByKey = @{}

    foreach ($line in [System.IO.File]::ReadLines($sourceTsv, $utf8NoBom)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $fields = [System.Collections.Generic.List[string]]::new()
        $fields.AddRange($line.Split("`t"))
        if ($fields.Count -lt 2) { continue }

        $key = Normalize-Key $fields[0]
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($utf8NoBom.GetByteCount($key) -gt 16) { continue }
        $existingByKey[$key] = $fields
    }

    $allKeys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($key in $existingByKey.Keys) { [void]$allKeys.Add($key) }
    foreach ($key in $externalByKey.Keys) { [void]$allKeys.Add($key) }

    $stream = [System.IO.File]::Open($tmpTsv, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $indexStream = [System.IO.File]::Open($tmpIdx, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $keyCount = 0
    $candidateCount = 0

    try {
        foreach ($key in ($allKeys | Sort-Object)) {
            if ($utf8NoBom.GetByteCount($key) -gt 16) { continue }
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            $existing = [System.Collections.Generic.List[string]]::new()

            if ($externalByKey.ContainsKey($key)) {
                foreach ($field in $externalByKey[$key]) {
                    if ($existing.Count -ge $MaxCandidates) { break }
                    $separator = $field.LastIndexOf(':')
                    $text = if ($separator -gt 0) { $field.Substring(0, $separator) } else { $field }
                    if ($seen.Add($text)) { $existing.Add($field) }
                }
            }

            if ($existingByKey.ContainsKey($key)) {
                $fields = $existingByKey[$key]
                for ($index = 1; $index -lt $fields.Count; $index += 1) {
                    $field = $fields[$index]
                    if ([string]::IsNullOrWhiteSpace($field)) { continue }
                    $separator = $field.LastIndexOf(':')
                    $text = if ($separator -gt 0) { $field.Substring(0, $separator) } else { $field }
                    if ($seen.Add($text)) { $existing.Add($field) }
                    if ($existing.Count -ge $MaxCandidates) { break }
                }
            }

            if ($existing.Count -eq 0) { continue }
            $offset = [UInt64]$stream.Position
            $outputLine = $key + "`t" + ($existing -join "`t") + "`n"
            $bytes = $utf8NoBom.GetBytes($outputLine)
            $stream.Write($bytes, 0, $bytes.Length)
            Write-IndexRecord $indexStream $key $offset $bytes.Length
            $keyCount += 1
            $candidateCount += $existing.Count
        }
    } finally {
        $stream.Dispose()
        $indexStream.Dispose()
    }

    Move-Item -LiteralPath $tmpTsv -Destination $targetTsv -Force
    Move-Item -LiteralPath $tmpIdx -Destination $targetIdx -Force

    return [PSCustomObject]@{
        Keys = $keyCount
        Candidates = $candidateCount
        TSVBytes = (Get-Item $targetTsv).Length
        IndexBytes = (Get-Item $targetIdx).Length
        TSV = $targetTsv
        Index = $targetIdx
    }
}

if (-not (Test-Path -LiteralPath $tsvPath)) { throw "Missing existing lexicon: $tsvPath" }

$existingKeys = Load-ExistingKeys $tsvPath
$externalByKey = @{}
$zhwikiYaml = Download-Asset 'zhwiki-*.dict.yaml' 'zhwiki.dict.yaml'
$webSlangYaml = Download-Asset 'web-slang-*.dict.yaml' 'web-slang.dict.yaml'

$zhwikiImported = Import-RimeYamlLexicon $externalByKey $null $zhwikiYaml 220 $MaxZhwikiPerKey
$webSlangImported = Import-RimeYamlLexicon $externalByKey $null $webSlangYaml 260 $MaxWebSlangPerKey
$result = Write-MergedLexicon $externalByKey $tsvPath $tsvPath $indexPath

$result | Add-Member -NotePropertyName ZhwikiImported -NotePropertyValue $zhwikiImported
$result | Add-Member -NotePropertyName WebSlangImported -NotePropertyValue $webSlangImported
$result

if (-not $KeepDownloads -and (Test-Path -LiteralPath $tempDirectory)) {
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force
}
