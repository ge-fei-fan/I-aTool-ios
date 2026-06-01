#!/usr/bin/env python3
"""Regression checks for letter keyboard key sizing and third-row layout."""

from __future__ import annotations

import re
import struct
import zlib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
KEYBOARD_SOURCE = REPO_ROOT / "SimpaninKeyboard" / "KeyboardViewControllerLegacy.swift"
PREVIEW_SOURCE = REPO_ROOT / "docs" / "previews" / "keyboard-letter-layout-preview.html"
LANGUAGE_PREVIEW_SOURCE = REPO_ROOT / "docs" / "previews" / "language-switch-icon-preview.html"
SHIFT_UPPER_IMAGE = REPO_ROOT / "ios-icon" / "澶у啓鍥炬爣.png"
SHIFT_LOWER_IMAGE = REPO_ROOT / "ios-icon" / "灏忓啓鍥炬爣.png"
TRANSLATE_IMAGE = REPO_ROOT / "ios-icon" / "缈昏瘧.png"


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start == -1:
        return ""
    brace = source.find("{", start)
    if brace == -1:
        return ""

    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    return ""


def row3_definition(source: str) -> str:
    match = re.search(r"let row3 = (.*?)\n\s*let row4", source, re.S)
    return match.group(1).strip() if match else ""


def number_third_row_definition(source: str) -> str:
    match = re.search(
        r"private var numberRows: \[\[KeySpec\]\] \{\s*\[\s*"
        r'"1234567890".*?,\s*'
        r'punctuationKeys\(\["-", "/", ":", ";", "\(", "\)", "\$", "&", "@", "\\""\]\),\s*'
        r"(.*?),\s*\[",
        source,
        re.S,
    )
    return match.group(1).strip() if match else ""


def symbol_third_row_definition(source: str) -> str:
    match = re.search(
        r"private var symbolRows: \[\[KeySpec\]\] \{\s*\[\s*"
        r'punctuationKeys\(\["\[", "\]", "\{", "\}", "#", "%", "\^", "\*", "\+", "="\]\),\s*'
        r'punctuationKeys\(\["_", "\\\\", "\|", "~", "<", ">", ".*?"\]\),\s*'
        r"(.*?),\s*\[",
        source,
        re.S,
    )
    return match.group(1).strip() if match else ""


def png_alpha_summary(path: Path) -> dict[str, object]:
    with path.open("rb") as handle:
        if handle.read(8) != b"\x89PNG\r\n\x1a\n":
            return {"is_png": False}

        width = height = bit_depth = color_type = None
        idat_chunks: list[bytes] = []
        while True:
            header = handle.read(8)
            if not header:
                break
            length, chunk_type = struct.unpack(">I4s", header)
            data = handle.read(length)
            handle.read(4)
            if chunk_type == b"IHDR":
                width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", data)
            elif chunk_type == b"IDAT":
                idat_chunks.append(data)
            elif chunk_type == b"IEND":
                break

    if color_type not in (4, 6):
        return {"is_png": True, "has_alpha": False, "color_type": color_type}

    channels = {4: 2, 6: 4}[color_type]
    bytes_per_pixel = channels * bit_depth // 8
    stride = width * bytes_per_pixel
    raw = zlib.decompress(b"".join(idat_chunks))
    previous = bytearray(stride)
    rows: list[bytearray] = []
    position = 0

    def paeth(left: int, up: int, up_left: int) -> int:
        prediction = left + up - up_left
        left_diff = abs(prediction - left)
        up_diff = abs(prediction - up)
        up_left_diff = abs(prediction - up_left)
        if left_diff <= up_diff and left_diff <= up_left_diff:
            return left
        if up_diff <= up_left_diff:
            return up
        return up_left

    for _ in range(height):
        filter_type = raw[position]
        position += 1
        scanline = bytearray(raw[position:position + stride])
        position += stride
        if filter_type == 1:
            for index in range(bytes_per_pixel, stride):
                scanline[index] = (scanline[index] + scanline[index - bytes_per_pixel]) & 255
        elif filter_type == 2:
            for index in range(stride):
                scanline[index] = (scanline[index] + previous[index]) & 255
        elif filter_type == 3:
            for index in range(stride):
                left = scanline[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
                up = previous[index]
                scanline[index] = (scanline[index] + ((left + up) // 2)) & 255
        elif filter_type == 4:
            for index in range(stride):
                left = scanline[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
                up = previous[index]
                up_left = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
                scanline[index] = (scanline[index] + paeth(left, up, up_left)) & 255
        previous = scanline
        rows.append(scanline)

    alpha_offset = 1 if color_type == 4 else 3

    def alpha_at(x: int, y: int) -> int:
        return rows[y][x * bytes_per_pixel + alpha_offset]

    corners = [
        alpha_at(0, 0),
        alpha_at(width - 1, 0),
        alpha_at(0, height - 1),
        alpha_at(width - 1, height - 1),
    ]

    return {
        "is_png": True,
        "has_alpha": True,
        "color_type": color_type,
        "corner_alpha": corners,
    }


def main() -> int:
    source = KEYBOARD_SOURCE.read_text(encoding="utf-8")
    preview = PREVIEW_SOURCE.read_text(encoding="utf-8")
    language_preview = LANGUAGE_PREVIEW_SOURCE.read_text(encoding="utf-8") if LANGUAGE_PREVIEW_SOURCE.exists() else ""
    shift_upper_image = png_alpha_summary(SHIFT_UPPER_IMAGE) if SHIFT_UPPER_IMAGE.exists() else {"is_png": False}
    shift_lower_image = png_alpha_summary(SHIFT_LOWER_IMAGE) if SHIFT_LOWER_IMAGE.exists() else {"is_png": False}
    translate_image = png_alpha_summary(TRANSLATE_IMAGE) if TRANSLATE_IMAGE.exists() else {"is_png": False}
    row3 = row3_definition(source)
    number_row3 = number_third_row_definition(source)
    symbol_row3 = symbol_third_row_definition(source)
    width_helper = function_body(source, "private func usesLetterKeyWidth(for kind: KeyKind) -> Bool")
    make_button = function_body(source, "private func makeButton(for spec: KeySpec) -> KeyboardKeyButton")
    key_handler = function_body(source, "private func handle(_ kind: KeyKind)")

    checks = {
        "letter third row keeps shift pinned left": row3.startswith("[KeySpec(.shift), KeySpec(.spacer, widthUnit: 0.5)]"),
        "letter third row keeps backspace pinned right": row3.endswith('+ [KeySpec(.spacer, widthUnit: 0.5), KeySpec(.backspace)]'),
        "letter third row keeps seven middle letters": '"zxcvbnm".map { KeySpec(.character(String($0))) }' in row3,
        "shift and backspace no longer use wide key units": "KeySpec(.shift, widthUnit: 1.5)" not in row3 and "KeySpec(.backspace, widthUnit: 1.5)" not in row3,
        "letter key width helper exists": bool(width_helper),
        "letter key width helper includes only characters": "case .character(_):" in width_helper and ".shift" not in width_helper and ".backspace" not in width_helper,
        "letter row width constraint applies through helper": "if usesUniformLetterKeys, usesLetterKeyWidth(for: key.kind)" in source,
        "third-row edge controls use square key width": "isThirdRowEdgeControlKey(key.kind)" in source and "button.widthAnchor.constraint(equalToConstant: 42).isActive = true" in source,
        "number third row edge keys are not wide": 'KeySpec(.modeSwitch(.symbols), title: "#+=", widthUnit: 1.35)' not in number_row3 and "KeySpec(.backspace, widthUnit: 1.35)" not in number_row3,
        "symbol third row edge keys are not wide": 'KeySpec(.modeSwitch(.numbers), title: "123", widthUnit: 1.35)' not in symbol_row3 and "KeySpec(.backspace, widthUnit: 1.35)" not in symbol_row3,
        "third-row edge helper includes mode switches": "case .modeSwitch(.numbers), .modeSwitch(.symbols), .shift, .backspace:" in source,
        "square edge rows equalize middle keys": "squareEdgeRowFlexibleButtons" in source and "button.widthAnchor.constraint(equalTo: squareEdgeRowFlexibleButtons[0].widthAnchor)" in source,
        "letter row side-key expansion was removed": "var sideKeys: [UIButton]" not in source and "sideKeys.append(button)" not in source,
        "keyboard icon point size stays 24pt": "private static let keyboardIconPointSize: CGFloat = 24" in source,
        "shift key image point size constant exists": "private static let shiftKeyImagePointSize: CGFloat = 30" in source,
        "shift key image alignment constant exists": "private static let shiftKeyImageVerticalAlignment: CGFloat = 0.18" in source,
        "keyboard key icon asset enum exists": "private enum KeyboardKeyIconAsset" in source and "case shiftUpper" in source and "case shiftLower" in source and "case backspace" in source,
        "shift no longer uses cat1 asset": 'return "cat1"' not in source,
        "shift upper image exists": SHIFT_UPPER_IMAGE.exists(),
        "shift lower image exists": SHIFT_LOWER_IMAGE.exists(),
        "shift upper image is a png": shift_upper_image.get("is_png") is True,
        "shift lower image is a png": shift_lower_image.get("is_png") is True,
        "shift lower image has alpha channel": shift_lower_image.get("has_alpha") is True,
        "shift lower image background corners are transparent": (
            isinstance(shift_lower_image.get("corner_alpha"), list)
            and shift_lower_image.get("corner_alpha")[:3] == [0, 0, 0]
        ),
        "shift upper asset maps to uppercase icon": 'return "澶у啓鍥炬爣"' in source,
        "shift lower asset maps to lowercase icon": 'return "灏忓啓鍥炬爣"' in source,
        "backspace uses clear-symbol asset": 'return "icons8-clear-symbol-48"' in source,
        "shift primary path uses state-specific keyboard key asset": "let shiftAsset: KeyboardKeyIconAsset = shiftState == .on ? .shiftUpper : .shiftLower" in source and "button.setImage(keyboardKeyIcon(shiftAsset" in source,
        "backspace primary path uses keyboard key asset": 'button.setImage(keyboardKeyIcon(.backspace' in source,
        "keyboard key icon helper avoids Self in default arguments": "pointSize: CGFloat = Self.keyboardIconPointSize" not in source,
        "shift uses original-color inset image": "keyboardKeyIcon(shiftAsset, fallbackSystemName: \"shift\", fallbackWeight: .light, pointSize: Self.shiftKeyImagePointSize, renderingMode: .alwaysOriginal, aspectFill: true, verticalAlignment: Self.shiftKeyImageVerticalAlignment)" in source,
        "backspace stays templated": "keyboardKeyIcon(.backspace, fallbackSystemName: \"delete.left\", fallbackWeight: .light)" in source,
        "keyboard image resizer supports aspect fill focus": "verticalAlignment: CGFloat = 0.5" in source and "let maxOffsetY = max(0, scaledSize.height - size.height)" in source and "let clampedVerticalAlignment = min(max(verticalAlignment, 0), 1)" in source and "y: -maxOffsetY * clampedVerticalAlignment" in source,
        "preview shift image keeps key background visible": ".key__icon--shift {" in preview and "inset: 4px;" in preview,
        "preview shift image keeps original colors": ".key__icon--shift .key__icon-image {" in preview and "filter: none;" in preview,
        "preview shift image defaults to lowercase icon": 'src="../../ios-icon/灏忓啓鍥炬爣.png"' in preview,
        "preview shift image switches to uppercase icon": 'shiftIconImage.src = shiftOn ? "../../ios-icon/澶у啓鍥炬爣.png" : "../../ios-icon/灏忓啓鍥炬爣.png"' in preview,
        "language switch preview exists": bool(language_preview),
        "language switch preview renders both states": 'data-state="chinese"' in language_preview and 'data-state="english"' in language_preview,
        "language switch preview uses stacked glyph icon": "language-icon__glyph language-icon__glyph--chinese" in language_preview and "language-icon__glyph language-icon__glyph--english" in language_preview,
        "language switch preview highlights chinese in chinese mode": '.language-key[data-state="chinese"] .language-icon__glyph--chinese' in language_preview and "#58a6ff" in language_preview,
        "language switch preview highlights english in english mode": '.language-key[data-state="english"] .language-icon__glyph--english' in language_preview and "color: var(--blue);" in language_preview,
        "language switch icon view exists in keyboard": "private final class LanguageSwitchIconView" in source,
        "language switch key uses icon view": "configureLanguageSwitchButton(button)" in source,
        "language switch title is not rendered as plain text": "} else if case .languageSwitch = spec.kind {\n            configureLanguageSwitchButton(button)\n        } else {\n            button.setTitle(title(for: spec), for: .normal)" in make_button,
        "language switch uses same blue for current-language glyphs": "let activeColor = UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1)" in source and "chineseLabel.textColor = highlightsChinese ? activeColor : inactiveColor" in source and "englishLabel.textColor = highlightsChinese ? inactiveColor : activeColor" in source,
        "theme refresh updates language icon": "updateLanguageSwitchIconAppearance" in source,
        "language switch preserves current shift state": "preferredShiftState(for: inputLanguage)" not in key_handler,
        "translate icon asset exists": TRANSLATE_IMAGE.exists(),
        "translate icon image is a png": translate_image.get("is_png") is True,
        "translate keyboard icon asset exists": "case translate" in source and 'return "缈昏瘧"' in source,
        "candidate bar third visible utility icon uses translate asset": '(asset: .heart, fallbackSystemName: "heart", label: "Quick fill", dismissesKeyboard: false, opensQuickFill: true, opensTranslation: false),\n            (asset: .translate, fallbackSystemName: "text.translate", label: "Translate", dismissesKeyboard: false, opensQuickFill: false, opensTranslation: true),' in source,
        "translate utility icon shares unified styling": "configureUtilityIconButton(\n                button,\n                asset: item.asset," in source and "button.setImage(keyboardIcon(asset, fallbackSystemName: fallbackSystemName), for: .normal)" in source,
    }

    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        print("Keyboard letter key layout checks failed:")
        for name in failed:
            print(f"- {name}")
        return 1

    print("Keyboard letter key layout checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
