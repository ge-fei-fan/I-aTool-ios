#!/usr/bin/env python3
"""Simulate the iOS keyboard pinyin candidate lookup from the bundled lexicon."""

from __future__ import annotations

import argparse
import bisect
import os
import re
import struct
import sys
from dataclasses import dataclass, replace
from enum import Enum
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RESOURCE_DIR = REPO_ROOT / "SimpaninKeyboard"


def configure_stdio() -> None:
    """Keep candidate output stable on Windows consoles and redirected pipes."""
    if sys.platform != "win32":
        return

    os.environ.setdefault("PYTHONUTF8", "1")
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        try:
            reconfigure(encoding="utf-8", errors="replace")
        except (OSError, ValueError):
            pass


def resolve_resource_dir(resource_dir: Path) -> Path:
    path = resource_dir.expanduser()
    if path.is_absolute():
        return path.resolve()
    return (Path.cwd() / path).resolve()


@dataclass(frozen=True)
class PinyinCandidate:
    text: str
    weight: int
    tier: int = 2
    word_length: int | None = None
    syllable_count: int = 1
    consume_length: int = 0
    source: str = "dictionary"

    def __post_init__(self) -> None:
        if self.word_length is None:
            object.__setattr__(self, "word_length", len(self.text))


@dataclass(frozen=True)
class PinyinCompletion:
    key: str
    consume_length: int


@dataclass(frozen=True)
class PinyinCorrection:
    key: str
    syllables: tuple[str, ...]
    cost: int
    corrected_syllables: int


@dataclass(frozen=True)
class InitialShorthandChunk:
    key: str
    is_shorthand: bool


@dataclass(frozen=True)
class CorrectionPath:
    key: str
    syllables: tuple[str, ...]
    cost: int
    corrected_syllables: int
    sort_score: int


@dataclass(frozen=True)
class BeamPath:
    text: str
    score: int
    parts: int


@dataclass(frozen=True)
class LooseKeyAlias:
    pinyin_keys: tuple[str, ...]
    preferred_text: str | None = None


class MatchKind(Enum):
    EXACT = "exact"
    COMPLETION = "completion"
    FUZZY = "fuzzy"
    PREFIX = "prefix"
    BEAM = "beam"
    FALLBACK = "fallback"


class PinyinSegmenter:
    SYLLABLES = {
        "a", "ai", "an", "ang", "ao",
        "ba", "bai", "ban", "bang", "bao", "bei", "ben", "beng", "bi", "bian", "biao", "bie", "bin", "bing", "bo", "bu",
        "ca", "cai", "can", "cang", "cao", "ce", "cen", "ceng", "cha", "chai", "chan", "chang", "chao", "che", "chen", "cheng", "chi", "chong", "chou", "chu", "chua", "chuai", "chuan", "chuang", "chui", "chun", "chuo", "ci", "cong", "cou", "cu", "cuan", "cui", "cun", "cuo",
        "da", "dai", "dan", "dang", "dao", "de", "dei", "den", "deng", "di", "dia", "dian", "diao", "die", "ding", "diu", "dong", "dou", "du", "duan", "dui", "dun", "duo",
        "e", "ei", "en", "eng", "er",
        "fa", "fan", "fang", "fei", "fen", "feng", "fo", "fou", "fu",
        "ga", "gai", "gan", "gang", "gao", "ge", "gei", "gen", "geng", "gong", "gou", "gu", "gua", "guai", "guan", "guang", "gui", "gun", "guo",
        "ha", "hai", "han", "hang", "hao", "he", "hei", "hen", "heng", "hong", "hou", "hu", "hua", "huai", "huan", "huang", "hui", "hun", "huo",
        "ji", "jia", "jian", "jiang", "jiao", "jie", "jin", "jing", "jiong", "jiu", "ju", "juan", "jue", "jun",
        "ka", "kai", "kan", "kang", "kao", "ke", "ken", "keng", "kong", "kou", "ku", "kua", "kuai", "kuan", "kuang", "kui", "kun", "kuo",
        "la", "lai", "lan", "lang", "lao", "le", "lei", "leng", "li", "lia", "lian", "liang", "liao", "lie", "lin", "ling", "liu", "lo", "long", "lou", "lu", "lv", "luan", "lve", "lun", "luo",
        "ma", "mai", "man", "mang", "mao", "me", "mei", "men", "meng", "mi", "mian", "miao", "mie", "min", "ming", "miu", "mo", "mou", "mu",
        "na", "nai", "nan", "nang", "nao", "ne", "nei", "nen", "neng", "ni", "nian", "niang", "niao", "nie", "nin", "ning", "niu", "nong", "nou", "nu", "nv", "nuan", "nve", "nuo",
        "o", "ou",
        "pa", "pai", "pan", "pang", "pao", "pei", "pen", "peng", "pi", "pian", "piao", "pie", "pin", "ping", "po", "pou", "pu",
        "qi", "qia", "qian", "qiang", "qiao", "qie", "qin", "qing", "qiong", "qiu", "qu", "quan", "que", "qun",
        "ran", "rang", "rao", "re", "ren", "reng", "ri", "rong", "rou", "ru", "ruan", "rui", "run", "ruo",
        "sa", "sai", "san", "sang", "sao", "se", "sen", "seng", "sha", "shai", "shan", "shang", "shao", "she", "shen", "sheng", "shi", "shou", "shu", "shua", "shuai", "shuan", "shuang", "shui", "shun", "shuo", "si", "song", "sou", "su", "suan", "sui", "sun", "suo",
        "ta", "tai", "tan", "tang", "tao", "te", "teng", "ti", "tian", "tiao", "tie", "ting", "tong", "tou", "tu", "tuan", "tui", "tun", "tuo",
        "wa", "wai", "wan", "wang", "wei", "wen", "weng", "wo", "wu",
        "xi", "xia", "xian", "xiang", "xiao", "xie", "xin", "xing", "xiong", "xiu", "xu", "xuan", "xue", "xun",
        "ya", "yan", "yang", "yao", "ye", "yi", "yin", "ying", "yo", "yong", "you", "yu", "yuan", "yue", "yun",
        "za", "zai", "zan", "zang", "zao", "ze", "zei", "zen", "zeng", "zha", "zhai", "zhan", "zhang", "zhao", "zhe", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu", "zhua", "zhuai", "zhuan", "zhuang", "zhui", "zhun", "zhuo", "zi", "zong", "zou", "zu", "zuan", "zui", "zun", "zuo",
    }
    COMPLETION_PRIORITY = {
        "h": ["hua", "huan", "han", "hao", "he", "hui", "huang", "hong", "huo", "hai", "hang", "heng", "hen", "ha", "hu"],
        "k": ["kan", "kao", "kai", "kuai", "ke", "kong", "kou", "ku", "kang", "ken", "keng", "ka", "kuan", "kuang", "kui", "kun", "kuo", "kua"],
        "s": ["shi", "shuo", "shang", "she", "shu", "shen", "sheng", "shou", "suo", "song", "si", "san", "sai", "su", "sa"],
        "x": ["xiang", "xin", "xing", "xian", "xiao", "xue", "xi", "xia", "xie", "xiu", "xu", "xuan", "xun", "xiong"],
    }
    ORDERED_SYLLABLES = sorted(SYLLABLES, key=lambda value: (len(value), value))
    MAX_CORRECTION_COST = 2
    MAX_CORRECTED_SYLLABLES = 2
    MAX_CORRECTION_INPUT_LENGTH = 18
    MAX_CORRECTION_SPAN = 7
    MAX_CORRECTION_WIDTH = 24
    KEYBOARD_NEIGHBORS = {
        "q": "wa", "w": "qase", "e": "wsdr", "r": "edft", "t": "rfgy", "y": "tghu", "u": "yhji", "i": "ujko", "o": "iklp", "p": "ol",
        "a": "qwsz", "s": "awedxz", "d": "serfcx", "f": "drtgvc", "g": "ftyhbv", "h": "gyujnb", "j": "huikmn", "k": "jiolm", "l": "kop",
        "z": "asx", "x": "zsdc", "c": "xdfv", "v": "cfgb", "b": "vghn", "n": "bhjm", "m": "njk",
    }

    @classmethod
    def segment(cls, key: str) -> list[str]:
        index = 0
        result: list[str] = []
        while index < len(key):
            best = None
            end = index + min(6, len(key) - index)
            while end > index:
                piece = key[index:end]
                if piece in cls.SYLLABLES:
                    best = piece
                    break
                end -= 1
            if best is None:
                return []
            result.append(best)
            index += len(best)
        return result

    @classmethod
    def completion_keys(cls, key: str, limit: int) -> list[PinyinCompletion]:
        segments, remainder = cls._partial_segmentation(key)
        if not remainder or len(remainder) > 3:
            return []
        chunks = cls._prefix_chunks(remainder)
        if not chunks:
            return []

        completions = [cls._completion_syllables(chunk) for chunk in chunks]
        if any(not values for values in completions):
            return []

        base_key = "".join(segments)
        base_consume_length = sum(len(segment) for segment in segments)
        results: list[PinyinCompletion] = []
        seen: set[str] = set()

        def append(candidate_key: str, consumed_chunks: int) -> None:
            if len(results) >= limit or candidate_key == base_key or candidate_key in seen:
                return
            seen.add(candidate_key)
            consume_length = base_consume_length + sum(len(chunk) for chunk in chunks[:consumed_chunks])
            results.append(PinyinCompletion(candidate_key, consume_length))

        append(base_key + "".join(values[0] for values in completions), len(completions))
        if len(completions) > 1:
            for count in range(len(completions) - 1, 0, -1):
                append(base_key + "".join(values[0] for values in completions[:count]), count)

        def build(index: int, candidate_key: str) -> None:
            if len(results) >= limit:
                return
            if index == len(completions):
                append(candidate_key, len(completions))
                return
            for syllable in completions[index]:
                build(index + 1, candidate_key + syllable)
                if len(results) >= limit:
                    break

        build(0, base_key)
        return results

    @classmethod
    def initial_shorthand_keys(cls, key: str, limit: int) -> list[str]:
        chunks = cls._initial_shorthand_chunks(key)
        if (
            limit <= 0
            or chunks is None
            or not any(chunk.is_shorthand for chunk in chunks)
            or not any(not chunk.is_shorthand for chunk in chunks)
        ):
            return []

        expansions = [
            cls._completion_syllables(chunk.key) if chunk.is_shorthand else [chunk.key]
            for chunk in chunks
        ]
        if any(not values for values in expansions):
            return []

        original_key = "".join(chunk.key for chunk in chunks)
        results: list[str] = []
        seen: set[str] = set()

        def build(index: int, candidate_key: str) -> None:
            if len(results) >= limit:
                return
            if index == len(expansions):
                if candidate_key and candidate_key != original_key and candidate_key not in seen:
                    seen.add(candidate_key)
                    results.append(candidate_key)
                return
            for syllable in expansions[index]:
                build(index + 1, candidate_key + syllable)
                if len(results) >= limit:
                    break

        build(0, "")
        return results

    @classmethod
    def acronym_key_sequences(
        cls,
        key: str,
        syllables_per_letter_limit: int,
        sequence_limit: int,
    ) -> list[tuple[str, ...]]:
        if (
            len(key) < 2
            or len(key) > 6
            or syllables_per_letter_limit <= 0
            or sequence_limit <= 0
            or "".join(cls.segment(key)) == key
        ):
            return []

        letters = list(key)
        if not all(cls._is_initial_shorthand(letter) for letter in letters):
            return []

        expansions = [
            cls._completion_syllables(letter)[:syllables_per_letter_limit]
            for letter in letters
        ]
        if any(not values for values in expansions):
            return []

        results: list[tuple[str, ...]] = []

        def build(index: int, sequence: tuple[str, ...]) -> None:
            if len(results) >= sequence_limit:
                return
            if index == len(expansions):
                results.append(sequence)
                return
            for syllable in expansions[index]:
                build(index + 1, sequence + (syllable,))
                if len(results) >= sequence_limit:
                    break

        build(0, ())
        return results

    @classmethod
    def correction_keys(cls, key: str, limit: int) -> list[PinyinCorrection]:
        if len(key) < 4 or len(key) > cls.MAX_CORRECTION_INPUT_LENGTH:
            return []
        if "".join(cls.segment(key)) == key:
            return []

        paths: list[list[CorrectionPath]] = [[] for _ in range(len(key) + 1)]
        paths[0] = [CorrectionPath("", (), 0, 0, 0)]

        for start in range(len(key)):
            if not paths[start]:
                continue
            max_end = min(len(key), start + cls.MAX_CORRECTION_SPAN)
            for end in range(start + 1, max_end + 1):
                piece = key[start:end]
                matches = cls._correction_matches(piece)
                if not matches:
                    continue
                for path in paths[start]:
                    for syllable, match_cost in matches:
                        corrected_syllables = path.corrected_syllables + (0 if match_cost == 0 else 1)
                        cost = path.cost + match_cost
                        if cost > cls.MAX_CORRECTION_COST or corrected_syllables > cls.MAX_CORRECTED_SYLLABLES:
                            continue
                        paths[end].append(CorrectionPath(
                            path.key + syllable,
                            path.syllables + (syllable,),
                            cost,
                            corrected_syllables,
                            path.sort_score + cls._correction_sort_rank(piece, syllable),
                        ))
                paths[end] = cls._prune_correction_paths(paths[end])

        return [
            PinyinCorrection(path.key, path.syllables, path.cost, path.corrected_syllables)
            for path in cls._prune_correction_paths(paths[len(key)])
            if path.cost > 0 and path.key != key
        ][:limit]

    @classmethod
    def _partial_segmentation(cls, key: str) -> tuple[list[str], str]:
        index = 0
        result: list[str] = []
        while index < len(key):
            best = None
            end = index + min(6, len(key) - index)
            while end > index:
                piece = key[index:end]
                if piece in cls.SYLLABLES:
                    best = piece
                    break
                end -= 1
            if best is None:
                return result, key[index:]
            result.append(best)
            index += len(best)
        return result, ""

    @classmethod
    def _initial_shorthand_chunks(cls, key: str) -> list[InitialShorthandChunk] | None:
        if len(key) < 4:
            return None

        index = 0
        result: list[InitialShorthandChunk] = []
        while index < len(key):
            best = None
            end = index + min(6, len(key) - index)
            while end > index:
                piece = key[index:end]
                if piece in cls.SYLLABLES:
                    best = piece
                    break
                end -= 1

            if best is not None:
                result.append(InitialShorthandChunk(best, False))
                index += len(best)
                continue

            piece = key[index:index + 1]
            if not cls._is_initial_shorthand(piece):
                return None
            result.append(InitialShorthandChunk(piece, True))
            index += 1

        return result

    @classmethod
    def _prefix_chunks(cls, remainder: str) -> list[str]:
        chunks: list[str] = []
        index = 0
        while index < len(remainder):
            best = None
            end = index + min(4, len(remainder) - index)
            while end > index:
                piece = remainder[index:end]
                if cls._has_syllable_with_prefix(piece):
                    best = piece
                    break
                end -= 1
            if best is None:
                return []
            chunks.append(best)
            index += len(best)
        return chunks

    @classmethod
    def _completion_syllables(cls, prefix: str) -> list[str]:
        matching = [syllable for syllable in cls.ORDERED_SYLLABLES if syllable.startswith(prefix)]
        if not matching:
            return []
        priority = cls.COMPLETION_PRIORITY.get(prefix, [])
        priority_set = set(priority)
        return [
            syllable for syllable in priority
            if syllable in cls.SYLLABLES and syllable.startswith(prefix)
        ] + [syllable for syllable in matching if syllable not in priority_set]

    @classmethod
    def _has_syllable_with_prefix(cls, prefix: str) -> bool:
        return any(syllable.startswith(prefix) for syllable in cls.ORDERED_SYLLABLES)

    @classmethod
    def _is_initial_shorthand(cls, key: str) -> bool:
        return len(key) == 1 and key not in cls.SYLLABLES and cls._has_syllable_with_prefix(key)

    @classmethod
    def _correction_matches(cls, piece: str) -> list[tuple[str, int]]:
        matches = []
        for syllable in cls.ORDERED_SYLLABLES:
            cost = cls._correction_cost(piece, syllable)
            if cost is not None:
                matches.append((syllable, cost))
        matches.sort(key=lambda item: (
            item[1],
            -cls._shared_prefix_length(item[0], piece),
            cls._correction_sort_rank(piece, item[0]),
            len(item[0]),
            item[0],
        ))
        return matches[:cls.MAX_CORRECTION_WIDTH]

    @classmethod
    def _correction_cost(cls, input_text: str, syllable: str) -> int | None:
        if input_text == syllable:
            return 0
        length_delta = len(input_text) - len(syllable)
        if abs(length_delta) > 1:
            return None
        if length_delta == 0:
            if cls._has_single_adjacent_keyboard_substitution(input_text, syllable) or cls._has_adjacent_transposition(input_text, syllable):
                return 1
            return None
        longer, shorter = (input_text, syllable) if length_delta > 0 else (syllable, input_text)
        return 1 if cls._can_match_by_skipping_one_character(longer, shorter) else None

    @classmethod
    def _correction_sort_rank(cls, input_text: str, syllable: str) -> int:
        if input_text == syllable:
            return 0
        if len(input_text) == len(syllable):
            mismatches = [index for index, value in enumerate(input_text) if value != syllable[index]]
            if len(mismatches) == 1:
                typed = input_text[mismatches[0]]
                expected = syllable[mismatches[0]]
                neighbors = cls.KEYBOARD_NEIGHBORS.get(typed)
                if neighbors and expected in neighbors:
                    return 10 + neighbors.index(expected)
                neighbors = cls.KEYBOARD_NEIGHBORS.get(expected)
                if neighbors and typed in neighbors:
                    return 10 + neighbors.index(typed)
            if len(mismatches) == 2:
                return 20
        return 30 if len(input_text) == len(syllable) else 14

    @classmethod
    def _has_single_adjacent_keyboard_substitution(cls, input_text: str, syllable: str) -> bool:
        mismatch = None
        for left, right in zip(input_text, syllable):
            if left == right:
                continue
            if mismatch is not None:
                return False
            mismatch = (left, right)
        return bool(mismatch and cls._are_keyboard_neighbors(mismatch[0], mismatch[1]))

    @staticmethod
    def _has_adjacent_transposition(input_text: str, syllable: str) -> bool:
        mismatches = [index for index, value in enumerate(input_text) if value != syllable[index]]
        return (
            len(mismatches) == 2
            and mismatches[1] == mismatches[0] + 1
            and input_text[mismatches[0]] == syllable[mismatches[1]]
            and input_text[mismatches[1]] == syllable[mismatches[0]]
        )

    @staticmethod
    def _can_match_by_skipping_one_character(longer: str, shorter: str) -> bool:
        longer_index = 0
        shorter_index = 0
        skipped = False
        while longer_index < len(longer) and shorter_index < len(shorter):
            if longer[longer_index] == shorter[shorter_index]:
                longer_index += 1
                shorter_index += 1
            elif skipped:
                return False
            else:
                skipped = True
                longer_index += 1
        return True

    @classmethod
    def _are_keyboard_neighbors(cls, first: str, second: str) -> bool:
        return second in cls.KEYBOARD_NEIGHBORS.get(first, "") or first in cls.KEYBOARD_NEIGHBORS.get(second, "")

    @staticmethod
    def _shared_prefix_length(first: str, second: str) -> int:
        length = 0
        for left, right in zip(first, second):
            if left != right:
                break
            length += 1
        return length

    @classmethod
    def _prune_correction_paths(cls, paths: list[CorrectionPath]) -> list[CorrectionPath]:
        best_by_key: dict[str, CorrectionPath] = {}
        for path in paths:
            current = best_by_key.get(path.key)
            if current and (
                current.cost < path.cost
                or (current.cost == path.cost and current.corrected_syllables < path.corrected_syllables)
                or (
                    current.cost == path.cost
                    and current.corrected_syllables == path.corrected_syllables
                    and current.sort_score <= path.sort_score
                )
            ):
                continue
            best_by_key[path.key] = path
        return sorted(
            best_by_key.values(),
            key=lambda path: (
                path.cost,
                len(path.key),
                path.sort_score,
                path.corrected_syllables,
                len(path.syllables),
                path.key,
            ),
        )[:cls.MAX_CORRECTION_WIDTH]


class PinyinCandidateProvider:
    RECORD_SIZE = 20
    FNV_OFFSET_BASIS = 14_695_981_039_346_656_037
    FNV_PRIME = 1_099_511_628_211
    MAX_BEAM_SYLLABLES = 8
    MAX_BEAM_SPAN = 4
    MAX_BEAM_WIDTH = 8
    MAX_COMPLETION_KEYS = 32
    COMPLETION_RANK_PENALTY = 120_000
    INITIAL_SHORTHAND_PHRASE_BONUS = 350_000
    MAX_ACRONYM_SYLLABLES_PER_LETTER = 16
    MAX_ACRONYM_KEY_SEQUENCES = 4_096
    MAX_ACRONYM_FALLBACK_SEQUENCES = 24
    ACRONYM_PHRASE_BONUS = 600_000
    ACRONYM_FALLBACK_BASE_SCORE = 8_600_000
    MAX_FUZZY_CORRECTION_KEYS = 24
    FUZZY_RANK_PENALTY = 10_000
    FUZZY_CORRECTION_PENALTY = 220_000
    FUZZY_DELETED_CHARACTER_BONUS = 650_000
    MAX_SEGMENTED_PHRASE_INPUT_LENGTH = 18
    MAX_SEGMENTED_PHRASE_SPAN = 6
    MAX_SEGMENTED_PHRASE_WIDTH = 10
    LOOSE_KEY_ALIASES = {
        "sj": [LooseKeyAlias(("shouji",), "手机")],
        "qwer": [LooseKeyAlias(("chuqu", "waner"), "出去玩儿")],
        "ty": [LooseKeyAlias(("tianyu",), "天宇")],
        "ii": [LooseKeyAlias(("o",), "哦")],
    }
    FALLBACK_DICTIONARY = {
        "a": ["啊", "阿"],
        "ai": ["爱", "唉", "矮"],
        "an": ["安", "按", "安全"],
        "ang": ["昂"],
        "ba": ["把", "吧", "爸"],
        "bai": ["百", "白", "摆"],
        "ban": ["办", "半", "班"],
        "bao": ["包", "报", "宝"],
        "bei": ["北", "被", "杯", "北京"],
        "bu": ["不", "部", "步", "不错"],
        "cha": ["查", "差", "茶"],
        "chang": ["长", "常", "场"],
        "chi": ["吃", "持", "迟"],
        "da": ["大", "打", "达"],
        "de": ["的", "得", "德"],
        "di": ["地", "第", "低"],
        "dian": ["点", "电", "店"],
        "dui": ["对", "队"],
        "fa": ["发", "法"],
        "ge": ["个", "哥", "各"],
        "guo": ["国", "过", "果"],
        "hao": ["好", "号", "浩"],
        "he": ["和", "喝", "河"],
        "hen": ["很"],
        "hui": ["会", "回"],
        "jia": ["家", "加", "假"],
        "jian": ["见", "间", "件"],
        "jin": ["进", "今", "近"],
        "jiu": ["就", "九", "久"],
        "kan": ["看"],
        "ke": ["可", "课", "客"],
        "lai": ["来"],
        "le": ["了", "乐"],
        "li": ["里", "理", "力"],
        "ma": ["吗", "妈", "马"],
        "mei": ["没", "美", "每"],
        "men": ["们", "门"],
        "ming": ["明", "名"],
        "ni": ["你", "呢", "尼", "你好", "你们"],
        "nihao": ["你好"],
        "qing": ["请", "清"],
        "qu": ["去", "取"],
        "ren": ["人", "认"],
        "shang": ["上", "商"],
        "shen": ["什", "深", "身"],
        "shenme": ["什么"],
        "shi": ["是", "时", "事", "时间"],
        "shijian": ["时间"],
        "ta": ["他", "她", "它"],
        "tian": ["天", "田"],
        "wan": ["完", "晚", "玩"],
        "wei": ["为", "位", "微"],
        "wo": ["我", "我们"],
        "women": ["我们"],
        "xiang": ["想", "向", "像"],
        "xiao": ["小", "笑"],
        "xiexie": ["谢谢"],
        "yao": ["要"],
        "ye": ["也", "夜"],
        "yi": ["一", "以", "已"],
        "you": ["有", "又", "由"],
        "zai": ["在", "再"],
        "zao": ["早"],
        "zen": ["怎"],
        "zenme": ["怎么"],
        "zhe": ["这", "着"],
        "zhong": ["中", "种", "中国"],
        "zhongguo": ["中国"],
    }

    def __init__(self, resource_dir: Path = DEFAULT_RESOURCE_DIR) -> None:
        self.lexicon_path = resource_dir / "PinyinLexicon.tsv"
        self.index_path = resource_dir / "PinyinLexicon.idx"
        if not self.lexicon_path.exists():
            raise FileNotFoundError(f"Missing lexicon: {self.lexicon_path}")
        if not self.index_path.exists():
            raise FileNotFoundError(f"Missing index: {self.index_path}")
        self.record_count = self.index_path.stat().st_size // self.RECORD_SIZE
        self._record_hashes: list[int] | None = None
        self._record_offsets: list[tuple[int, int]] | None = None

    @classmethod
    def normalized_key(cls, value: str) -> str:
        return "".join(character for character in value.lower() if "a" <= character <= "z")

    def candidates(self, pinyin: str) -> list[PinyinCandidate]:
        key = self.normalized_key(pinyin)
        if not key:
            return []

        cache: dict[str, list[PinyinCandidate]] = {}
        candidates: list[PinyinCandidate] = []
        candidates += self._scored_candidates(key, MatchKind.EXACT, len(key), cache)
        completion_candidates = self._completion_candidates(key, cache)
        candidates += completion_candidates
        candidates += self._initial_shorthand_candidates(key, cache)
        candidates += self._acronym_candidates(key, cache)
        candidates += self._fuzzy_correction_candidates(key, cache)

        segments = PinyinSegmenter.segment(key)
        if len(segments) > 1:
            candidates += self._beam_candidates(segments, key, cache)

        candidates += self._segmented_phrase_candidates(key, cache)

        if completion_candidates or len(candidates) < 16:
            candidates += self._longest_prefix_candidates(key, cache)
        candidates += self._fallback_candidates(key)

        return self._merge(candidates)

    def keyboard_candidates(self, pinyin: str) -> list[PinyinCandidate]:
        key = self.normalized_key(pinyin)
        candidates = self.candidates(key)
        seen = {candidate.text for candidate in candidates}
        for text in (key.upper(), key.lower()):
            if key and text not in seen:
                seen.add(text)
                candidates.append(PinyinCandidate(text, 0, consume_length=len(key), source="letters"))
        return candidates

    def _cached_bundled_candidates(self, key: str, cache: dict[str, list[PinyinCandidate]]) -> list[PinyinCandidate]:
        if key not in cache:
            cache[key] = self._bundled_candidates(key) or []
        return cache[key]

    def _scored_candidates(
        self,
        key: str,
        match: MatchKind,
        consume_length: int,
        cache: dict[str, list[PinyinCandidate]],
    ) -> list[PinyinCandidate]:
        return [
            self._scored_candidate(candidate, match, consume_length)
            for candidate in self._cached_bundled_candidates(key, cache)
        ]

    def _longest_prefix_candidates(self, key: str, cache: dict[str, list[PinyinCandidate]]) -> list[PinyinCandidate]:
        lookup_key = key
        while lookup_key:
            lookup_key = lookup_key[:-1]
            if not lookup_key:
                break
            candidates = self._scored_candidates(lookup_key, MatchKind.PREFIX, len(lookup_key), cache)
            if candidates:
                return candidates
        return []

    def _completion_candidates(self, key: str, cache: dict[str, list[PinyinCandidate]]) -> list[PinyinCandidate]:
        results: list[PinyinCandidate] = []
        for rank, completion in enumerate(PinyinSegmenter.completion_keys(key, self.MAX_COMPLETION_KEYS)):
            for candidate in self._scored_candidates(completion.key, MatchKind.COMPLETION, completion.consume_length, cache)[:4]:
                results.append(replace(
                    candidate,
                    weight=candidate.weight - rank * self.COMPLETION_RANK_PENALTY,
                    source="completion",
                ))
        return results

    def _initial_shorthand_candidates(self, key: str, cache: dict[str, list[PinyinCandidate]]) -> list[PinyinCandidate]:
        results: list[PinyinCandidate] = []
        for shorthand_key in PinyinSegmenter.initial_shorthand_keys(key, self.MAX_COMPLETION_KEYS):
            results += [
                replace(
                    candidate,
                    weight=candidate.weight + self.INITIAL_SHORTHAND_PHRASE_BONUS,
                    source="initial-shorthand",
                )
                for candidate in self._scored_candidates(shorthand_key, MatchKind.COMPLETION, len(key), cache)[:4]
            ]
        return results

    def _acronym_candidates(self, key: str, cache: dict[str, list[PinyinCandidate]]) -> list[PinyinCandidate]:
        sequences = PinyinSegmenter.acronym_key_sequences(
            key,
            self.MAX_ACRONYM_SYLLABLES_PER_LETTER,
            self.MAX_ACRONYM_KEY_SEQUENCES,
        )
        results: list[PinyinCandidate] = []

        for sequence in sequences:
            lookup_key = "".join(sequence)
            results += [
                replace(
                    candidate,
                    weight=candidate.weight + self.ACRONYM_PHRASE_BONUS,
                    source="acronym",
                )
                for candidate in self._scored_candidates(lookup_key, MatchKind.COMPLETION, len(key), cache)[:3]
            ]

        for sequence in sequences[:self.MAX_ACRONYM_FALLBACK_SEQUENCES]:
            results += [
                replace(
                    candidate,
                    weight=candidate.weight + self.ACRONYM_FALLBACK_BASE_SCORE,
                    source="acronym-fallback",
                )
                for candidate in self._phrase_candidates(sequence, len(key), cache)[:2]
            ]

        return self._merge(results)

    def _fuzzy_correction_candidates(self, key: str, cache: dict[str, list[PinyinCandidate]]) -> list[PinyinCandidate]:
        results: list[PinyinCandidate] = []
        for rank, correction in enumerate(PinyinSegmenter.correction_keys(key, self.MAX_FUZZY_CORRECTION_KEYS)):
            corrected = [
                self._fuzzy_candidate(candidate, correction, rank, len(key))
                for candidate in self._scored_candidates(correction.key, MatchKind.FUZZY, len(key), cache)[:6]
            ]
            if not corrected:
                corrected += [
                    self._fuzzy_candidate(candidate, correction, rank, len(key))
                    for candidate in self._phrase_candidates(correction.syllables, len(key), cache)[:4]
                ]
            results += corrected
        return results

    def _beam_candidates(
        self,
        segments: list[str],
        full_key: str,
        cache: dict[str, list[PinyinCandidate]],
    ) -> list[PinyinCandidate]:
        if len(segments) <= 1 or len(segments) > self.MAX_BEAM_SYLLABLES:
            return []

        paths: list[list[BeamPath]] = [[] for _ in range(len(segments) + 1)]
        paths[0] = [BeamPath("", 0, 0)]

        for start in range(len(segments)):
            if not paths[start]:
                continue
            max_end = min(len(segments), start + self.MAX_BEAM_SPAN)
            for path in paths[start]:
                for end in range(start + 1, max_end + 1):
                    lookup_key = "".join(segments[start:end])
                    if lookup_key == full_key:
                        continue
                    limit = 4 if end - start == 1 else 8
                    for candidate in self._cached_bundled_candidates(lookup_key, cache)[:limit]:
                        text = path.text + candidate.text
                        if len(text) > 16:
                            continue
                        score = path.score + self._beam_part_score(candidate, end - start)
                        paths[end].append(BeamPath(text, score, path.parts + 1))
                    paths[end] = self._prune_beam_paths(paths[end])

        results = []
        for path in self._prune_beam_paths(paths[len(segments)]):
            if path.parts <= 1:
                continue
            average_score = path.score // max(1, path.parts)
            score = 6_200_000 + average_score - path.parts * 60_000
            results.append(PinyinCandidate(path.text, score, 2, len(path.text), len(segments), len(full_key), "beam"))
        return results

    def _segmented_phrase_candidates(self, key: str, cache: dict[str, list[PinyinCandidate]]) -> list[PinyinCandidate]:
        if len(key) < 4 or len(key) > self.MAX_SEGMENTED_PHRASE_INPUT_LENGTH:
            return []

        paths: list[list[BeamPath]] = [[] for _ in range(len(key) + 1)]
        paths[0] = [BeamPath("", 0, 0)]

        for start in range(len(key)):
            if not paths[start]:
                continue
            matches = self._segmented_matches(key, start, cache)
            if not matches:
                continue
            for path in paths[start]:
                for match in matches:
                    end = start + match.consume_length
                    text = path.text + match.text
                    if len(text) > 24:
                        continue
                    score = path.score + self._beam_part_score(match, max(1, match.syllable_count))
                    paths[end].append(BeamPath(text, score, path.parts + 1))
            max_end = min(len(key), start + self.MAX_SEGMENTED_PHRASE_SPAN)
            for end in range(start + 1, max_end + 1):
                if paths[end]:
                    paths[end] = self._prune_segmented_phrase_paths(paths[end])

        results = []
        for path in self._prune_segmented_phrase_paths(paths[len(key)]):
            if path.parts <= 1:
                continue
            average_score = path.score // max(1, path.parts)
            score = 2_600_000 + average_score - path.parts * 90_000
            results.append(PinyinCandidate(path.text, score, 4, len(path.text), path.parts, len(key), "segmented"))
        return results

    def _segmented_matches(
        self,
        key: str,
        start: int,
        cache: dict[str, list[PinyinCandidate]],
    ) -> list[PinyinCandidate]:
        max_end = min(len(key), start + self.MAX_SEGMENTED_PHRASE_SPAN)
        if max_end <= start:
            return []

        results: list[PinyinCandidate] = []
        for end in range(max_end, start, -1):
            piece = key[start:end]
            consume_length = end - start
            results += self._scored_candidates(piece, MatchKind.EXACT, consume_length, cache)[:4]
            results += self._loose_alias_candidates(piece, consume_length, cache)[:4]
            results += self._segmented_completion_candidates(piece, consume_length, cache)[:4]

        return sorted(
            results,
            key=lambda candidate: (-candidate.weight, -candidate.consume_length, candidate.text),
        )[:12]

    def _loose_alias_candidates(
        self,
        key: str,
        consume_length: int,
        cache: dict[str, list[PinyinCandidate]],
    ) -> list[PinyinCandidate]:
        aliases = self.LOOSE_KEY_ALIASES.get(key)
        if not aliases:
            return []
        candidates: list[PinyinCandidate] = []
        for alias_index, alias in enumerate(aliases):
            if alias.preferred_text:
                candidates.append(PinyinCandidate(
                    alias.preferred_text,
                    1_800_000 - alias_index * 10_000,
                    4,
                    len(alias.preferred_text),
                    len(alias.pinyin_keys),
                    consume_length,
                    "alias",
                ))
            candidates += self._phrase_candidates(alias.pinyin_keys, consume_length, cache)
        return self._merge(candidates)

    def _phrase_candidates(
        self,
        pinyin_keys: tuple[str, ...],
        consume_length: int,
        cache: dict[str, list[PinyinCandidate]],
    ) -> list[PinyinCandidate]:
        if not pinyin_keys:
            return []
        paths = [BeamPath("", 0, 0)]
        for pinyin_key in pinyin_keys:
            candidates = self._cached_bundled_candidates(pinyin_key, cache)[:3]
            if not candidates:
                return []
            next_paths = []
            for path in paths:
                for candidate in candidates:
                    text = path.text + candidate.text
                    score = path.score + self._beam_part_score(candidate, 1)
                    next_paths.append(BeamPath(text, score, path.parts + 1))
            paths = self._prune_segmented_phrase_paths(next_paths)
        return [
            PinyinCandidate(path.text, path.score // max(1, path.parts), 4, len(path.text), len(pinyin_keys), consume_length, "phrase")
            for path in paths
        ]

    def _segmented_completion_candidates(
        self,
        key: str,
        consume_length: int,
        cache: dict[str, list[PinyinCandidate]],
    ) -> list[PinyinCandidate]:
        results: list[PinyinCandidate] = []
        for rank, completion in enumerate(PinyinSegmenter.completion_keys(key, 12)):
            for candidate in self._scored_candidates(completion.key, MatchKind.COMPLETION, consume_length, cache)[:3]:
                results.append(replace(
                    candidate,
                    weight=candidate.weight - rank * self.COMPLETION_RANK_PENALTY,
                    consume_length=consume_length,
                    source="segmented-completion",
                ))
        return results

    def _fallback_candidates(self, key: str) -> list[PinyinCandidate]:
        candidates: list[PinyinCandidate] = []
        exact = self.FALLBACK_DICTIONARY.get(key)
        if exact:
            candidates += [
                PinyinCandidate(text, 1_000_000 + 10_000 - index, 5, consume_length=len(key), source="fallback")
                for index, text in enumerate(exact)
            ]

        prefix_candidates = []
        for fallback_key in sorted(
            [fallback_key for fallback_key in self.FALLBACK_DICTIONARY if fallback_key.startswith(key)],
            key=lambda fallback_key: (len(fallback_key), fallback_key),
        ):
            prefix_candidates += self.FALLBACK_DICTIONARY[fallback_key]
        candidates += [
            PinyinCandidate(text, 900_000 - index, 5, consume_length=len(key), source="fallback-prefix")
            for index, text in enumerate(prefix_candidates)
        ]
        return candidates

    def _scored_candidate(self, candidate: PinyinCandidate, match: MatchKind, consume_length: int) -> PinyinCandidate:
        if match == MatchKind.EXACT:
            base_score = 10_000_000
            length_bonus = min(candidate.word_length or 0, 8) * 45_000
        elif match == MatchKind.COMPLETION:
            base_score = 8_400_000
            length_bonus = min(candidate.word_length or 0, 8) * 35_000
        elif match == MatchKind.FUZZY:
            base_score = 8_000_000
            length_bonus = min(candidate.word_length or 0, 8) * 35_000
        elif match == MatchKind.PREFIX:
            base_score = 4_800_000
            length_bonus = min(candidate.word_length or 0, 8) * 20_000
        elif match == MatchKind.BEAM:
            base_score = 6_200_000
            length_bonus = min(candidate.word_length or 0, 8) * 25_000
        else:
            base_score = 900_000
            length_bonus = 0

        score = (
            base_score
            + self._dictionary_score(candidate.weight)
            + self._tier_bonus(candidate.tier)
            + length_bonus
            + min(candidate.syllable_count, 6) * 35_000
        )
        return PinyinCandidate(
            candidate.text,
            score,
            candidate.tier,
            candidate.word_length,
            candidate.syllable_count,
            consume_length,
            match.value,
        )

    def _fuzzy_candidate(
        self,
        candidate: PinyinCandidate,
        correction: PinyinCorrection,
        rank: int,
        consume_length: int,
    ) -> PinyinCandidate:
        return replace(
            candidate,
            weight=(
                candidate.weight
                - correction.cost * self.FUZZY_CORRECTION_PENALTY
                - correction.corrected_syllables * 80_000
                - rank * self.FUZZY_RANK_PENALTY
                + max(0, consume_length - len(correction.key)) * self.FUZZY_DELETED_CHARACTER_BONUS
            ),
            consume_length=consume_length,
            source="fuzzy",
        )

    def _beam_part_score(self, candidate: PinyinCandidate, span: int) -> int:
        single_character_penalty = 500_000 if span == 1 and candidate.word_length == 1 else 0
        return (
            self._dictionary_score(candidate.weight)
            + self._tier_bonus(candidate.tier)
            + min(candidate.word_length or 0, 8) * 30_000
            + max(0, span - 1) * 350_000
            - single_character_penalty
        )

    @staticmethod
    def _dictionary_score(weight: int) -> int:
        return min(max(weight, 1), 1_200_000)

    @staticmethod
    def _tier_bonus(tier: int) -> int:
        if tier <= 0:
            return 600_000
        if tier == 1:
            return 420_000
        if tier == 2:
            return 260_000
        if tier == 3:
            return 120_000
        if tier == 4:
            return 40_000
        return 0

    @staticmethod
    def _merge(candidates: list[PinyinCandidate]) -> list[PinyinCandidate]:
        best_by_text: dict[str, PinyinCandidate] = {}
        for candidate in candidates:
            if not candidate.text:
                continue
            current = best_by_text.get(candidate.text)
            if current and current.weight >= candidate.weight:
                continue
            best_by_text[candidate.text] = candidate
        return sorted(
            best_by_text.values(),
            key=lambda candidate: (-candidate.weight, len(candidate.text), candidate.text),
        )

    @staticmethod
    def _prune_beam_paths(paths: list[BeamPath]) -> list[BeamPath]:
        best_by_text: dict[str, BeamPath] = {}
        for path in paths:
            if not path.text and path.parts != 0:
                continue
            current = best_by_text.get(path.text)
            if current and current.score >= path.score:
                continue
            best_by_text[path.text] = path
        return sorted(best_by_text.values(), key=lambda path: (-path.score, path.parts, path.text))[:PinyinCandidateProvider.MAX_BEAM_WIDTH]

    @staticmethod
    def _prune_segmented_phrase_paths(paths: list[BeamPath]) -> list[BeamPath]:
        best_by_text: dict[str, BeamPath] = {}
        for path in paths:
            if not path.text and path.parts != 0:
                continue
            current = best_by_text.get(path.text)
            if current and current.score >= path.score:
                continue
            best_by_text[path.text] = path
        return sorted(best_by_text.values(), key=lambda path: (-path.score, path.parts, path.text))[:PinyinCandidateProvider.MAX_SEGMENTED_PHRASE_WIDTH]

    def _bundled_candidates(self, key: str) -> list[PinyinCandidate] | None:
        records = self._find_records(key)
        if not records:
            return None

        with self.lexicon_path.open("rb") as handle:
            for offset, length in records:
                handle.seek(offset)
                line = handle.read(length).decode("utf-8", errors="strict").rstrip("\r\n")
                fields = [field for field in line.split("\t") if field]
                if not fields or fields[0] != key:
                    continue
                return [
                    self._parse_candidate_field(field, 120 - index)
                    for index, field in enumerate(fields[1:])
                ]
        return None

    def _find_records(self, key: str) -> list[tuple[int, int]]:
        self._load_index()
        assert self._record_hashes is not None
        assert self._record_offsets is not None

        target_hash = self._hash_key(key)
        index = bisect.bisect_left(self._record_hashes, target_hash)
        results = []
        while index < len(self._record_hashes) and self._record_hashes[index] == target_hash:
            results.append(self._record_offsets[index])
            index += 1
        return results

    def _load_index(self) -> None:
        if self._record_hashes is not None:
            return
        hashes: list[int] = []
        offsets: list[tuple[int, int]] = []
        with self.index_path.open("rb") as handle:
            while chunk := handle.read(self.RECORD_SIZE):
                if len(chunk) != self.RECORD_SIZE:
                    break
                key_hash, offset, length = struct.unpack("<QQI", chunk)
                hashes.append(key_hash)
                offsets.append((offset, length))
        self._record_hashes = hashes
        self._record_offsets = offsets

    @classmethod
    def _hash_key(cls, key: str) -> int:
        result = cls.FNV_OFFSET_BASIS
        for byte in key.encode("utf-8"):
            result ^= byte
            result = (result * cls.FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
        return result

    @staticmethod
    def _parse_candidate_field(field: str, fallback_weight: int) -> PinyinCandidate:
        parts = field.split(":")
        if len(parts) >= 5:
            text = ":".join(parts[:-4])
            metadata = parts[-4:]
            return PinyinCandidate(
                text,
                _parse_int(metadata[0], fallback_weight),
                _parse_int(metadata[1], 2),
                _parse_int(metadata[2], len(text)),
                _parse_int(metadata[3], 1),
            )
        if ":" not in field:
            return PinyinCandidate(field, fallback_weight)
        text, weight_text = field.rsplit(":", 1)
        return PinyinCandidate(text, _parse_int(weight_text, fallback_weight))


class KeyboardSimulator:
    def __init__(self, provider: PinyinCandidateProvider) -> None:
        self.provider = provider
        self.composition_buffer = ""

    def type_text(self, text: str) -> list[tuple[str, list[PinyinCandidate]]]:
        snapshots = []
        for character in text:
            if re.match(r"[A-Za-z]", character):
                self.composition_buffer += character.lower()
                snapshots.append((self.composition_buffer, self.candidates()))
        return snapshots

    def candidates(self) -> list[PinyinCandidate]:
        return self.provider.keyboard_candidates(self.composition_buffer)


def _parse_int(value: str, fallback: int) -> int:
    try:
        return int(value)
    except ValueError:
        return fallback


def format_candidates(candidates: list[PinyinCandidate], limit: int, debug: bool) -> list[str]:
    lines = []
    for index, candidate in enumerate(candidates[:limit], start=1):
        if debug:
            lines.append(
                f"{index:>2}. {candidate.text}\t"
                f"score={candidate.weight}\tconsume={candidate.consume_length}\t"
                f"tier={candidate.tier}\tlen={candidate.word_length}\t"
                f"syllables={candidate.syllable_count}\tsource={candidate.source}"
            )
        else:
            lines.append(f"{index:>2}. {candidate.text}")
    return lines


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Simulate FITNEX iOS keyboard pinyin candidate lookup.",
    )
    parser.add_argument("pinyin", help="Pinyin letters to type, for example: nihao")
    parser.add_argument("--limit", type=int, default=30, help="Maximum candidates to print. Default: 30")
    parser.add_argument("--trace", action="store_true", help="Print candidates after each simulated key press")
    parser.add_argument("--debug", action="store_true", help="Print scores, consume lengths, tiers, and candidate source")
    parser.add_argument(
        "--resource-dir",
        type=Path,
        default=DEFAULT_RESOURCE_DIR,
        help="Directory containing PinyinLexicon.tsv and PinyinLexicon.idx",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    configure_stdio()
    args = build_parser().parse_args(argv)
    if args.limit < 1:
        print("--limit must be >= 1", file=sys.stderr)
        return 2

    resource_dir = resolve_resource_dir(args.resource_dir)
    try:
        provider = PinyinCandidateProvider(resource_dir)
    except FileNotFoundError as error:
        print(str(error), file=sys.stderr)
        return 1

    simulator = KeyboardSimulator(provider)
    snapshots = simulator.type_text(args.pinyin)

    if not snapshots:
        normalized = provider.normalized_key(args.pinyin)
        print(f"No pinyin letters found in input: {args.pinyin!r}")
        if normalized:
            print(f"Normalized key: {normalized}")
        return 0

    if args.trace:
        for key, candidates in snapshots:
            print(f"[{key}]")
            print("\n".join(format_candidates(candidates, args.limit, args.debug)))
            print()
    else:
        key, candidates = snapshots[-1]
        print(f"Pinyin: {key}")
        print("\n".join(format_candidates(candidates, args.limit, args.debug)))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
