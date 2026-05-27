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
        "candidate page creates rows through helper": "func makeCandidatePageRowStack(spacing: CGFloat) -> UIStackView" in source
        and "candidatePageStack.addArrangedSubview(rowStack)" in source,
        "candidate page wraps normal candidates to next row": "let candidateSpacing = rowWidth == 0 ? 0 : spacing" in source
        and "if rowWidth > 0 && rowWidth + candidateSpacing + size.width > contentWidth" in source,
        "candidate page detects overwide candidates": "candidatePageButtonPreferredWidth(for: candidate.text)" in source
        and "let isOverwideCandidate = preferredWidth > contentWidth" in source,
        "overwide candidate gets full row width": "let size = candidatePageButtonSize(for: candidate.text, maxWidth: contentWidth)" in source
        and "rowWidth = contentWidth" in source,
        "expanded candidate titles truncate instead of wrapping": "button.titleLabel?.lineBreakMode = .byTruncatingTail" in source
        and "button.titleLabel?.numberOfLines = 1" in source,
        "candidate page no longer uses standalone ellipsis": "makeCandidatePageEllipsisView" not in source
        and "candidatePageEllipsisSize" not in source,
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
