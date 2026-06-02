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
        $source.Contains("Text(pinyinState.displayText.isEmpty ?") -and
        $source.Contains("pinyinState.hasComposition")
    )
    "candidate strip has toggle expand button" = (
        $source.Contains("candidateExpandButton") -and
        $source.Contains('pinyinState.isCandidatePageVisible ? "chevron.up" : "chevron.down"') -and
        $source.Contains("pinyinState.isCandidatePageVisible.toggle()")
    )
    "candidate expand button has larger touch target" = (
        $source.Contains("candidateExpandHitWidth: CGFloat = 48") -and
        $source.Contains("candidateExpandHitHeight: CGFloat = 44") -and
        $source.Contains(".frame(width: PinyinKeyboardMetrics.candidateExpandHitWidth, height: PinyinKeyboardMetrics.candidateExpandHitHeight)") -and
        $source.Contains(".contentShape(Rectangle())")
    )
    "candidate strip keeps composition visible while expanded" = (
        $source.Contains("if pinyinState.isCandidatePageVisible {") -and
        $source.Contains("expandedCompositionArea") -and
        $source.Contains("candidateInputArea") -and
        $source.Contains("private var expandedCompositionArea: some View") -and
        $source.Contains(".allowsHitTesting(!pinyinState.isCandidatePageVisible)")
    )
    "candidate strip renders selectable candidates" = (
        $source.Contains("ForEach(Array(pinyinState.candidates.prefix(candidateBatchSize).enumerated()), id: \.element.id)") -and
        $source.Contains("PinyinCandidateButton")
    )
    "candidate strip whitespace can start horizontal drag" = (
        $source.Contains("private var migratedCandidateStrip: some View") -and
        $source.Contains(".frame(minWidth: 0, alignment: .leading)") -and
        $source.Contains(".contentShape(Rectangle())") -and
        $source.Contains(".scrollDisabled(pinyinState.candidates.count <= 3)")
    )
    "expanded candidate page starts below pinyin composition bar" = (
        $source.Contains(".overlay(alignment: .top) {") -and
        $source.Contains("expandedCandidateOverlay") -and
        $source.Contains("PinyinExpandedCandidateOverlay") -and
        $source.Contains("expandedCandidateOverlayTopOffset") -and
        $source.Contains(".padding(.top, PinyinKeyboardMetrics.expandedCandidateOverlayTopOffset)") -and
        $source.Contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)") -and
        $source.Contains(".clipped()") -and
        -not $source.Contains("GeometryReader { proxy in") -and
        -not $source.Contains("expandedCandidateOverlayHeight(for:")
    )
    "expanded candidate page does not show pinyin text" = (
        $source.Contains("private var collapseHeader: some View") -and
        -not $source.Contains("Text(pinyinState.displayText)")
    )
    "expanded candidate page has independent collapse control" = (
        $source.Contains("private var collapseHeader: some View") -and
        $source.Contains("pinyinState.isCandidatePageVisible = false") -and
        $source.Contains('"chevron.up"')
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
    "candidate page uses top-down transition animation" = (
        $source.Contains(".transition(.move(edge: .top).combined(with: .opacity))") -and
        $source.Contains(".animation(.easeOut(duration: PinyinKeyboardMetrics.candidatePanelAnimationDuration), value: pinyinState.isCandidatePageVisible)") -and
        $source.Contains("withAnimation(.easeOut(duration: PinyinKeyboardMetrics.candidatePanelAnimationDuration))")
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit candidate bar checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit candidate bar checks passed."
