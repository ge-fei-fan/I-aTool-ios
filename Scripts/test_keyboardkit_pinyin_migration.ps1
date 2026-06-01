$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyboardSource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewController.swift"
$legacySource = Join-Path $repoRoot "SimpaninKeyboard\KeyboardViewControllerLegacy.swift"
$engineSource = Join-Path $repoRoot "SimpaninKeyboard\PinyinInputEngine.swift"
$projectFile = Join-Path $repoRoot "Simpanin.xcodeproj\project.pbxproj"

$keyboard = Get-Content -Path $keyboardSource -Raw
$legacy = Get-Content -Path $legacySource -Raw
$engine = Get-Content -Path $engineSource -Raw
$project = Get-Content -Path $projectFile -Raw

$legacySourcesPattern = "KeyboardViewControllerLegacy.swift in Sources"

$checks = [ordered]@{
    "legacy keyboard implementation is backed up" = (
        (Test-Path $legacySource) -and
        $legacy.Contains("final class KeyboardViewController: UIInputViewController")
    )
    "active keyboard uses KeyboardKit controller" = (
        $keyboard.Contains("import KeyboardKit") -and
        $keyboard.Contains("final class KeyboardViewController: KeyboardInputViewController")
    )
    "active keyboard installs custom SwiftUI keyboard through KeyboardKit" = (
        $keyboard.Contains("override func viewWillSetupKeyboardView()") -and
        $keyboard.Contains("setupKeyboardView { [pinyinState] controller in") -and
        $keyboard.Contains("PinyinKeyboardView") -and
        -not $keyboard.Contains("UIHostingController<")
    )
    "active keyboard routes pinyin through extracted engine" = (
        $keyboard.Contains("private let pinyinState = PinyinKeyboardInputState()") -and
        $keyboard.Contains("@Published private(set) var engine = PinyinInputEngine()") -and
        $keyboard.Contains("engine.insertLetter") -and
        $keyboard.Contains("engine.candidates") -and
        $keyboard.Contains("engine.select")
    )
    "pinyin engine reuses existing providers and resources" = (
        $engine.Contains("private let candidateProvider = PinyinCandidateProvider()") -and
        $engine.Contains("private let associationProvider = PinyinAssociationProvider()") -and
        $engine.Contains("PinyinLexicon") -and
        $engine.Contains("PinyinAssociations")
    )
    "pinyin engine is UI independent" = (
        $engine.Contains("import Foundation") -and
        -not $engine.Contains("import UIKit") -and
        -not $engine.Contains("UIInputViewController")
    )
    "project references KeyboardKit package" = (
        $project.Contains('XCRemoteSwiftPackageReference "KeyboardKit"') -and
        $project.Contains("https://github.com/KeyboardKit/KeyboardKit.git") -and
        $project.Contains("kind = exactVersion;") -and
        $project.Contains("version = 10.1.4;")
    )
    "project compiles active keyboard and pinyin engine" = (
        $project.Contains("KeyboardViewController.swift in Sources") -and
        $project.Contains("PinyinInputEngine.swift in Sources")
    )
    "project keeps legacy file out of build sources" = (
        $project.Contains("KeyboardViewControllerLegacy.swift") -and
        -not $project.Contains($legacySourcesPattern)
    )
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($failed.Count -gt 0) {
    Write-Output "KeyboardKit pinyin migration checks failed:"
    $failed | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "KeyboardKit pinyin migration checks passed."
