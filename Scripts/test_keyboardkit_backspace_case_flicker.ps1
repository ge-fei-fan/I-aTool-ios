$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw
$plainBackspaceHandler = [regex]::Match(
    $source,
    "private func handlePlainBackspaceLowercasing\(\) \{[\s\S]*?\n    \}"
).Value

$checks = [ordered]@{
    "plain backspace has a dedicated lowercase-restoring handler" = (
        $plainBackspaceHandler.Contains("private func handlePlainBackspaceLowercasing()") -and
        $plainBackspaceHandler.Contains("controller?.textDocumentProxy.deleteBackward()")
    )
    "action backspace without pinyin avoids KeyboardKit standard handler" = (
        $source.Contains("case .backspace where pinyinState.hasComposition:") -and
        ($source -match "case \.backspace:\s*handlePlainBackspaceLowercasing\(\)")
    )
    "release backspace without pinyin avoids standard action path" = (
        ($source -match "guard pinyinState\.hasComposition else \{\s*handlePlainBackspaceLowercasing\(\)\s*return\s*\}")
    )
    "backspace pre-release gestures are consumed to avoid default case refresh" = (
        ($source -match "case \.backspace:\s*return true") -and
        -not ($source -match "if shouldConsumePreReleaseGesture\(on: action\) \{\s*applyPinyinLowercaseState\(\)")
    )
    "plain backspace clears manual uppercase state" = (
        $plainBackspaceHandler.Contains("handlePlainBackspaceLowercasing()") -and
        $source.Contains("private var isManualUppercaseEnabled = false") -and
        $plainBackspaceHandler.Contains("applyLowercaseState()")
    )
    "plain backspace restores lowercase without KeyboardKit standard action" = (
        ($plainBackspaceHandler -match "private func handlePlainBackspaceLowercasing\(\) \{\s*controller\?\.textDocumentProxy\.deleteBackward\(\)\s*applyLowercaseState\(\)\s*\}") -and
        -not ($source -match "case \.backspace:\s*standardActionHandler\.handle\(action\)") -and
        -not ($source -match "guard pinyinState\.hasComposition else \{\s*handleStandardAction\(gesture, on: action\)")
    )
    "lowercase state helper resets manual uppercase flag" = (
        ($source -match "private func applyLowercaseState\(\) \{\s*isManualUppercaseEnabled = false\s*controller\?\.setKeyboardCase\(\.lowercased\)\s*\}")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit backspace case flicker checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit backspace case flicker checks passed."
