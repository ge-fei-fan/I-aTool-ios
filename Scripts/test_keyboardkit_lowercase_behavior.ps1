$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$engineSource = Join-Path $repoRoot "SimpaninKeyboard\PinyinInputEngine.swift"
$source = Get-Content -Path $keyboardSource -Raw
$engine = Get-Content -Path $engineSource -Raw
$directPinyinCharacterCase = [regex]::Match(
    $source,
    "case \.character\(let value\) where isPinyinLetter\(value\):[\s\S]*?case \.backspace where"
).Value
$releasePinyinCharacterCase = [regex]::Match(
    $source,
    "case \.character\(let value\):[\s\S]*?case \.backspace:"
).Value

$checks = [ordered]@{
    "keyboard starts in lowercase" = (
        $source.Contains("override func viewDidLoad()") -and
        $source.Contains("setKeyboardCase(.lowercased)")
    )
    "pinyin action handler controls KeyboardInputViewController case" = (
        $source.Contains("private weak var controller: KeyboardInputViewController?") -and
        $source.Contains("controller: KeyboardInputViewController")
    )
    "shift is handled manually instead of KeyboardKit auto-capitalization" = (
        $source.Contains("case .shift(let keyboardCase):") -and
        $source.Contains("handleShift(keyboardCase)") -and
        $source.Contains("private func handleShift(_ keyboardCase: Keyboard.KeyboardCase)")
    )
    "manual uppercase state is tracked" = (
        $source.Contains("private var isManualUppercaseEnabled = false") -and
        $source.Contains("isManualUppercaseEnabled = true") -and
        $source.Contains("isManualUppercaseEnabled = false")
    )
    "standard non-shift paths are forced back to lowercase by default" = (
        $source.Contains("handleStandardAction(gesture, on: action)") -and
        $source.Contains("private func handleStandardAction(_ gesture: Keyboard.Gesture, on action: KeyboardAction)") -and
        $source.Contains("if !isManualUppercaseEnabled {") -and
        $source.Contains("controller?.setKeyboardCase(.lowercased)")
    )
    "pinyin letters preserve typed case for display and direct commit" = (
        $source.Contains("engine.insertLetter(letter)") -and
        -not $source.Contains("engine.insertLetter(letter.lowercased())") -and
        $engine.Contains("compositionBuffer += letter") -and
        -not $engine.Contains("compositionBuffer += letter.lowercased()")
    )
    "pinyin character input does not force keyboard back to lowercase" = (
        $directPinyinCharacterCase.Contains("pinyinState.insertLetter(value)") -and
        -not ($directPinyinCharacterCase -match "applyLowercaseState|setKeyboardCase\(\.lowercased\)") -and
        $releasePinyinCharacterCase.Contains("pinyinState.insertLetter(value)") -and
        -not ($releasePinyinCharacterCase -match "applyLowercaseState|setKeyboardCase\(\.lowercased\)")
    )
    "pinyin candidate lookup remains lowercase-normalized" = (
        $engine.Contains("return candidateProvider.candidates(for: compositionBuffer).map") -and
        $engine.Contains("private static func normalizedKey(_ value: String)") -and
        $engine.Contains("String(value.lowercased().filter")
    )
    "primary action restores lowercase after send or return" = (
        $source.Contains("case .primary:") -and
        ($source -match "case \.primary:[\s\S]*?handleStandardAction\(gesture, on: action\)[\s\S]*?applyLowercaseState\(\)")
    )
    "plain backspace restores lowercase" = (
        $source.Contains("private func handlePlainBackspaceLowercasing()") -and
        ($source -match "private func handlePlainBackspaceLowercasing\(\) \{\s*controller\?\.textDocumentProxy\.deleteBackward\(\)\s*applyLowercaseState\(\)\s*\}")
    )
    "shared lowercase helper clears manual uppercase state" = (
        ($source -match "private func applyLowercaseState\(\) \{\s*isManualUppercaseEnabled = false\s*controller\?\.setKeyboardCase\(\.lowercased\)\s*\}")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit lowercase behavior checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit lowercase behavior checks passed."
