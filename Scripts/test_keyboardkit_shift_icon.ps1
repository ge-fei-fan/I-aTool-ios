$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$source = Get-Content -Path $keyboardSource -Raw

$iconFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "ios-icon") -File | Where-Object {
    $_.Length -eq 1725206 -or $_.Length -eq 3006912
})

$checks = [ordered]@{
    "shift icon source files exist" = (
        $iconFiles.Count -eq 2
    )
    "shift icon loads from keyboard bundle folder resource" = (
        $source.Contains("Bundle(for: KeyboardViewController.self)") -and
        $source.Contains('withExtension: "png"') -and
        $source.Contains('subdirectory: "ios-icon"')
    )
    "shift icon uses UIImage file loading for bundled png" = (
        $source.Contains("UIImage(contentsOfFile: url.path)") -and
        $source.Contains("Image(uiImage: image)")
    )
    "shift icon has system fallback" = (
        $source.Contains('fallbackSystemName') -and
        $source.Contains('Image(systemName: fallbackSystemName)')
    )
    "shift icon no longer uses SwiftUI named image path" = (
        -not $source.Contains("Image(imageName)") -and
        -not $source.Contains('return "ios-icon/大写图标"') -and
        -not $source.Contains('return "ios-icon/小写图标"')
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit shift icon checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit shift icon checks passed."
