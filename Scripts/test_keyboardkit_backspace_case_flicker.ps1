$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw
$plainBackspaceHandler = [regex]::Match(
    $source,
    "private func handlePlainBackspacePreservingCase\(\) \{[\s\S]*?\n    \}"
).Value

$checks = [ordered]@{
    "plain backspace has a dedicated case-preserving handler" = (
        $plainBackspaceHandler.Contains("private func handlePlainBackspacePreservingCase()") -and
        $plainBackspaceHandler.Contains("controller?.textDocumentProxy.deleteBackward()")
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
        $plainBackspaceHandler.Contains("handlePlainBackspacePreservingCase()") -and
        $source.Contains("private var isManualUppercaseEnabled = false") -and
        -not ($plainBackspaceHandler -match "applyDefaultLowercaseIfNeeded|applyPinyinLowercaseState|setKeyboardCase")
    )
    "plain backspace does not change keyboard case" = (
        ($plainBackspaceHandler -match "private func handlePlainBackspacePreservingCase\(\) \{\s*controller\?\.textDocumentProxy\.deleteBackward\(\)\s*\}") -and
        $source.Contains("applyPreReleaseCaseStateIfNeeded(on: action)") -and
        -not ($source -match "if shouldConsumePreReleaseGesture\(on: action\) \{\s*applyPinyinLowercaseState\(\)")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit backspace case flicker checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit backspace case flicker checks passed."
