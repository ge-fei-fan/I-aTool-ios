import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum KeyboardMode {
        case letters
        case numbers
    }

    private enum ShiftState {
        case off
        case on
    }

    private let candidateProvider = PinyinCandidateProvider()
    private let rootStack = UIStackView()
    private let candidateScrollView = UIScrollView()
    private let candidateStack = UIStackView()
    private let bufferLabel = UILabel()
    private var bufferWidthConstraint: NSLayoutConstraint?
    private var keyButtons: [UIButton] = []
    private var compositionBuffer = ""
    private var keyboardMode: KeyboardMode = .letters
    private var shiftState: ShiftState = .off

    private var isDark: Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard()
        renderKeyboard()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    private func setupKeyboard() {
        view.backgroundColor = keyboardBackground

        rootStack.axis = .vertical
        rootStack.spacing = 7
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 258)
        ])

        candidateScrollView.showsHorizontalScrollIndicator = false
        candidateScrollView.alwaysBounceHorizontal = true
        rootStack.addArrangedSubview(candidateScrollView)
        candidateScrollView.heightAnchor.constraint(equalToConstant: 38).isActive = true

        candidateStack.axis = .horizontal
        candidateStack.spacing = 6
        candidateStack.alignment = .fill
        candidateStack.distribution = .fill
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScrollView.addSubview(candidateStack)

        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func renderKeyboard() {
        keyButtons.removeAll()
        rootStack.arrangedSubviews.dropFirst().forEach { view in
            rootStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let rows: [[KeySpec]]
        switch keyboardMode {
        case .letters:
            rows = letterRows
        case .numbers:
            rows = numberRows
        }

        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 6
            rowStack.alignment = .fill
            rowStack.distribution = .fillProportionally

            for key in row {
                let button = makeButton(for: key)
                button.widthUnit = key.widthUnit
                rowStack.addArrangedSubview(button)
                button.heightAnchor.constraint(equalToConstant: 44).isActive = true
                keyButtons.append(button)
            }

            rootStack.addArrangedSubview(rowStack)
        }

        updateCandidates()
        applyTheme()
    }

    private var letterRows: [[KeySpec]] {
        let row1 = "qwertyuiop".map { KeySpec(.character(String($0))) }
        let row2 = "asdfghjkl".map { KeySpec(.character(String($0))) }
        let row3 = [KeySpec(.shift, widthUnit: 1.35)] + "zxcvbnm".map { KeySpec(.character(String($0))) } + [KeySpec(.backspace, widthUnit: 1.35)]
        let row4 = [
            KeySpec(.modeSwitch, title: "123", widthUnit: 1.35),
            KeySpec(.space, title: "空格", widthUnit: 4.8),
            KeySpec(.returnKey, title: "换行", widthUnit: 1.55)
        ]
        return [row1, row2, row3, row4]
    }

    private var numberRows: [[KeySpec]] {
        [
            "1234567890".map { KeySpec(.character(String($0))) },
            ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { KeySpec(.character($0)) },
            [KeySpec(.modeSwitch, title: "拼音", widthUnit: 1.35)] + [".", ",", "?", "!", "'"].map { KeySpec(.character($0)) } + [KeySpec(.backspace, widthUnit: 1.35)],
            [
                KeySpec(.modeSwitch, title: "拼音", widthUnit: 1.35),
                KeySpec(.space, title: "空格", widthUnit: 4.8),
                KeySpec(.returnKey, title: "换行", widthUnit: 1.55)
            ]
        ]
    }

    private func makeButton(for spec: KeySpec) -> KeyboardKeyButton {
        let button = KeyboardKeyButton(type: .system)
        button.layer.cornerRadius = 6
        button.layer.shadowOpacity = 0.22
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.titleLabel?.font = spec.kind.isPrimary ? .systemFont(ofSize: 22, weight: .regular) : .systemFont(ofSize: 16, weight: .regular)
        button.setTitle(title(for: spec), for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.handle(spec.kind)
        }, for: .touchUpInside)
        return button
    }

    private func title(for spec: KeySpec) -> String {
        if let title = spec.title {
            return title
        }

        switch spec.kind {
        case .character(let value):
            return shiftState == .on ? value.uppercased() : value
        case .shift:
            return shiftState == .on ? "⇧" : "⇧"
        case .backspace:
            return "⌫"
        case .space:
            return "空格"
        case .returnKey:
            return "换行"
        case .modeSwitch:
            return keyboardMode == .letters ? "123" : "拼音"
        }
    }

    private func handle(_ kind: KeyKind) {
        switch kind {
        case .character(let value):
            if keyboardMode == .letters, value.rangeOfCharacter(from: .letters) != nil {
                compositionBuffer.append(value.lowercased())
                updateCandidates()
            } else {
                commitCompositionIfNeeded()
                textDocumentProxy.insertText(value)
            }
        case .shift:
            shiftState = shiftState == .on ? .off : .on
            renderKeyboard()
        case .backspace:
            if !compositionBuffer.isEmpty {
                compositionBuffer.removeLast()
                updateCandidates()
            } else {
                textDocumentProxy.deleteBackward()
            }
        case .space:
            if let first = candidates(for: compositionBuffer).first {
                textDocumentProxy.insertText(first)
                compositionBuffer = ""
                updateCandidates()
            } else {
                textDocumentProxy.insertText(" ")
            }
        case .returnKey:
            commitCompositionIfNeeded()
            textDocumentProxy.insertText("\n")
        case .modeSwitch:
            commitCompositionIfNeeded()
            keyboardMode = keyboardMode == .letters ? .numbers : .letters
            renderKeyboard()
        }
    }

    private func commitCompositionIfNeeded() {
        guard !compositionBuffer.isEmpty else { return }
        if let first = candidates(for: compositionBuffer).first {
            textDocumentProxy.insertText(first)
        } else {
            textDocumentProxy.insertText(compositionBuffer)
        }
        compositionBuffer = ""
        updateCandidates()
    }

    private func updateCandidates() {
        candidateStack.arrangedSubviews.forEach { view in
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        bufferLabel.text = compositionBuffer.isEmpty ? "中文拼音" : compositionBuffer
        bufferLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        bufferLabel.textColor = secondaryText
        bufferLabel.textAlignment = .center
        bufferLabel.backgroundColor = candidateBackground
        bufferLabel.layer.cornerRadius = 8
        bufferLabel.clipsToBounds = true
        candidateStack.addArrangedSubview(bufferLabel)
        bufferWidthConstraint?.isActive = false
        bufferWidthConstraint = bufferLabel.widthAnchor.constraint(equalToConstant: 88)
        bufferWidthConstraint?.isActive = true

        let candidates: [String]
        if compositionBuffer.isEmpty {
            candidates = []
        } else {
            candidates = self.candidates(for: compositionBuffer)
        }
        if candidates.isEmpty {
            let hint = UILabel()
            hint.text = compositionBuffer.isEmpty ? "输入拼音后选择候选词" : "无候选，空格提交拼音"
            hint.font = .systemFont(ofSize: 13, weight: .regular)
            hint.textColor = secondaryText
            candidateStack.addArrangedSubview(hint)
            return
        }

        for candidate in candidates {
            let button = UIButton(type: .system)
            button.setTitle(candidate, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 18, weight: .regular)
            button.setTitleColor(primaryText, for: .normal)
            button.backgroundColor = candidateBackground
            button.layer.cornerRadius = 8
            button.addAction(UIAction { [weak self] _ in
                self?.textDocumentProxy.insertText(candidate)
                self?.compositionBuffer = ""
                self?.updateCandidates()
            }, for: .touchUpInside)
            candidateStack.addArrangedSubview(button)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
    }

    private func applyTheme() {
        view.backgroundColor = keyboardBackground
        bufferLabel.backgroundColor = candidateBackground
        bufferLabel.textColor = secondaryText

        for button in keyButtons {
            let title = button.title(for: .normal) ?? ""
            let isSpecial = ["123", "拼音", "⌫", "⇧", "换行"].contains(title)
            button.backgroundColor = isSpecial ? specialKeyBackground : keyBackground
            button.setTitleColor(primaryText, for: .normal)
            button.layer.shadowColor = shadowColor.cgColor
        }
    }

    private var keyboardBackground: UIColor {
        isDark ? UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1)
    }

    private var keyBackground: UIColor {
        isDark ? UIColor(red: 0.39, green: 0.39, blue: 0.41, alpha: 1) : .white
    }

    private var specialKeyBackground: UIColor {
        isDark ? UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1)
    }

    private var candidateBackground: UIColor {
        isDark ? UIColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1) : UIColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1)
    }

    private var primaryText: UIColor {
        isDark ? .white : .black
    }

    private var secondaryText: UIColor {
        isDark ? UIColor(white: 0.78, alpha: 1) : UIColor(white: 0.35, alpha: 1)
    }

    private var shadowColor: UIColor {
        isDark ? .black : UIColor(white: 0.45, alpha: 1)
    }

    private func candidates(for pinyin: String) -> [String] {
        guard !pinyin.isEmpty else { return [] }
        return candidateProvider.candidates(for: pinyin)
    }
}

private struct KeySpec {
    let kind: KeyKind
    let title: String?
    let widthUnit: CGFloat

    init(_ kind: KeyKind, title: String? = nil, widthUnit: CGFloat = 1) {
        self.kind = kind
        self.title = title
        self.widthUnit = widthUnit
    }
}

private final class KeyboardKeyButton: UIButton {
    var widthUnit: CGFloat = 1

    override var intrinsicContentSize: CGSize {
        CGSize(width: 32 * widthUnit, height: 44)
    }
}

private enum KeyKind {
    case character(String)
    case shift
    case backspace
    case space
    case returnKey
    case modeSwitch

    var isPrimary: Bool {
        if case .character = self {
            return true
        }
        return false
    }
}

private final class PinyinCandidateProvider {
    private struct IndexRecord {
        let key: String
        let offset: UInt64
        let length: Int
    }

    private static let recordSize = 28
    private static let keySize = 16

    private let lexiconURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "tsv")
    private let indexURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "idx")
    private let recordCount: Int

    init() {
        if let indexURL,
           let size = try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.size] as? NSNumber {
            recordCount = size.intValue / Self.recordSize
        } else {
            recordCount = 0
        }
    }

    func candidates(for pinyin: String) -> [String] {
        let key = Self.normalizedKey(pinyin)
        guard !key.isEmpty else { return [] }

        if let resourceCandidates = bundledCandidates(for: key), !resourceCandidates.isEmpty {
            return resourceCandidates
        }

        if let fallback = Self.fallbackDictionary[key] {
            return fallback
        }

        return Self.fallbackDictionary
            .filter { $0.key.hasPrefix(key) }
            .sorted { $0.key.count == $1.key.count ? $0.key < $1.key : $0.key.count < $1.key.count }
            .flatMap(\.value)
    }

    private func bundledCandidates(for key: String) -> [String]? {
        guard let lexiconURL, let indexURL, recordCount > 0 else { return nil }
        var lookupKey = key
        var matchedRecord: IndexRecord?

        while !lookupKey.isEmpty {
            if let record = findRecord(for: lookupKey, in: indexURL) {
                matchedRecord = record
                break
            }
            lookupKey.removeLast()
        }

        guard let record = matchedRecord else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: lexiconURL) else { return nil }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: record.offset)
            let data = try handle.read(upToCount: record.length) ?? Data()
            guard let line = String(data: data, encoding: .utf8) else { return nil }
            return line
                .trimmingCharacters(in: .newlines)
                .split(separator: "\t", omittingEmptySubsequences: true)
                .dropFirst()
                .map(String.init)
        } catch {
            return nil
        }
    }

    private func findRecord(for key: String, in indexURL: URL) -> IndexRecord? {
        guard let handle = try? FileHandle(forReadingFrom: indexURL) else { return nil }
        defer { try? handle.close() }

        var low = 0
        var high = recordCount - 1

        while low <= high {
            let mid = (low + high) / 2
            guard let record = readRecord(at: mid, from: handle) else { return nil }
            let comparison = record.key.compare(key)

            if comparison == .orderedSame {
                return record
            } else if comparison == .orderedAscending {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return nil
    }

    private func readRecord(at index: Int, from handle: FileHandle) -> IndexRecord? {
        do {
            try handle.seek(toOffset: UInt64(index * Self.recordSize))
            let data = try handle.read(upToCount: Self.recordSize) ?? Data()
            guard data.count == Self.recordSize else { return nil }

            let keyData = data.prefix(Self.keySize).prefix { $0 != 0 }
            guard let key = String(data: Data(keyData), encoding: .utf8) else { return nil }

            let offset = Self.uint64LE(data, start: 16)
            let length = Int(Self.uint32LE(data, start: 24))
            return IndexRecord(key: key, offset: offset, length: length)
        } catch {
            return nil
        }
    }

    private static func normalizedKey(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.compactMap { scalar in
            guard scalar.value >= 97 && scalar.value <= 122 else { return nil }
            return Character(scalar)
        })
    }

    private static func uint64LE(_ data: Data, start: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<8 {
            result |= UInt64(data[start + index]) << UInt64(index * 8)
        }
        return result
    }

    private static func uint32LE(_ data: Data, start: Int) -> UInt32 {
        var result: UInt32 = 0
        for index in 0..<4 {
            result |= UInt32(data[start + index]) << UInt32(index * 8)
        }
        return result
    }

    private static let fallbackDictionary: [String: [String]] = [
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
        "zhongguo": ["中国"]
    ]
}
