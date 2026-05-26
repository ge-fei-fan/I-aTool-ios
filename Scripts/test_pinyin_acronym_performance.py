#!/usr/bin/env python3
"""Regression checks for pinyin acronym lookup fan-out."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SIMULATOR_PATH = REPO_ROOT / "Scripts" / "simulate_pinyin_keyboard.py"
RESOURCE_DIR = REPO_ROOT / "SimpaninKeyboard"
MAX_SHORT_ACRONYM_LOOKUPS = 600
MAX_LONG_COMPOSITION_LOOKUPS = 120


def load_simulator():
    spec = importlib.util.spec_from_file_location("simulate_pinyin_keyboard", SIMULATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SIMULATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def measured_candidates(provider, key: str):
    original = provider._bundled_candidates
    lookups: list[str] = []

    def wrapped(lookup_key: str):
        lookups.append(lookup_key)
        return original(lookup_key)

    provider._bundled_candidates = wrapped
    try:
        candidates = provider.keyboard_candidates(key)
    finally:
        provider._bundled_candidates = original

    return candidates, lookups


def main() -> int:
    simulator = load_simulator()
    provider = simulator.PinyinCandidateProvider(RESOURCE_DIR)

    failures: list[str] = []
    for key in ("ssh", "sss"):
        candidates, lookups = measured_candidates(provider, key)
        if len(lookups) > MAX_SHORT_ACRONYM_LOOKUPS:
            failures.append(f"{key} performed {len(lookups)} lexicon lookups")
        if key == "ssh" and "说实话" not in [candidate.text for candidate in candidates[:30]]:
            failures.append("ssh lost expected acronym candidate 说实话")

    shi_candidates, shi_lookups = measured_candidates(provider, "shi")
    if len(shi_lookups) != 1:
        failures.append(f"shi performed {len(shi_lookups)} lexicon lookups")
    if "是" not in [candidate.text for candidate in shi_candidates[:10]]:
        failures.append("shi lost expected exact candidate 是")

    for key in ("zhongguo", "woaibeijing"):
        candidates, lookups = measured_candidates(provider, key)
        if len(lookups) > MAX_LONG_COMPOSITION_LOOKUPS:
            failures.append(f"{key} performed {len(lookups)} lexicon lookups")
        if not candidates:
            failures.append(f"{key} returned no candidates")

    if failures:
        print("Pinyin acronym performance checks failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Pinyin acronym performance checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
