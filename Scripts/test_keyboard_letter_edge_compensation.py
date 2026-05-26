#!/usr/bin/env python3
"""Regression checks for transparent letter-row edge compensation."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    checks = {
        "letter row keeps proxy spacers for a and l": '[KeySpec(.spacer, widthUnit: 0.5, proxyKind: .character("a"))]' in source and '[KeySpec(.spacer, widthUnit: 0.5, proxyKind: .character("l"))]' in source,
        "proxy spacer stores forwarded real key button": "weak var forwardedKeyButton: KeyboardKeyButton?" in source,
        "pending spacers resolve both preview source and forwarded key button": "pending.button.forwardedKeyButton = button" in source,
        "resolved spacers capture forwarded real key button immediately": "proxySpacer.forwardedKeyButton = previewSourceView" in source,
        "proxy spacer remains visually transparent": "backgroundColor = .clear" in source and "private final class KeyboardProxySpacerButton: UIButton" in source,
        "dedicated edge compensation overlay is removed": "KeyboardLetterEdgeCompensationButton" not in source,
        "dedicated edge compensation button state is removed": "letterEdgeCompensationButtons" not in source,
        "proxy spacer highlights forwarded real key on press": "forwardedKeyButton?.isHighlighted = true" in source,
        "proxy spacer removes forwarded real key highlight on release": "forwardedKeyButton?.isHighlighted = false" in source,
        "proxy spacer preview anchors to the forwarded real key": "onPreviewBegan?(previewSourceView ?? forwardedKeyButton ?? self, previewText)" in source,
        "proxy spacer tracking still handles drag exit": "override func continueTracking(_ touch: UITouch, with event: UIEvent?)" in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Missing transparent letter edge compensation behavior:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard transparent letter edge compensation checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
