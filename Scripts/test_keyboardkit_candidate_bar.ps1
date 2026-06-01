$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw

$checks = [ordered]@{
    "active keyboard uses KeyboardKit setupKeyboardView lifecycle" = (
        $source.Contains("override func viewWillSetupKeyboardView()") -and
        $source.Contains("setupKeyboardView { controller in") -and
        -not $source.Contains("UIHostingController(rootView:") -and
        -not $source.Contains("addChild(hostingController)") -and
        -not $source.Contains("view.addSubview(hostingController.view)")
    )
    "active keyboard renders migrated candidate strip" = (
        $source.Contains("private var candidateInputArea: some View") -and
        $source.Contains("private var migratedCandidateStrip: some View")
    )
    "candidate strip shows pinyin composition text" = (
        $source.Contains('Text(engine.displayText.isEmpty ? "中文拼音" : engine.displayText)') -and
        $source.Contains("engine.hasComposition")
    )
    "candidate strip has old-style expand button" = (
        $source.Contains("candidateExpandButton") -and
        $source.Contains("chevron.down")
    )
    "candidate strip renders selectable candidates" = (
        $source.Contains("ForEach(Array(engine.candidates.enumerated()), id: \.element.id)") -and
        $source.Contains("selectCandidate(candidate)")
    )
    "expanded candidate page is restored" = (
        $source.Contains("private var candidateExpandedPage: some View") -and
        $source.Contains("CandidateFlowLayout") -and
        $source.Contains("isCandidatePageVisible")
    )
    "candidate page hides when composition is committed or cleared" = (
        $source.Contains("isCandidatePageVisible = false") -and
        $source.Contains("commitCompositionIfNeeded()")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit candidate bar checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit candidate bar checks passed."
