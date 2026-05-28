#!/usr/bin/env python3
"""Regression checks for keyboard candidate bar utility icons."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def utility_items_block(source: str) -> str:
    match = re.search(
        r"let utilityItems: \[\(.*?\)\] = \[(.*?)\n\s*\]",
        source,
        re.S,
    )
    return match.group(1) if match else ""


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    items = utility_items_block(source)

    checks = {
        "candidate icon size is 24pt": "private static let keyboardIconPointSize: CGFloat = 24" in source,
        "leading function icon uses diversity icon": 'configureUtilityIconButton(utilityOverlayButton, asset: .diversity, fallbackSystemName: "person.2", accessibilityLabel: "Function")' in source,
        "leading function icon is disabled": "utilityOverlayButton.isUserInteractionEnabled = false" in source,
        "leading function icon does not open quick fill": "utilityOverlayButton.addAction" not in source,
        "quick fill heart icon is first utility item": '(asset: .heart, fallbackSystemName: "heart", label: "Quick fill", dismissesKeyboard: false, opensQuickFill: true, opensTranslation: false)' in items,
        "utility item list has five icons": items.count("(asset:") == 5,
        "total utility toolbar has six icons": source.count("utilityOverlayIconButtons.append(") == 2 and items.count("(asset:") == 5,
        "utility toolbar keeps equal spacing": "utilityOverlayStack.distribution = .equalSpacing" in source,
        "utility toolbar uses 5pt horizontal insets": "utilityOverlayStack.leadingAnchor.constraint(equalTo: utilityOverlayView.leadingAnchor, constant: 5)" in source
        and "utilityOverlayStack.trailingAnchor.constraint(equalTo: utilityOverlayView.trailingAnchor, constant: -5)" in source,
        "utility icon button touch size stays 34 by 32": "button.widthAnchor.constraint(equalToConstant: 34).isActive = true" in source
        and "button.heightAnchor.constraint(equalToConstant: 32).isActive = true" in source,
        "heart icon precedes translate": items.find('label: "Quick fill"') != -1 and items.find('label: "Quick fill"') < items.find('label: "Translate"'),
        "heart icon opens quick fill": "if item.opensQuickFill" in source and "self?.handleUtilityFillButtonTap()" in source,
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
