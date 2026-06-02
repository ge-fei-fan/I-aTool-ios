$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$engineSource = Join-Path $repoRoot "SimpaninKeyboard\PinyinInputEngine.swift"
$keyboard = Get-Content -Path $keyboardSource -Raw
$engine = Get-Content -Path $engineSource -Raw
$engineInsertLetter = [regex]::Match(
    $engine,
    "mutating func insertLetter\(_ letter: String\) \{[\s\S]*?\n    \}"
).Value
$engineCommitText = [regex]::Match(
    $engine,
    "mutating func commitCompositionAsText\(\) -> String\? \{[\s\S]*?\n    \}"
).Value
$engineSelect = [regex]::Match(
    $engine,
    "mutating func select\(_ candidate: Candidate\) -> String\? \{[\s\S]*?\n    \}"
).Value
$candidateButtonAction = [regex]::Match(
    $keyboard,
    "private struct PinyinCandidateButton: View \{[\s\S]*?Button \{[\s\S]*?\n        \} label:"
).Value
$canHandleAction = [regex]::Match(
    $keyboard,
    "func canHandle\(_ gesture: Keyboard\.Gesture, on action: KeyboardAction\) -> Bool \{[\s\S]*?\n    \}"
).Value
$shouldHandlePinyinAction = [regex]::Match(
    $keyboard,
    "private func shouldHandlePinyinAction\(_ action: KeyboardAction\) -> Bool \{[\s\S]*?\n    \}"
).Value
$shouldRouteLetterToPinyin = [regex]::Match(
    $keyboard,
    "private func shouldRouteLetterToPinyin\(_ value: String\) -> Bool \{[\s\S]*?\n    \}"
).Value

$checks = [ordered]@{
    "keyboard state passes raw typed pinyin letters into engine" = (
        $keyboard.Contains("func insertLetter(_ letter: String)") -and
        $keyboard.Contains("engine.insertLetter(letter)") -and
        -not $keyboard.Contains("engine.insertLetter(letter.lowercased())")
    )
    "pinyin letters are handled by custom action handler in Chinese mode" = (
        $canHandleAction.Contains("if shouldHandlePinyinAction(action) {") -and
        $canHandleAction.Contains("return true") -and
        $keyboard.Contains("@Published var isChineseInputEnabled = true") -and
        $keyboard.Contains("func toggleChineseInput()") -and
        $keyboard.Contains("pinyinState.toggleChineseInput()") -and
        $shouldRouteLetterToPinyin.Contains("pinyinState.isChineseInputEnabled && isPinyinLetter(value)") -and
        $shouldHandlePinyinAction.Contains("case .character(let value):") -and
        $shouldHandlePinyinAction.Contains("return shouldRouteLetterToPinyin(value)")
    )
    "Chinese English toggle key is inserted after reduced 123 key" = (
        $keyboard.Contains("languageSwitchActionName") -and
        $keyboard.Contains(".custom(named: Self.languageSwitchActionName)") -and
        $keyboard.Contains("PinyinLanguageSwitchButtonContent(isChineseInputEnabled: pinyinState.isChineseInputEnabled)") -and
        $keyboard.Contains("guard item.action == .keyboardType(.numeric) else { return item }") -and
        $keyboard.Contains("return item.withWidth(.inputPercentage(0.88))") -and
        $keyboard.Contains("layout.itemRows.insert(languageSwitchItem(height: CGFloat(layout.idealItemHeight)), after: .keyboardType(.numeric))") -and
        $keyboard.Contains("Text(isChineseInputEnabled ?")
    )
    "pinyin engine stores raw typed letter casing" = (
        $engineInsertLetter.Contains("compositionBuffer += letter") -and
        -not $engineInsertLetter.Contains("compositionBuffer += letter.lowercased()")
    )
    "candidate lookup still uses the composition buffer through normalized provider" = (
        $engine.Contains("return candidateProvider.candidates(for: compositionBuffer).map") -and
        $engine.Contains("func candidates(for pinyin: String)") -and
        $engine.Contains("let key = Self.normalizedKey(pinyin)") -and
        $engine.Contains("String(value.lowercased().filter")
    )
    "direct return commits displayed mixed-case pinyin text" = (
        $engineCommitText.Contains("let text = displayText") -and
        $engineCommitText.Contains("return text")
    )
    "complete selected composition records selection on return commit" = (
        $engineCommitText.Contains("if compositionBuffer.isEmpty,") -and
        $engineCommitText.Contains("selectedSegments.allSatisfy(\.recordsSelection)") -and
        $engineCommitText.Contains("candidateProvider.recordSelection(text, for: committedPinyin)")
    )
    "candidate selection consumes original-case pinyin span" = (
        $engine.Contains("let consumedPinyin = String(compositionBuffer[..<end])") -and
        $engine.Contains("pinyin: consumedPinyin")
    )
    "partial candidate selection keeps selected text in composition" = (
        $engineSelect.Contains("selectedSegments.append(SelectedSegment(") -and
        $engineSelect.Contains("return nil") -and
        -not $engineSelect.Contains("return committedText") -and
        -not $engineSelect.Contains("selectedSegments.removeAll()") -and
        -not $engineSelect.Contains("associationContext = limitedAssociationContext(committedText)")
    )
    "complete candidate selection commits immediately" = (
        $engineSelect.Contains("if compositionBuffer.isEmpty {") -and
        $engineSelect.Contains("return commitCompositionAsText()")
    )
    "candidate button inserts only when select returns committed text" = (
        $candidateButtonAction.Contains("pinyinState.select(candidate)") -and
        $candidateButtonAction.Contains("if let committedText = pinyinState.select(candidate)") -and
        $candidateButtonAction.Contains("insertText(committedText)") -and
        -not $candidateButtonAction.Contains("pinyinState.isCandidatePageVisible = false")
    )
    "deleting a selected segment restores its original-case pinyin" = (
        $engine.Contains("compositionBuffer = segment.pinyin")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit pinyin case behavior checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit pinyin case behavior checks passed."
