#!/usr/bin/env python3
"""Regression checks for non-blocking keyboard candidate refresh."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewController.swift"


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    checks = {
        "candidate refresh uses a background queue": "private let candidateQueue = DispatchQueue(" in source,
        "candidate refresh work can be cancelled": "private var candidateRefreshWorkItem: DispatchWorkItem?" in source,
        "candidate refresh has generation tokens": "private var candidateRefreshGeneration = 0" in source,
        "old pending candidate refreshes are cancelled": "candidateRefreshWorkItem?.cancel()" in source,
        "candidate lookup is scheduled off the touch callback": "candidateQueue.asyncAfter" in source,
        "cancelled candidate work exits before lookup": "guard !workItem.isCancelled else { return }" in source,
        "stale candidate results are discarded on main": "candidateRefreshGeneration == generation" in source,
        "candidate application stays on the main queue": "DispatchQueue.main.async" in source,
        "bundled pinyin lookups are cached behind a lock": "private let bundledCandidateCacheLock = NSLock()" in source,
        "bundled pinyin lookup cache has a size limit": "private static let maxBundledCandidateCacheEntries" in source,
        "bundled pinyin cache stores misses": "storeBundledCandidates([], for: key)" in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Missing async candidate refresh behavior:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard async candidate refresh checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
