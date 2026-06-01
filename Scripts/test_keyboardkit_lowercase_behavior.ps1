$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw

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
    "pinyin letters remain normalized for candidate lookup" = (
        $source.Contains("engine.insertLetter(letter.lowercased())")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit lowercase behavior checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit lowercase behavior checks passed."
