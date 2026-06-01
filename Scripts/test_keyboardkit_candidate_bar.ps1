$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw

$checks = [ordered]@{
    "active keyboard uses KeyboardKit setupKeyboardView lifecycle" = (
        $source.Contains("override func viewWillSetupKeyboardView()") -and
        $source.Contains("setupKeyboardView { [pinyinState] controller in") -and
        -not $source.Contains("UIHostingController(rootView:") -and
        -not $source.Contains("addChild(hostingController)") -and
        -not $source.Contains("view.addSubview(hostingController.view)")
    )
    "active keyboard renders migrated candidate strip" = (
        $source.Contains("private var candidateInputArea: some View") -and
        $source.Contains("private var migratedCandidateStrip: some View")
    )
    "candidate strip shows pinyin composition text" = (
        $source.Contains('Text(pinyinState.displayText.isEmpty ? "中文拼音" : pinyinState.displayText)') -and
        $source.Contains("pinyinState.hasComposition")
    )
    "candidate strip has toggle expand button" = (
        $source.Contains("candidateExpandButton") -and
        $source.Contains('pinyinState.isCandidatePageVisible ? "chevron.up" : "chevron.down"') -and
        $source.Contains("pinyinState.isCandidatePageVisible.toggle()")
    )
    "candidate strip remains visible and interactive while expanded" = (
        -not $source.Contains(".opacity(pinyinState.isCandidatePageVisible ? 0 : 1)") -and
        -not $source.Contains(".allowsHitTesting(!pinyinState.isCandidatePageVisible)")
    )
    "candidate strip renders selectable candidates" = (
        $source.Contains("ForEach(Array(pinyinState.candidates.enumerated()), id: \.element.id)") -and
        $source.Contains("PinyinCandidateButton")
    )
    "expanded candidate page covers only the key area" = (
        $source.Contains(".overlay(alignment: .top) {") -and
        $source.Contains("expandedCandidateOverlay") -and
        $source.Contains("PinyinKeyboardMetrics.candidateToolbarHeight") -and
        $source.Contains(".padding(.top, PinyinKeyboardMetrics.candidateToolbarHeight)") -and
        $source.Contains(".clipped()") -and
        -not $source.Contains("GeometryReader { proxy in") -and
        -not $source.Contains("expandedCandidateOverlayHeight(for:") -and
        -not $source.Contains(".frame(maxHeight: .infinity, alignment: .top)")
    )
    "expanded candidate page keeps flow layout" = (
        $source.Contains("private struct PinyinExpandedCandidateOverlay: View") -and
        $source.Contains("CandidateFlowLayout") -and
        $source.Contains("pinyinState.isCandidatePageVisible")
    )
    "candidate page hides when composition is committed or cleared" = (
        $source.Contains("isCandidatePageVisible = false") -and
        $source.Contains("commitCompositionAsText()")
    )
    "candidate page avoids full keyboard transition animation" = (
        -not $source.Contains(".transition(.move(edge: .top).combined(with: .opacity))") -and
        -not $source.Contains(".animation(.easeInOut(duration: 0.22), value: pinyinState.isCandidatePageVisible)")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit candidate bar checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit candidate bar checks passed."
