#!/usr/bin/env python3
"""Regression checks for quick-fill add input and save behavior."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def function_body(source: str, name: str) -> str:
    match = re.search(rf"\bprivate\s+func\s+{re.escape(name)}\s*\(", source)
    if match is None:
        raise AssertionError(f"Missing function: {name}")
    start = match.start()

    brace_start = source.find("{", start)
    if brace_start == -1:
        raise AssertionError(f"Missing function body: {name}")

    depth = 0
    for index in range(brace_start, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[brace_start + 1:index]

    raise AssertionError(f"Unclosed function body: {name}")


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    handle_candidate = function_body(source, "handleCandidateSelection")
    insert_current_target = function_body(source, "insertTextIntoCurrentTarget")
    save_add_text = function_body(source, "saveQuickFillAddText")
    handle_add_input = function_body(source, "handleQuickFillAddInput")

    closes_add_window_from_candidate = re.search(
        r"if\s+isQuickFillAddWindowVisible\s*\{[^{}]*setQuickFillAddWindowVisible\(false\)[^{}]*return[^{}]*\}",
        handle_candidate,
        re.S,
    )
    checks = {
        "candidate selection keeps quick-fill add window open": closes_add_window_from_candidate is None,
        "candidate selection still handles composition candidates": "replaceCompositionWith(candidate)" in handle_candidate,
        "candidate selection still handles association candidates": "insertAssociationCandidate(candidate.text)" in handle_candidate,
        "current target routes text into quick-fill add draft": (
            "if isQuickFillAddWindowVisible" in insert_current_target
            and "appendQuickFillAddDraftText(text)" in insert_current_target
        ),
        "return key saves quick-fill add draft": (
            "case .returnKey:" in handle_add_input
            and "saveQuickFillAddText()" in handle_add_input
        ),
        "saving persists quick-fill items to app group": (
            'UserDefaults(suiteName: "group.com.local.fitnex")' in save_add_text
            and 'sharedDefaults?.set(items, forKey: "quickFill.items")' in save_add_text
        ),
        "saving reopens quick-fill panel": (
            "setQuickFillAddWindowVisible(false)" in save_add_text
            and "setQuickFillPanelVisible(true)" in save_add_text
        ),
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Quick fill add input checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Quick fill add input checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
