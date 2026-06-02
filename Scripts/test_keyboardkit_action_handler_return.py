#!/usr/bin/env python3
"""Regression check for KeyboardKit action handler Bool forwarding."""

from __future__ import annotations

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


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    can_handle = function_body(
        source,
        "func canHandle(_ gesture: Keyboard.Gesture, on action: KeyboardAction) -> Bool",
    )

    checks = {
        "custom pinyin actions are handled locally": (
            "if shouldHandlePinyinAction(action)" in can_handle
            and "return true" in can_handle
        ),
        "unhandled actions return the standard handler decision": (
            "return standardActionHandler.canHandle(gesture, on: action)" in can_handle
        ),
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("KeyboardKit action handler return checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("KeyboardKit action handler return checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
