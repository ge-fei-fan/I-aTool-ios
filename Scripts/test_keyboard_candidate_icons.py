#!/usr/bin/env python3
"""Regression checks for keyboard candidate bar utility icons."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def utility_items_block(source: str) -> str:
    match = re.search(
        r"let utilityItems: \[\(asset: KeyboardIconAsset, fallbackSystemName: String, label: String, dismissesKeyboard: Bool\)\] = \[(.*?)\n\s*\]",
        source,
        re.S,
    )
    return match.group(1) if match else ""


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    items = utility_items_block(source)

    checks = {
        "candidate icon size is 22pt": "private static let keyboardIconPointSize: CGFloat = 22" in source,
        "quick fill uses diversity icon": 'configureUtilityIconButton(utilityOverlayButton, asset: .diversity, fallbackSystemName: "person.2", accessibilityLabel: "Quick fill")' in source,
        "messages heart icon is first utility item": '(asset: .heart, fallbackSystemName: "heart", label: "Messages", dismissesKeyboard: false)' in items,
        "utility item list has five icons": items.count("(asset:") == 5,
        "heart icon precedes dictation": items.find('label: "Messages"') != -1 and items.find('label: "Messages"') < items.find('label: "Dictation"'),
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Keyboard candidate icon checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard candidate icon checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
