#!/usr/bin/env python3
"""Regression checks for keyboard key hit testing and row gap routing."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    checks = {
        "row touch router class": "private final class KeyboardRowStack" in source,
        "row stack used for keyboard rows": "let rowStack = KeyboardRowStack()" in source,
        "nearest control routing": "nearestTouchTarget(at point: CGPoint)" in source,
        "expanded key hit testing": "override func point(inside point: CGPoint, with event: UIEvent?) -> Bool" in source,
        "row hit testing avoids point parameter shadowing": "isUserInteractionEnabled, point(inside: point, with: event)" not in source,
        "key touch outset configured": "button.touchOutset = Self.keyTouchOutset" in source,
        "space long press keeps normal touches": "recognizer.cancelsTouchesInView = false" in source,
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
