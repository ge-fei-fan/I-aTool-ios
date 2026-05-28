$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw
$bringToFrontMatches = [regex]::Matches(
    $source,
    [regex]::Escape("candidatePageView.bringSubviewToFront(candidatePageCollapseButton)")
).Count

$checks = [ordered]@{
    "quick fill show and render paths both lift back button above scroll layer" = $bringToFrontMatches -eq 2
    "quick fill back button layering comment exists" = $source.Contains("Keep the back button above the full-height quick fill scroll view so it can receive taps.")
    "quick fill back icon uses dedicated 20pt size" = $source.Contains("private static let quickFillBackIconPointSize: CGFloat = 20") -and $source.Contains('button.setImage(keyboardIcon(.back, fallbackSystemName: "chevron.left", pointSize: Self.quickFillBackIconPointSize), for: .normal)')
    "quick fill top bar is fixed outside scroll content" = $source.Contains("private let quickFillTopBar = UIView()") -and $source.Contains("candidatePageView.addSubview(quickFillTopBar)")
    "quick fill scroll view starts below fixed top bar" = $source.Contains("candidatePageScrollTopToQuickFillTopBarConstraint = candidatePageScrollView.topAnchor.constraint(equalTo: quickFillTopBar.bottomAnchor, constant: Self.quickFillHeaderBottomSpacing)") -and $source.Contains("candidatePageScrollTopToQuickFillTopBarConstraint?.isActive = visible")
    "quick fill header is rendered into fixed top bar" = $source.Contains("renderQuickFillTopBar()") -and $source.Contains("quickFillTopBar.addSubview(header)")
    "quick fill header is not in scroll content" = -not $source.Contains("candidatePageStack.addArrangedSubview(makeQuickFillHeader())")
    "quick fill empty state shows 暂无数据 text" = $source.Contains('label.text = "暂无数据"') -and $source.Contains("label.font = .systemFont(ofSize: 14, weight: .regular)") -and $source.Contains("label.textColor = secondaryText")
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "Quick fill back button regression checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "Quick fill back button regression checks passed."
