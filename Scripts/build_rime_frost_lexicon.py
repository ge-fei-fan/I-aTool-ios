#!/usr/bin/env python3
import argparse
import re
import shutil
import struct
import subprocess
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


REPO_URL = "https://github.com/gaboolic/rime-frost"
DEFAULT_TABLE = "rime_frost"
KEY_SIZE = 64
ASSOCIATION_KEY_SIZE = 32
FNV_OFFSET_BASIS = 14695981039346656037
FNV_PRIME = 1099511628211


@dataclass(frozen=True)
class CandidateEntry:
    text: str
    weight: int
    tier: int
    word_length: int
    syllable_count: int


def normalized_key(value):
    return "".join(ch for ch in value.lower() if "a" <= ch <= "z")


def hash_key(value):
    result = FNV_OFFSET_BASIS
    for byte in value.encode("utf-8"):
        result ^= byte
        result = (result * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return result


def normalized_syllables(value):
    return [key for key in (normalized_key(part) for part in value.split()) if key]


def normalized_text(value):
    return value.replace("\t", " ").replace("\r", "").replace("\n", "").strip()


def has_cjk(value):
    return any("\u4e00" <= ch <= "\u9fff" for ch in value)


def is_cjk_text(value):
    return bool(value) and all("\u4e00" <= ch <= "\u9fff" for ch in value)


def tier_for_table(table):
    if table in {"cn_dicts/8105", "cn_dicts/base"}:
        return 0
    if table in {"cn_dicts/41448", "cn_dicts/ext", "cn_dicts/others", "cn_dicts/corrections"}:
        return 1
    if table.startswith("cn_dicts_cell/"):
        return 3
    if table == "cn_dicts/tencent":
        return 4
    return 2


def clone_or_update(source_dir, keep_download):
    if source_dir.exists():
        return

    if source_dir.parent:
        source_dir.parent.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        ["git", "clone", "--depth", "1", REPO_URL, str(source_dir)],
        check=True,
    )
    if not keep_download:
        # Caller still needs the clone during this run; cleanup happens in main.
        return


def parse_import_tables(root, table_name):
    table_path = root / f"{table_name}.dict.yaml"
    tables = []
    in_imports = False

    with table_path.open("r", encoding="utf-8-sig") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if line == "...":
                break
            if line.startswith("import_tables:"):
                in_imports = True
                continue
            if not in_imports:
                continue
            if not line:
                continue
            if not line.startswith("-"):
                if not raw_line.startswith((" ", "\t")):
                    in_imports = False
                continue

            item = line[1:].strip()
            item = item.split("#", 1)[0].strip()
            if item:
                tables.append(item)

    return tables


def iter_dict_rows(path, tier):
    in_body = False
    with path.open("r", encoding="utf-8-sig") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            stripped = line.strip()
            if not in_body:
                if stripped == "...":
                    in_body = True
                continue
            if not stripped or stripped.startswith("#"):
                continue
            if "\t" not in line:
                continue

            fields = line.split("\t")
            if len(fields) < 2:
                continue

            text = normalized_text(fields[0])
            syllables = normalized_syllables(fields[1])
            key = "".join(syllables)
            if not text or not key or not syllables:
                continue

            weight = 1
            if len(fields) >= 3:
                match = re.search(r"-?\d+", fields[2])
                if match:
                    weight = max(1, int(match.group(0)))

            yield key, CandidateEntry(
                text=text,
                weight=weight,
                tier=tier,
                word_length=len(text),
                syllable_count=len(syllables),
            )


def should_replace_candidate(current, next_entry):
    if current is None:
        return True
    if next_entry.tier != current.tier:
        return next_entry.tier < current.tier
    if next_entry.weight != current.weight:
        return next_entry.weight > current.weight
    return next_entry.word_length < current.word_length


def add_candidate(store, key, entry, max_candidates, max_word_length):
    if not key or len(key.encode("utf-8")) > KEY_SIZE:
        return
    if not entry.text or entry.word_length > max_word_length:
        return
    if not has_cjk(entry.text):
        return

    by_text = store[key]
    current = by_text.get(entry.text)
    if should_replace_candidate(current, entry):
        by_text[entry.text] = entry


def add_associations(store, entry, min_weight, max_suffix_length):
    text = entry.text
    if entry.weight < min_weight or len(text) < 3 or not is_cjk_text(text):
        return

    association_weight = entry.weight + max(0, 4 - entry.tier) * 10_000
    max_prefix_length = min(4, len(text) - 1)
    for prefix_length in range(2, max_prefix_length + 1):
        prefix = text[:prefix_length]
        suffix = text[prefix_length:]
        if not suffix or len(suffix) > max_suffix_length:
            continue
        if len(prefix.encode("utf-8")) > ASSOCIATION_KEY_SIZE:
            continue
        store[prefix][suffix] = max(store[prefix].get(suffix, 0), association_weight)


def candidate_sort_key(item):
    text, entry = item
    return (entry.tier, -entry.weight, entry.word_length, text)


def format_candidate(entry):
    return f"{entry.text}:{entry.weight}:{entry.tier}:{entry.word_length}:{entry.syllable_count}"


def write_indexed_tsv(entries_by_key, tsv_path, idx_path, key_size, max_candidates):
    tsv_tmp = tsv_path.with_suffix(tsv_path.suffix + ".tmp")
    idx_tmp = idx_path.with_suffix(idx_path.suffix + ".tmp")
    key_count = 0
    candidate_count = 0
    index_records = []

    with tsv_tmp.open("wb") as tsv:
        for key in sorted(entries_by_key):
            if len(key.encode("utf-8")) > key_size:
                continue
            candidates = sorted(
                entries_by_key[key].items(),
                key=candidate_sort_key,
            )[:max_candidates]
            if not candidates:
                continue

            fields = [key] + [format_candidate(entry) for _, entry in candidates]
            line = ("\t".join(fields) + "\n").encode("utf-8")
            offset = tsv.tell()
            tsv.write(line)

            index_records.append((hash_key(key), key, offset, len(line)))
            key_count += 1
            candidate_count += len(candidates)

    with idx_tmp.open("wb") as idx:
        for key_hash, _, offset, length in sorted(index_records):
            idx.write(struct.pack("<Q", key_hash))
            idx.write(struct.pack("<Q", offset))
            idx.write(struct.pack("<I", length))

    tsv_tmp.replace(tsv_path)
    idx_tmp.replace(idx_path)
    return key_count, candidate_count


def write_association_indexed_tsv(entries_by_key, tsv_path, idx_path, key_size, max_candidates):
    tsv_tmp = tsv_path.with_suffix(tsv_path.suffix + ".tmp")
    idx_tmp = idx_path.with_suffix(idx_path.suffix + ".tmp")
    key_count = 0
    candidate_count = 0

    with tsv_tmp.open("wb") as tsv, idx_tmp.open("wb") as idx:
        for key in sorted(entries_by_key):
            if len(key.encode("utf-8")) > key_size:
                continue
            candidates = sorted(
                entries_by_key[key].items(),
                key=lambda item: (-item[1], len(item[0]), item[0]),
            )[:max_candidates]
            if not candidates:
                continue

            fields = [key] + [f"{text}:{weight}" for text, weight in candidates]
            line = ("\t".join(fields) + "\n").encode("utf-8")
            offset = tsv.tell()
            tsv.write(line)

            key_bytes = key.encode("utf-8")
            idx.write(key_bytes.ljust(key_size, b"\0"))
            idx.write(struct.pack("<Q", offset))
            idx.write(struct.pack("<I", len(line)))
            key_count += 1
            candidate_count += len(candidates)

    tsv_tmp.replace(tsv_path)
    idx_tmp.replace(idx_path)
    return key_count, candidate_count


def main():
    parser = argparse.ArgumentParser(description="Build Simpanin pinyin resources from rime-frost.")
    parser.add_argument("--source-dir", default=".rime-frost-tmp")
    parser.add_argument("--output-directory", default="SimpaninKeyboard")
    parser.add_argument("--table", default=DEFAULT_TABLE)
    parser.add_argument("--max-candidates", type=int, default=180)
    parser.add_argument("--max-associations", type=int, default=80)
    parser.add_argument("--max-word-length", type=int, default=12)
    parser.add_argument("--min-association-weight", type=int, default=100)
    parser.add_argument("--max-association-suffix-length", type=int, default=8)
    parser.add_argument("--keep-downloads", action="store_true")
    args = parser.parse_args()

    repo = Path.cwd()
    source_dir = repo / args.source_dir
    output_dir = repo / args.output_directory
    output_dir.mkdir(parents=True, exist_ok=True)

    clone_or_update(source_dir, args.keep_downloads)

    lexicon = defaultdict(dict)
    associations = defaultdict(dict)
    tables = parse_import_tables(source_dir, args.table)
    imported_rows = 0

    for table in tables:
        path = source_dir / f"{table}.dict.yaml"
        if not path.exists():
            raise FileNotFoundError(f"Missing rime-frost table: {table}")

        tier = tier_for_table(table)
        for key, entry in iter_dict_rows(path, tier):
            add_candidate(lexicon, key, entry, args.max_candidates, args.max_word_length)
            add_associations(
                associations,
                entry,
                args.min_association_weight,
                args.max_association_suffix_length,
            )
            imported_rows += 1

    lexicon_keys, lexicon_candidates = write_indexed_tsv(
        lexicon,
        output_dir / "PinyinLexicon.tsv",
        output_dir / "PinyinLexicon.idx",
        KEY_SIZE,
        args.max_candidates,
    )
    association_keys, association_candidates = write_association_indexed_tsv(
        associations,
        output_dir / "PinyinAssociations.tsv",
        output_dir / "PinyinAssociations.idx",
        ASSOCIATION_KEY_SIZE,
        args.max_associations,
    )

    if not args.keep_downloads and source_dir.exists():
        shutil.rmtree(source_dir)

    print(f"ImportedRows={imported_rows}")
    print(f"LexiconKeys={lexicon_keys}")
    print(f"LexiconCandidates={lexicon_candidates}")
    print(f"AssociationKeys={association_keys}")
    print(f"AssociationCandidates={association_candidates}")
    print(f"LexiconTSV={output_dir / 'PinyinLexicon.tsv'}")
    print(f"AssociationTSV={output_dir / 'PinyinAssociations.tsv'}")


if __name__ == "__main__":
    main()
