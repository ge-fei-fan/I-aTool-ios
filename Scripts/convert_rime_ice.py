#!/usr/bin/env python3
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

PINYIN_RE = re.compile(r"^[a-züv: ]+$")


def normalize_code(value: str) -> str:
    value = value.strip().lower()
    value = value.replace("ü", "v").replace("u:", "v")
    return re.sub(r"[^a-z]", "", value)


def iter_dict_rows(path: Path):
    in_body = False
    with path.open("r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line == "...":
                in_body = True
                continue
            if not in_body:
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            text = parts[0].strip()
            if not text:
                continue
            yield text, [part.strip() for part in parts[1:] if part.strip()]


def parse_weight(parts):
    for value in reversed(parts):
        try:
            return int(float(value))
        except ValueError:
            continue
    return 1


def build_char_pinyin(dict_files):
    char_pinyin = {}
    for path in dict_files:
        for text, parts in iter_dict_rows(path):
            if len(text) != 1 or not parts:
                continue
            code = parts[0]
            if not PINYIN_RE.match(code):
                continue
            normalized = normalize_code(code)
            if normalized and text not in char_pinyin:
                char_pinyin[text] = normalized
    return char_pinyin


def code_from_parts(text, parts, char_pinyin):
    if not parts:
        return None

    if PINYIN_RE.match(parts[0]):
        return normalize_code(parts[0])

    code = "".join(char_pinyin.get(char, "") for char in text)
    if code and len(code) >= len(text):
        return code
    return None


def add_candidate(index, key, text, weight, max_word_length, max_prefix_length):
    if not key or not text or len(text) > max_word_length:
        return
    for length in range(1, min(len(key), max_prefix_length) + 1):
        prefix = key[:length]
        candidate_weight = weight + 10_000_000_000 if length == len(key) else weight
        existing = index[prefix].get(text)
        if existing is None or candidate_weight > existing:
            index[prefix][text] = candidate_weight


def prune(index, max_candidates):
    limit = max_candidates * 3
    for key, values in list(index.items()):
        if len(values) <= limit:
            continue
        top = sorted(values.items(), key=lambda item: (-item[1], len(item[0]), item[0]))[:limit]
        index[key] = dict(top)


def convert(source_dir: Path, output: Path, max_candidates: int, max_word_length: int, max_prefix_length: int):
    cn_dir = source_dir / "cn_dicts"
    char_files = [cn_dir / "8105.dict.yaml", cn_dir / "41448.dict.yaml"]
    char_pinyin = build_char_pinyin(char_files)
    dict_files = [
        cn_dir / "8105.dict.yaml",
        cn_dir / "41448.dict.yaml",
        cn_dir / "base.dict.yaml",
        cn_dir / "ext.dict.yaml",
        cn_dir / "others.dict.yaml",
        cn_dir / "tencent.dict.yaml",
    ]

    index = defaultdict(dict)
    row_count = 0
    used_count = 0

    for path in dict_files:
        for text, parts in iter_dict_rows(path):
            row_count += 1
            code = code_from_parts(text, parts, char_pinyin)
            if not code:
                continue
            weight = parse_weight(parts)
            add_candidate(index, code, text, weight, max_word_length, max_prefix_length)
            used_count += 1
            if used_count % 100000 == 0:
                prune(index, max_candidates)

    prune(index, max_candidates)
    result = {}
    for key, values in sorted(index.items()):
        candidates = sorted(values.items(), key=lambda item: (-item[1], len(item[0]), item[0]))
        result[key] = [word for word, _ in candidates[:max_candidates]]

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, separators=(",", ":"))

    print(f"source_rows={row_count}")
    print(f"used_rows={used_count}")
    print(f"keys={len(result)}")
    print(f"candidates={sum(len(v) for v in result.values())}")
    print(f"output={output}")


def main():
    parser = argparse.ArgumentParser(description="Convert rime-ice dictionaries into keyboard prefix lexicon JSON.")
    parser.add_argument("--source", required=True, help="Path to a checked-out rime-ice repository")
    parser.add_argument("--output", required=True, help="Output PinyinLexicon.json path")
    parser.add_argument("--max-candidates", type=int, default=120)
    parser.add_argument("--max-word-length", type=int, default=8)
    parser.add_argument("--max-prefix-length", type=int, default=8)
    args = parser.parse_args()
    convert(Path(args.source), Path(args.output), args.max_candidates, args.max_word_length, args.max_prefix_length)


if __name__ == "__main__":
    main()
