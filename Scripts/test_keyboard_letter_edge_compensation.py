#!/usr/bin/env python3
"""Regression checks for red letter-row edge compensation."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"
PREVIEW_SOURCE = REPO_ROOT / "docs" / "previews" / "keyboard-a-l-gap-preview.html"


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    preview = PREVIEW_SOURCE.read_text(encoding="utf-8")
    checks = {
        "letter row keeps proxy spacers for a and l": '[KeySpec(.spacer, widthUnit: 0.5, proxyKind: .character("a"))]' in source and '[KeySpec(.spacer, widthUnit: 0.5, proxyKind: .character("l"))]' in source,
        "proxy spacer buttons are tracked for theme updates": "private var proxySpacerButtons: [KeyboardProxySpacerButton] = []" in source,
        "proxy spacer buttons reset before rerender": "proxySpacerButtons.removeAll()" in source,
        "proxy spacer buttons get collected while building rows": "proxySpacerButtons.append(proxySpacer)" in source,
        "proxy spacer stores forwarded real key button": "weak var forwardedKeyButton: KeyboardKeyButton?" in source,
        "pending spacers resolve both preview source and forwarded key button": "pending.button.forwardedKeyButton = button" in source,
        "resolved spacers capture forwarded real key button immediately": "proxySpacer.forwardedKeyButton = previewSourceView" in source,
        "proxy spacer no longer stays visually transparent": "proxy spacer remains visually transparent" not in source and "button.applyAppearance(backgroundColor: proxySpacerBackground, shadowColor: shadowColor)" in source,
        "proxy spacer uses system red background": "private var proxySpacerBackground: UIColor {" in source and ".systemRed" in source,
        "dedicated edge compensation overlay is removed": "KeyboardLetterEdgeCompensationButton" not in source,
        "dedicated edge compensation button state is removed": "letterEdgeCompensationButtons" not in source,
        "proxy spacer preview binds through shared key-preview helper": "bindKeyPreviewEvents(" in source and "highlightedControlProvider:" in source,
        "proxy spacer uses a minimum visible preview duration": "minimumVisibleDuration: Self.proxySpacerPreviewMinimumVisibleDuration" in source,
        "preview hide can defer short-lived proxy previews": "minimumVisibleDuration: TimeInterval = 0" in source and "pendingKeyPreviewHideWorkItem" in source,
        "proxy spacer highlights forwarded real key on press": "highlightedControlProvider?()?.isHighlighted = true" in source,
        "proxy spacer removes forwarded real key highlight on release": "highlightedControlProvider?()?.isHighlighted = false" in source,
        "proxy spacer preview anchors to the forwarded real key": "proxySpacer?.previewSourceView ?? proxySpacer?.forwardedKeyButton" in source,
        "proxy spacer custom tracking path is removed": "func configurePreview(" not in source and "override func beginTracking(_ touch: UITouch, with event: UIEvent?)" not in source,
        "preview page keeps red gap keycaps": ".gap {" in preview and "#ff3b30" in preview,
        "preview page keeps real key preview anchoring": "data-source=\"[data-home-key='a']\"" in preview and "sourceFor(element)" in preview,
        "preview page simulates drag cancel and restore": "pointermove" in preview and "commitKey(element);" in preview,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Missing red letter edge compensation behavior:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard red letter edge compensation checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
