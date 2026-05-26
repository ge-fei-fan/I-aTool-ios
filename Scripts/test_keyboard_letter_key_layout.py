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


def number_third_row_definition(source: str) -> str:
    match = re.search(
        r"private var numberRows: \[\[KeySpec\]\] \{\s*\[\s*"
        r'"1234567890".*?,\s*'
        r'punctuationKeys\(\["-", "/", ":", ";", "\(", "\)", "\$", "&", "@", "\\""\]\),\s*'
        r"(.*?),\s*\[",
        source,
        re.S,
    )
    return match.group(1).strip() if match else ""


def symbol_third_row_definition(source: str) -> str:
    match = re.search(
        r"private var symbolRows: \[\[KeySpec\]\] \{\s*\[\s*"
        r'punctuationKeys\(\["\[", "\]", "\{", "\}", "#", "%", "\^", "\*", "\+", "="\]\),\s*'
        r'punctuationKeys\(\["_", "\\\\", "\|", "~", "<", ">", ".*?"\]\),\s*'
        r"(.*?),\s*\[",
        source,
        re.S,
    )
    return match.group(1).strip() if match else ""


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    row3 = row3_definition(source)
    number_row3 = number_third_row_definition(source)
    symbol_row3 = symbol_third_row_definition(source)
    width_helper = function_body(source, "private func usesLetterKeyWidth(for kind: KeyKind) -> Bool")

    checks = {
        "letter third row keeps shift pinned left": row3.startswith("[KeySpec(.shift), KeySpec(.spacer, widthUnit: 0.5)]"),
        "letter third row keeps backspace pinned right": row3.endswith('+ [KeySpec(.spacer, widthUnit: 0.5), KeySpec(.backspace)]'),
        "letter third row keeps seven middle letters": '"zxcvbnm".map { KeySpec(.character(String($0))) }' in row3,
        "shift and backspace no longer use wide key units": "KeySpec(.shift, widthUnit: 1.5)" not in row3 and "KeySpec(.backspace, widthUnit: 1.5)" not in row3,
        "letter key width helper exists": bool(width_helper),
        "letter key width helper includes only characters": "case .character(_):" in width_helper and ".shift" not in width_helper and ".backspace" not in width_helper,
        "letter row width constraint applies through helper": "if usesUniformLetterKeys, usesLetterKeyWidth(for: key.kind)" in source,
        "third-row edge controls use square key width": "isThirdRowEdgeControlKey(key.kind)" in source and "button.widthAnchor.constraint(equalToConstant: 42).isActive = true" in source,
        "number third row edge keys are not wide": 'KeySpec(.modeSwitch(.symbols), title: "#+=", widthUnit: 1.35)' not in number_row3 and "KeySpec(.backspace, widthUnit: 1.35)" not in number_row3,
        "symbol third row edge keys are not wide": 'KeySpec(.modeSwitch(.numbers), title: "123", widthUnit: 1.35)' not in symbol_row3 and "KeySpec(.backspace, widthUnit: 1.35)" not in symbol_row3,
        "third-row edge helper includes mode switches": "case .modeSwitch(.numbers), .modeSwitch(.symbols), .shift, .backspace:" in source,
        "square edge rows equalize middle keys": "squareEdgeRowFlexibleButtons" in source and "button.widthAnchor.constraint(equalTo: squareEdgeRowFlexibleButtons[0].widthAnchor)" in source,
        "letter row side-key expansion was removed": "var sideKeys: [UIButton]" not in source and "sideKeys.append(button)" not in source,
        "keyboard icon point size stays 24pt": "private static let keyboardIconPointSize: CGFloat = 24" in source,
        "keyboard key icon asset enum exists": "private enum KeyboardKeyIconAsset" in source and "case shift" in source and "case backspace" in source,
        "shift uses cat1 asset": 'return "cat1"' in source,
        "backspace uses clear-symbol asset": 'return "icons8-clear-symbol-48"' in source,
        "shift primary path uses keyboard key asset": 'button.setImage(keyboardKeyIcon(.shift' in source,
        "backspace primary path uses keyboard key asset": 'button.setImage(keyboardKeyIcon(.backspace' in source,
        "shift preserves original image colors": "keyboardKeyIcon(.shift, fallbackSystemName: \"shift\", fallbackWeight: .light, preservesOriginalColors: true)" in source,
        "backspace stays templated": "keyboardKeyIcon(.backspace, fallbackSystemName: \"delete.left\", fallbackWeight: .light, preservesOriginalColors: false)" in source,
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
