#!/usr/bin/env python3
"""Regression checks for hiding quick-fill from the settings page."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HOME_SOURCE = REPO_ROOT / "Simpanin" / "HomeView.swift"


def struct_body(source: str, name: str) -> str:
    marker = f"private struct {name}:"
    start = source.find(marker)
    if start == -1:
        raise AssertionError(f"Missing struct: {name}")

    brace_start = source.find("{", start)
    if brace_start == -1:
        raise AssertionError(f"Missing struct body: {name}")

    depth = 0
    for index in range(brace_start, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[brace_start + 1:index]

    raise AssertionError(f"Unclosed struct body: {name}")


def main() -> int:
    source = HOME_SOURCE.read_text(encoding="utf-8")
    settings_view = struct_body(source, "SettingsView")

    checks = {
        "settings page hides quick-fill row": (
            'title: "快速填充"' not in settings_view
            and "showingQuickFillSettings = true" not in settings_view
        ),
        "settings page does not own quick-fill settings state": (
            "showingQuickFillSettings" not in settings_view
            and "quickFillStore" not in settings_view
        ),
        "settings page no longer presents quick-fill sheet": (
            "QuickFillSettingsSheet" not in settings_view
        ),
        "quick-fill settings implementation remains available": (
            "private struct QuickFillSettingsSheet" in source
            and "private final class QuickFillStore" in source
        ),
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Settings quick-fill visibility checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Settings quick-fill visibility checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
