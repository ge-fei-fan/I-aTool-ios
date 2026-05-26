#!/usr/bin/env python3
"""Regression checks for letter-row edge compensation buttons."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    checks = {
        "edge compensation buttons are stored separately": "private var letterEdgeCompensationButtons: [KeyboardLetterEdgeCompensationButton] = []" in source,
        "edge compensation buttons are removed before rerender": "removeLetterEdgeCompensationButtons()" in source,
        "edge compensation buttons install from preview source map": "installLetterEdgeCompensationButtons(rowStack: rowStack, previewSourceButtonsByCharacter: previewSourceButtonsByCharacter)" in source,
        "left edge compensation stretches to screen edge": "leftButton.leadingAnchor.constraint(equalTo: view.leadingAnchor)" in source and "leftButton.trailingAnchor.constraint(equalTo: aButton.leadingAnchor)" in source,
        "right edge compensation stretches to screen edge": "rightButton.leadingAnchor.constraint(equalTo: lButton.trailingAnchor)" in source and "rightButton.trailingAnchor.constraint(equalTo: view.trailingAnchor)" in source,
        "preview still anchors to the real a key": 'configureLetterEdgeCompensationButton(leftButton, keyKind: .character("a"), previewSourceView: aButton)' in source,
        "preview still anchors to the real l key": 'configureLetterEdgeCompensationButton(rightButton, keyKind: .character("l"), previewSourceView: lButton)' in source,
        "dedicated edge compensation button class exists": "private final class KeyboardLetterEdgeCompensationButton: UIButton" in source,
        "edge compensation uses a dedicated 16pt visible strip": "private static let letterEdgeCompensationVisibleWidth: CGFloat = 16" in source,
        "left edge strip hugs the inner edge": "backgroundPlate.frame = CGRect(x: bounds.width - stripWidth, y: 0, width: stripWidth, height: bounds.height)" in source,
        "right edge strip hugs the inner edge": "backgroundPlate.frame = CGRect(x: 0, y: 0, width: stripWidth, height: bounds.height)" in source,
        "edge compensation appearance is themed": "button.applyAppearance(backgroundColor: keyBackground, shadowColor: shadowColor)" in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Missing letter edge compensation behavior:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard letter edge compensation checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
