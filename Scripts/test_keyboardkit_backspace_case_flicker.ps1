$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw

$checks = [ordered]@{
    "plain backspace has a dedicated case-preserving handler" = (
        $source.Contains("private func handlePlainBackspacePreservingCase()") -and
        $source.Contains("controller?.textDocumentProxy.deleteBackward()")
    )
    "action backspace without pinyin avoids KeyboardKit standard handler" = (
        $source.Contains("case .backspace where pinyinState.hasComposition:") -and
        ($source -match "case \.backspace:\s*handlePlainBackspacePreservingCase\(\)")
    )
    "release backspace without pinyin avoids standard action path" = (
        ($source -match "guard pinyinState\.hasComposition else \{\s*handlePlainBackspacePreservingCase\(\)\s*return\s*\}")
    )
    "backspace pre-release gestures are consumed to avoid default case refresh" = (
        ($source -match "case \.backspace:\s*return true")
    )
    "plain backspace preserves manual uppercase state" = (
        $source.Contains("handlePlainBackspacePreservingCase()") -and
        $source.Contains("applyDefaultLowercaseIfNeeded()") -and
        $source.Contains("if !isManualUppercaseEnabled {")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit backspace case flicker checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit backspace case flicker checks passed."