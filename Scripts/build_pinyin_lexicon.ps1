param(
    [string]$SourceGitSpec = 'fadee8e:SimpaninKeyboard/PinyinLexicon.json',
    [string]$OutputDirectory = 'SimpaninKeyboard',
    [int]$MaxCandidates = 120,
    [int]$MaxWordLength = 12
)

$ErrorActionPreference = 'Stop'

$repo = Get-Location
$temp = Join-Path $repo '.codex-pinyin-lexicon.json'

& git show $SourceGitSpec | Out-File -FilePath $temp -Encoding utf8

try {
    $json = Get-Content -Raw -Encoding UTF8 -Path $temp
    $source = $json | ConvertFrom-Json
    $latin1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')
    $utf8 = [System.Text.Encoding]::UTF8

    function Repair-Text([string]$value) {
        if ([string]::IsNullOrEmpty($value)) { return $value }
        try {
            $bytes = $latin1.GetBytes($value)
            $fixed = $utf8.GetString($bytes)
            if ($fixed -match '[\u4e00-\u9fff]') { return $fixed }
        } catch {
        }
        return $value
    }

    $targetDirectory = Join-Path $repo $OutputDirectory
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
    $tsvPath = Join-Path $targetDirectory 'PinyinLexicon.tsv'
    $indexPath = Join-Path $targetDirectory 'PinyinLexicon.idx'

    $stream = [System.IO.File]::Open($tsvPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $indexStream = [System.IO.File]::Open($indexPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $keyCount = 0
    $candidateCount = 0

    try {
        foreach ($property in ($source.PSObject.Properties | Sort-Object Name)) {
            $values = @()
            $seen = New-Object 'System.Collections.Generic.HashSet[string]'

            foreach ($raw in @($property.Value)) {
                $candidate = Repair-Text ([string]$raw)
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                if ($candidate.Length -gt $MaxWordLength) { continue }
                $candidate = $candidate -replace "`t", ' ' -replace "`r|`n", ''

                if ($seen.Add($candidate)) {
                    $values += $candidate
                }
                if ($values.Count -ge $MaxCandidates) { break }
            }

            if ($values.Count -eq 0) { continue }

            $offset = $stream.Position
            $line = $property.Name + "`t" + ($values -join "`t") + "`n"
            $bytes = $utf8.GetBytes($line)
            $stream.Write($bytes, 0, $bytes.Length)

            $keyBytes = $utf8.GetBytes($property.Name)
            if ($keyBytes.Length -le 16) {
                $keyBuffer = New-Object byte[] 16
                [Array]::Copy($keyBytes, $keyBuffer, $keyBytes.Length)
                $offsetBytes = [BitConverter]::GetBytes([Int64]$offset)
                $lengthBytes = [BitConverter]::GetBytes([Int32]$bytes.Length)

                $indexStream.Write($keyBuffer, 0, $keyBuffer.Length)
                $indexStream.Write($offsetBytes, 0, $offsetBytes.Length)
                $indexStream.Write($lengthBytes, 0, $lengthBytes.Length)
            }

            $keyCount += 1
            $candidateCount += $values.Count
        }
    } finally {
        $stream.Dispose()
        $indexStream.Dispose()
    }

    [PSCustomObject]@{
        Keys = $keyCount
        Candidates = $candidateCount
        TSVBytes = (Get-Item $tsvPath).Length
        IndexBytes = (Get-Item $indexPath).Length
        TSV = $tsvPath
        Index = $indexPath
    }
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force
    }
}
