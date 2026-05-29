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
    apply_candidate_refresh = function_body(source, "applyCandidateRefreshResult")
    handle_candidate = function_body(source, "handleCandidateSelection")
    handle_translation_tap = function_body(source, "handleTranslationButtonTap")
    handle_utility_fill_tap = function_body(source, "handleUtilityFillButtonTap")
    show_add_window = function_body(source, "showQuickFillAddWindow")
    set_add_window_visible = function_body(source, "setQuickFillAddWindowVisible")
    insert_current_target = function_body(source, "insertTextIntoCurrentTarget")
    save_add_text = function_body(source, "saveQuickFillAddText")
    persist_items = function_body(source, "persistQuickFillItems")
    close_add_to_panel = function_body(source, "closeQuickFillAddWindowToPanel")
    handle_add_input = function_body(source, "handleQuickFillAddInput")
    set_candidate_page_visible = function_body(source, "setCandidatePageVisible")
    set_quick_fill_panel_visible = function_body(source, "setQuickFillPanelVisible")
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
        "empty candidate refresh preserves quick-fill panel": (
            "if allCandidates.isEmpty && !isQuickFillPanelVisible" in apply_candidate_refresh
            and "setCandidatePageVisible(false)" in apply_candidate_refresh
        ),
        "quick-fill icon from add window opens panel directly": (
            "if isQuickFillAddWindowVisible" in handle_utility_fill_tap
            and "setQuickFillAddWindowVisible(false, animated: false)" in handle_utility_fill_tap
            and "setQuickFillPanelVisible(true)" in handle_utility_fill_tap
            and handle_utility_fill_tap.find("if isQuickFillAddWindowVisible")
            < handle_utility_fill_tap.find("if isQuickFillPanelVisible")
        ),
        "quick-fill icon add-window branch returns before toggle": (
            re.search(
                r"if\s+isQuickFillAddWindowVisible\s*\{[^{}]*setQuickFillPanelVisible\(true\)[^{}]*return[^{}]*\}",
                handle_utility_fill_tap,
                re.S,
            )
            is not None
        ),
        "quick-fill panel show recovers hidden panel view": (
            "needsPanelRestore" in set_quick_fill_panel_visible
            and "candidatePageView.isHidden" in set_quick_fill_panel_visible
            and "guard isQuickFillPanelVisible != shouldShow || needsPanelRestore else { return }"
            in set_quick_fill_panel_visible
        ),
        "candidate page dismissal preserves quick-fill panel": (
            "guard !self.isCandidatePageVisible," in set_candidate_page_visible
            and "!self.isQuickFillPanelVisible else { return }" in set_candidate_page_visible
        ),
        "return key saves quick-fill add draft": (
            "case .returnKey:" in handle_add_input
            and "saveQuickFillAddText()" in handle_add_input
        ),
        "saving persists quick-fill items to app group": (
            "persistQuickFillItems(items)" in save_add_text
            and 'UserDefaults(suiteName: "group.com.local.fitnex")' in persist_items
            and 'sharedDefaults?.set(items, forKey: "quickFill.items")' in persist_items
        ),
        "saving keeps newest quick-fill item at top": (
            "items.insert(text, at: 0)" in save_add_text
            and "quickFillItems = items" in persist_items
        ),
        "saving reopens quick-fill panel": (
            "setQuickFillAddWindowVisible(false)" in save_add_text
            and "setQuickFillPanelVisible(true)" in save_add_text
        ),
        "add mode clears edit state and draft": (
            "quickFillEditingIndex = nil" in show_add_window
            and 'quickFillAddTitleLabel.text = quickFillEditingIndex == nil ? "添加常用语" : "编辑常用语"'
            in show_add_window
            and 'quickFillAddDraftText = ""' in show_add_window
        ),
        "edit mode preloads selected quick-fill item": (
            "quickFillEditingIndex = index" in show_add_window
            and "quickFillAddDraftText = quickFillItems[index]" in show_add_window
        ),
        "hiding add window clears edit mode": (
            "quickFillEditingIndex = nil" in set_add_window_visible
            and 'quickFillAddTitleLabel.text = "添加常用语"' in set_add_window_visible
        ),
        "editing persists replacement at original index": (
            "if let editingIndex = quickFillEditingIndex" in save_add_text
            and "let targetIndex = min(editingIndex, items.count)" in save_add_text
            and "items.insert(text, at: targetIndex)" in save_add_text
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
