#!/usr/bin/env python3
"""Regression checks for keyboard key hit testing and row gap routing."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    checks = {
        "root touch router class": "private final class KeyboardRootStack" in source,
        "root stack uses keyboard touch router": "private let rootStack = KeyboardRootStack()" in source,
        "root stack touch outset configured": "rootStack.touchTargetOutset = Self.keyTouchOutset" in source,
        "root stack routes screen-edge touches to rows": "nearestKeyboardRow(at point: CGPoint)" in source,
        "root stack searches nested keyboard rows": "collectKeyboardRows(from view: UIView)" in source,
        "root stack converts nested row frames before distance checks": "convert(row.bounds, from: row)" in source,
        "root stack forwards edge hits into row hit testing": "return row.hitTest(convert(point, to: row), with: event)" in source,
        "row touch router class": "private final class KeyboardRowStack" in source,
        "row stack used for keyboard rows": "let rowStack = KeyboardRowStack()" in source,
        "nearest control routing": "nearestTouchTarget(at point: CGPoint)" in source,
        "expanded key hit testing": "override func point(inside point: CGPoint, with event: UIEvent?) -> Bool" in source,
        "row hit testing avoids point parameter shadowing": "isUserInteractionEnabled, point(inside: point, with: event)" not in source,
        "key touch outset configured": "button.touchOutset = Self.keyTouchOutset" in source,
        "space long press keeps normal touches": "recognizer.cancelsTouchesInView = false" in source,
        "key preview uses approved 52 by 84 size": "CGSize(width: 52, height: 84)" in source,
        "key preview body is 72pt tall": "private var tailHeight: CGFloat { 12 }" in source,
        "key preview tail can track edge keys": "var tailCenterX: CGFloat = 26" in source,
        "key preview tail tracks pressed key center": "keyPreviewView.tailCenterX = min(max(buttonFrame.midX - originX, minTailCenterX), maxTailCenterX)" in source,
        "key preview letter is raised 5pt": "label.frame = bubbleRect.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: -5)" in source,
        "proxy spacer stores preview and forwarded key sources": "weak var previewSourceView: UIView?" in source and "weak var forwardedKeyButton: KeyboardKeyButton?" in source,
        "proxy spacer uses shared preview binding": "bindKeyPreviewEvents(" in source and "sourceViewProvider:" in source and "highlightedControlProvider:" in source,
        "proxy spacer forwards preview anchor to real key source": "proxySpacer?.previewSourceView ?? proxySpacer?.forwardedKeyButton" in source,
        "proxy spacer shares preview exit events through helper": "[.touchDragExit, .touchUpInside, .touchUpOutside, .touchCancel]" in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Missing keyboard touch routing behavior:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard touch routing checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
