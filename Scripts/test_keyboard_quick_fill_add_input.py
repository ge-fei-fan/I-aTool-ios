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


def computed_property_body(source: str, name: str) -> str:
    match = re.search(rf"\bprivate\s+var\s+{re.escape(name)}\s*:\s*Bool\s*\{{", source)
    if match is None:
        raise AssertionError(f"Missing computed property: {name}")
    start = match.start()

    brace_start = source.find("{", start)
    if brace_start == -1:
        raise AssertionError(f"Missing computed property body: {name}")

    depth = 0
    for index in range(brace_start, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[brace_start + 1:index]

    raise AssertionError(f"Unclosed computed property body: {name}")


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    handle_candidate = function_body(source, "handleCandidateSelection")
    handle_translation_tap = function_body(source, "handleTranslationButtonTap")
    insert_current_target = function_body(source, "insertTextIntoCurrentTarget")
    save_add_text = function_body(source, "saveQuickFillAddText")
    close_add_to_panel = function_body(source, "closeQuickFillAddWindowToPanel")
    handle_add_input = function_body(source, "handleQuickFillAddInput")
    should_show_utility_overlay = computed_property_body(source, "shouldShowUtilityOverlay")

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
        "quick-fill add draft does not hide utility icons": (
            "quickFillAddDraftText.trimmingCharacters" not in should_show_utility_overlay
        ),
        "return key saves quick-fill add draft": (
            "case .returnKey:" in handle_add_input
            and "saveQuickFillAddText()" in handle_add_input
        ),
        "saving persists quick-fill items to app group": (
            'UserDefaults(suiteName: "group.com.local.fitnex")' in save_add_text
            and 'sharedDefaults?.set(items, forKey: "quickFill.items")' in save_add_text
        ),
        "saving keeps newest quick-fill item at top": (
            "items.insert(text, at: 0)" in save_add_text
            and "quickFillItems = items" in save_add_text
        ),
        "saving reopens quick-fill panel": (
            "setQuickFillAddWindowVisible(false)" in save_add_text
            and "setQuickFillPanelVisible(true)" in save_add_text
        ),
        "back button returns to quick-fill panel": (
            "setQuickFillAddWindowVisible(false" in close_add_to_panel
            and "reloadQuickFillItems()" in close_add_to_panel
            and "setQuickFillPanelVisible(true)" in close_add_to_panel
        ),
        "translation tap closes quick-fill add window first": (
            "setQuickFillAddWindowVisible(false" in handle_translation_tap
            and handle_translation_tap.find("setQuickFillAddWindowVisible(false")
            < handle_translation_tap.find("setTranslationPanelVisible(true)")
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
