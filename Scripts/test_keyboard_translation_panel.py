#!/usr/bin/env python3
"""Regression checks for clipboard translation panel behavior."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewControllerLegacy.swift"


def method_body(source: str, name: str) -> str:
    match = re.search(rf"private func {re.escape(name)}\([^)]*\) \{{", source)
    if not match:
        return ""

    depth = 0
    start = match.end() - 1
    for index in range(start, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    return ""


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    tap_handler = method_body(source, "handleTranslationButtonTap")
    start_translation = method_body(source, "startClipboardTranslation")
    request_translation = method_body(source, "requestStreamingTranslation")
    cancel_translation = method_body(source, "cancelTranslationRequest")

    checks = {
        "translation panel has no original text view": "translationOriginalTextView" not in source,
        "translation tap keeps visible panel open": "setTranslationPanelVisible(false)" not in tap_handler,
        "translation tap always starts clipboard translation": tap_handler.count("startClipboardTranslation()") == 1
        and "if !isTranslationPanelVisible" in tap_handler,
        "new translation request invalidates older stream": "activeTranslationRequestID" in source
        and "activeTranslationRequestID += 1" in start_translation
        and "requestID" in request_translation,
        "cancelled translation callbacks cannot clear current request": "activeTranslationRequestID += 1" in cancel_translation
        and "guard self.activeTranslationRequestID == requestID else { return }" in request_translation,
        "prompt only returns Chinese": "natural English" not in source
        and "鑷姩璇嗗埆" in source
        and "绠€浣撲腑鏂? in source
        and "涓枃鍘熸枃" in source
        and "鍙繑鍥炶瘧鏂? in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Keyboard translation panel checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard translation panel checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
