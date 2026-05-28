$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw

$checks = [ordered]@{
    "quick fill header height constant is 36pt" = $source.Contains("private static let quickFillHeaderHeight: CGFloat = 36")
    "quick fill header side slot width constant is 44pt" = $source.Contains("private static let quickFillHeaderSideSlotWidth: CGFloat = 44")
    "quick fill header tab spacing constant is 28pt" = $source.Contains("private static let quickFillHeaderTabSpacing: CGFloat = 28")
    "quick fill header bottom spacing constant is 8pt" = $source.Contains("private static let quickFillHeaderBottomSpacing: CGFloat = 8")
    "quick fill tab indicator uses 20 by 3 sizing" = $source.Contains("private static let quickFillTabIndicatorWidth: CGFloat = 20") -and $source.Contains("private static let quickFillTabIndicatorHeight: CGFloat = 3")
    "quick fill back icon size is reduced to 20pt" = $source.Contains("private static let quickFillBackIconPointSize: CGFloat = 20")
    "quick fill back button touch size is 36 by 36" = $source.Contains("private static let quickFillBackButtonWidth: CGFloat = 36") -and $source.Contains("private static let quickFillBackButtonHeight: CGFloat = 36")
    "quick fill top bar height uses shared constant" = $source.Contains("quickFillTopBar.heightAnchor.constraint(equalToConstant: Self.quickFillHeaderHeight)")
    "quick fill content starts just below header" = $source.Contains("candidatePageScrollTopToQuickFillTopBarConstraint = candidatePageScrollView.topAnchor.constraint(equalTo: quickFillTopBar.bottomAnchor, constant: Self.quickFillHeaderBottomSpacing)")
    "quick fill header centers tab stack" = $source.Contains("tabStack.centerXAnchor.constraint(equalTo: header.centerXAnchor)") -and $source.Contains("tabStack.leadingAnchor.constraint(greaterThanOrEqualTo: header.leadingAnchor, constant: Self.quickFillHeaderSideSlotWidth)") -and $source.Contains("tabStack.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -Self.quickFillHeaderSideSlotWidth)")
    "quick fill header no longer relies on asymmetric margins or trailing spacer" = -not $source.Contains("header.layoutMargins = UIEdgeInsets(top: 0, left: 44, bottom: 0, right: 12)") -and -not $source.Contains("trailingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true")
    "quick fill tabs use shared spacing and indicator constants" = $source.Contains("tabStack.spacing = Self.quickFillHeaderTabSpacing") -and $source.Contains("indicator.heightAnchor.constraint(equalToConstant: Self.quickFillTabIndicatorHeight).isActive = true") -and $source.Contains("indicator.widthAnchor.constraint(equalToConstant: Self.quickFillTabIndicatorWidth).isActive = true")
    "theme refresh rerenders quick fill panel when visible" = $source.Contains("if isQuickFillPanelVisible {`n            renderQuickFillPanel()`n        } else {`n            renderCandidatePageIfNeeded()`n        }")
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "Quick fill header style checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "Quick fill header style checks passed."
