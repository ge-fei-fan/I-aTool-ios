#!/usr/bin/env python3
"""Regression checks for expanded keyboard candidate page layout."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    checks = {
        "candidate page uses leading compact alignment": "candidatePageStack.alignment = .leading" in source,
        "quick fill restores fill alignment": "candidatePageStack.alignment = .fill" in source
        and source.find("private func renderQuickFillPanel()") < source.find("candidatePageStack.alignment = .fill", source.find("private func renderQuickFillPanel()")),
        "candidate page creates a single preview row": "let rowStack = UIStackView()" in source
        and "candidatePageStack.addArrangedSubview(rowStack)" in source,
        "candidate page no longer creates rows inside candidate loop": "var rowStack: UIStackView?" not in source
        and "let needsNewRow = rowStack == nil" not in source,
        "candidate page reserves ellipsis width": "let ellipsisSize = candidatePageEllipsisSize()" in source
        and "let availableCandidateWidth = hasMoreCandidates ? contentWidth - ellipsisSize.width - spacing : contentWidth" in source,
        "candidate page appends ellipsis when truncated": "makeCandidatePageEllipsisView()" in source
        and "if hasMoreCandidates" in source,
        "candidate page ellipsis is non-interactive": "ellipsisButton.isUserInteractionEnabled = false" in source,
        "candidate page keeps minimum candidate width": "let minimumWidth: CGFloat = 56" in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Keyboard candidate page layout checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard candidate page layout checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
