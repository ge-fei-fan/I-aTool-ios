#!/usr/bin/env python3
"""Regression checks for letter keyboard key sizing and third-row layout."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start == -1:
        return ""
    brace = source.find("{", start)
    if brace == -1:
        return ""

    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    return ""


def row3_definition(source: str) -> str:
    match = re.search(r"let row3 = (.*?)\n\s*let row4", source, re.S)
    return match.group(1).strip() if match else ""


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    row3 = row3_definition(source)
    width_helper = function_body(source, "private func usesLetterKeyWidth(for kind: KeyKind) -> Bool")

    checks = {
        "letter third row keeps shift pinned left": row3.startswith("[KeySpec(.shift), KeySpec(.spacer, widthUnit: 0.5)]"),
        "letter third row keeps backspace pinned right": row3.endswith('+ [KeySpec(.spacer, widthUnit: 0.5), KeySpec(.backspace)]'),
        "letter third row keeps seven middle letters": '"zxcvbnm".map { KeySpec(.character(String($0))) }' in row3,
        "shift and backspace no longer use wide key units": "KeySpec(.shift, widthUnit: 1.5)" not in row3 and "KeySpec(.backspace, widthUnit: 1.5)" not in row3,
        "letter key width helper exists": bool(width_helper),
        "letter key width helper includes characters": "case .character(_), .shift, .backspace:" in width_helper,
        "letter row width constraint applies through helper": "usesUniformLetterKeys, usesLetterKeyWidth(for: key.kind)" in source,
        "letter row side-key expansion was removed": "var sideKeys: [UIButton]" not in source and "sideKeys.append(button)" not in source,
        "keyboard symbol icon size matches lowercase letters": "UIImage.SymbolConfiguration(pointSize: 26, weight: .light)" in source,
        "shift uses an SF Symbol icon": 'UIImage(systemName: "shift", withConfiguration: configuration)' in source,
        "backspace keeps delete SF Symbol icon": 'UIImage(systemName: "delete.left", withConfiguration: configuration)' in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Keyboard letter key layout checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard letter key layout checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
