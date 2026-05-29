#!/usr/bin/env python3
"""Regression checks for quick-fill swipe edit and delete actions."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def function_body(source: str, name: str) -> str:
    match = re.search(rf"\bprivate\s+func\s+{re.escape(name)}\s*\(", source)
    if match is None:
        raise AssertionError(f"Missing function: {name}")

    brace_start = source.find("{", match.start())
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


def class_body(source: str, name: str) -> str:
    marker = f"private final class {name}"
    start = source.find(marker)
    if start == -1:
        raise AssertionError(f"Missing class: {name}")

    brace_start = source.find("{", start)
    if brace_start == -1:
        raise AssertionError(f"Missing class body: {name}")

    depth = 0
    for index in range(brace_start, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[brace_start + 1:index]

    raise AssertionError(f"Unclosed class body: {name}")


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    render_panel = function_body(source, "renderQuickFillPanel")
    make_row = function_body(source, "makeQuickFillButton")
    save_text = function_body(source, "saveQuickFillAddText")
    show_add = function_body(source, "showQuickFillAddWindow")
    try:
        row_class = class_body(source, "QuickFillSwipeActionRow")
    except AssertionError:
        row_class = ""

    checks = {
        "quick-fill items render with stable indices": (
            "quickFillItems.enumerated().forEach" in render_panel
            and "makeQuickFillButton(text: text, index: index)" in render_panel
        ),
        "quick-fill row uses custom swipe container": (
            "QuickFillSwipeActionRow(" in make_row
            and "onSelect" in make_row
            and "onEdit" in make_row
            and "onDelete" in make_row
            and "onExpand" in make_row
        ),
        "swipe row exposes edit and delete buttons": (
            'editButton.setTitle("编辑", for: .normal)' in row_class
            and 'deleteButton.setTitle("删除", for: .normal)' in row_class
        ),
        "swipe row handles horizontal pan": (
            "UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))" in row_class
            and "override func gestureRecognizerShouldBegin" in row_class
            and "abs(velocity.x) > abs(velocity.y)" in row_class
        ),
        "expanded row tap collapses instead of inserting": (
            "if isExpanded" in row_class
            and "setExpanded(false, animated: true)" in row_class
            and "return" in row_class
        ),
        "controller tracks editing index": "private var quickFillEditingIndex: Int?" in source,
        "edit window prefills selected text": (
            "quickFillEditingIndex = index" in show_add
            and "quickFillAddDraftText = quickFillItems[index]" in show_add
            and 'quickFillAddTitleLabel.text = quickFillEditingIndex == nil ? "添加常用语" : "编辑常用语"' in show_add
        ),
        "editing save preserves original position": (
            "if let editingIndex = quickFillEditingIndex" in save_text
            and "let targetIndex = min(editingIndex, items.count)" in save_text
            and "items.insert(text, at: targetIndex)" in save_text
        ),
        "delete action removes item and persists": (
            "private func deleteQuickFillItem(at index: Int)" in source
            and "items.remove(at: index)" in source
            and "persistQuickFillItems(items)" in source
        ),
        "only one swipe row remains expanded": (
            "private weak var expandedQuickFillRow: QuickFillSwipeActionRow?" in source
            and "private func handleQuickFillRowExpansion(_ row: QuickFillSwipeActionRow)" in source
            and "expandedQuickFillRow?.setExpanded(false, animated: true)" in source
        ),
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Quick fill swipe action checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Quick fill swipe action checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
