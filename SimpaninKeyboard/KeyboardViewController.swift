import os
import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum KeyboardMode {
        case letters
        case numbers

        var logValue: String {
            switch self {
            case .letters:
                return "letters"
            case .numbers:
                return "numbers"
            }
        }
    }

    private enum ShiftState {
        case off
        case on

        var logValue: String {
            switch self {
            case .off:
                return "off"
            case .on:
                return "on"
            }
        }
    }

    private let keyboardLog = SharedKeyboardLogStore()
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
    private var didAppear = false

    private var isDark: Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    private var fileLogAllowed: Bool {
        didAppear && hasFullAccess && keyboardLog.sharedContainerAvailable
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard()
        renderKeyboard()
        keyboardLog.record(
            "viewDidLoad",
            metadata: ["fullAccess": "\(hasFullAccess)"],
            fileLoggingEnabled: false
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardLog.record(
            "viewWillAppear",
            metadata: ["fullAccess": "\(hasFullAccess)"],
            fileLoggingEnabled: false
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
        keyboardLog.setFileLoggingEnabled(fileLogAllowed)
        keyboardLog.writeStartupProbe(
            event: "viewDidAppear",
            metadata: [
                "fullAccess": "\(hasFullAccess)",
                "appGroupAvailable": "\(keyboardLog.sharedContainerAvailable)"
            ]
        )
        keyboardLog.record(
            "viewDidAppear",
            metadata: [
                "fullAccess": "\(hasFullAccess)",
                "appGroupAvailable": "\(keyboardLog.sharedContainerAvailable)"
            ],
            fileLoggingEnabled: fileLogAllowed
        )
        if hasFullAccess && !keyboardLog.sharedContainerAvailable {
            keyboardLog.record(
                "appGroupUnavailable",
                metadata: ["fullAccess": "true"],
                level: "warning",
                fileLoggingEnabled: false
            )
        }
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
        let modeBeforeRender = keyboardMode.logValue
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
        keyboardLog.record(
            "keyboard rendered",
            metadata: [
                "mode": modeBeforeRender,
                "keyCount": "\(keyButtons.count)",
                "fullAccess": "\(hasFullAccess)"
            ],
            fileLoggingEnabled: fileLogAllowed
        )
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
        let previousMode = keyboardMode
        keyboardLog.record(
            "key tap begin",
            metadata: [
                "keyKind": kind.logValue,
                "mode": keyboardMode.logValue,
                "bufferLength": "\(compositionBuffer.count)"
            ],
            fileLoggingEnabled: false
        )

        switch kind {
        case .character(let value):
            if keyboardMode == .letters, value.rangeOfCharacter(from: .letters) != nil {
                compositionBuffer.append(value.lowercased())
                updateCandidates()
                keyboardLog.record(
                    "letter input",
                    metadata: [
                        "bufferLength": "\(compositionBuffer.count)",
                        "mode": keyboardMode.logValue
                    ],
                    fileLoggingEnabled: fileLogAllowed
                )
            } else {
                commitCompositionIfNeeded()
                textDocumentProxy.insertText(value)
                keyboardLog.record(
                    "direct character input",
                    metadata: [
                        "mode": keyboardMode.logValue,
                        "characterKind": value.rangeOfCharacter(from: .decimalDigits) != nil ? "digit" : "symbol"
                    ],
                    fileLoggingEnabled: fileLogAllowed
                )
            }
        case .shift:
            shiftState = shiftState == .on ? .off : .on
            renderKeyboard()
            keyboardLog.record(
                "shift toggled",
                metadata: ["shift": shiftState.logValue],
                fileLoggingEnabled: fileLogAllowed
            )
        case .backspace:
            if !compositionBuffer.isEmpty {
                compositionBuffer.removeLast()
                updateCandidates()
                keyboardLog.record(
                    "buffer backspace",
                    metadata: ["bufferLength": "\(compositionBuffer.count)"],
                    fileLoggingEnabled: fileLogAllowed
                )
            } else {
                textDocumentProxy.deleteBackward()
                keyboardLog.record("document backspace", fileLoggingEnabled: fileLogAllowed)
            }
        case .space:
            if let first = candidates(for: compositionBuffer).first {
                textDocumentProxy.insertText(first)
                keyboardLog.record(
                    "space committed candidate",
                    metadata: ["bufferLength": "\(compositionBuffer.count)"],
                    fileLoggingEnabled: fileLogAllowed
                )
                compositionBuffer = ""
                updateCandidates()
            } else {
                textDocumentProxy.insertText(" ")
                keyboardLog.record("space inserted", fileLoggingEnabled: fileLogAllowed)
            }
        case .returnKey:
            commitCompositionIfNeeded()
            textDocumentProxy.insertText("\n")
            keyboardLog.record("return inserted", fileLoggingEnabled: fileLogAllowed)
        case .modeSwitch:
            commitCompositionIfNeeded()
            keyboardMode = keyboardMode == .letters ? .numbers : .letters
            renderKeyboard()
            keyboardLog.record(
                "mode switched",
                metadata: [
                    "from": previousMode.logValue,
                    "to": keyboardMode.logValue
                ],
                fileLoggingEnabled: fileLogAllowed
            )
        }

        keyboardLog.record(
            "key tap end",
            metadata: [
                "keyKind": kind.logValue,
                "mode": keyboardMode.logValue,
                "bufferLength": "\(compositionBuffer.count)"
            ],
            fileLoggingEnabled: fileLogAllowed
        )
    }

    private func commitCompositionIfNeeded() {
        guard !compositionBuffer.isEmpty else { return }
        let bufferLength = compositionBuffer.count
        if let first = candidates(for: compositionBuffer).first {
            textDocumentProxy.insertText(first)
            keyboardLog.record(
                "composition committed candidate",
                metadata: ["bufferLength": "\(bufferLength)"],
                fileLoggingEnabled: fileLogAllowed
            )
        } else {
            textDocumentProxy.insertText(compositionBuffer)
            keyboardLog.record(
                "composition committed fallback",
                metadata: ["bufferLength": "\(bufferLength)"],
                level: "warning",
                fileLoggingEnabled: fileLogAllowed
            )
        }
        compositionBuffer = ""
        updateCandidates()
    }

    private func updateCandidates() {
        let startedAt = Date()
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
        let durationMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        keyboardLog.record(
            "candidates updated",
            metadata: [
                "bufferLength": "\(compositionBuffer.count)",
                "candidateCount": "\(candidates.count)",
                "durationMS": "\(durationMS)"
            ],
            fileLoggingEnabled: fileLogAllowed
        )
        if candidates.isEmpty {
            let hint = UILabel()
            hint.text = compositionBuffer.isEmpty ? "输入拼音后选择候选词" : "无候选，空格提交拼音"
            hint.font = .systemFont(ofSize: 13, weight: .regular)
            hint.textColor = secondaryText
            candidateStack.addArrangedSubview(hint)
            return
        }

        for (index, candidate) in candidates.prefix(5).enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(candidate, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 18, weight: .regular)
            button.setTitleColor(primaryText, for: .normal)
            button.backgroundColor = candidateBackground
            button.layer.cornerRadius = 8
            button.addAction(UIAction { [weak self] _ in
                self?.textDocumentProxy.insertText(candidate)
                self?.keyboardLog.record(
                    "candidate selected",
                    metadata: [
                        "candidateIndex": "\(index)",
                        "bufferLength": "\(self?.compositionBuffer.count ?? 0)"
                    ],
                    fileLoggingEnabled: self?.fileLogAllowed ?? false
                )
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

    var logValue: String {
        switch self {
        case .character:
            return "character"
        case .shift:
            return "shift"
        case .backspace:
            return "backspace"
        case .space:
            return "space"
        case .returnKey:
            return "return"
        case .modeSwitch:
            return "modeSwitch"
        }
    }
}

private struct SharedKeyboardLogEntry: Codable {
    let id: String
    let timestamp: Date
    let source: String
    let category: String
    let level: String
    let message: String
    let method: String
    let url: String
    let requestHeaders: [String: String]
    let requestBody: String
    let statusCode: Int?
    let responseHeaders: [String: String]
    let responseBody: String
    let error: String?
    let durationMS: Int
    let metadata: [String: String]
}

private final class SharedKeyboardLogStore {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.local.fitnex.keyboard", category: "keyboard")
    private let retention: TimeInterval = 3 * 24 * 60 * 60
    private let appGroupID = "group.com.local.fitnex"
    private var fileLoggingEnabled = false

    private static let chunkFileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH"
        return formatter
    }()

    var sharedContainerAvailable: Bool {
        directoryURL != nil
    }

    func setFileLoggingEnabled(_ enabled: Bool) {
        fileLoggingEnabled = enabled && sharedContainerAvailable
    }

    func writeStartupProbe(event: String, metadata: [String: String]) {
        guard let directoryURL else {
            writeOSLog(
                message: "startup probe skipped",
                level: "warning",
                metadata: ["reason": "appGroupUnavailable", "event": event],
                error: nil
            )
            return
        }

        let payload: [String: String] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "event": event
        ].merging(metadata) { _, new in new }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: directoryURL.appendingPathComponent("keyboard-startup.json"), options: [.atomic])
        } catch {
            writeOSLog(
                message: "startup probe failed",
                level: "error",
                metadata: ["event": event],
                error: error.localizedDescription
            )
        }
    }

    func record(
        _ message: String,
        metadata: [String: String] = [:],
        level: String = "info",
        error: String? = nil,
        durationMS: Int = 0,
        fileLoggingEnabled explicitFileLoggingEnabled: Bool? = nil
    ) {
        let resolvedLevel = error == nil ? level : "error"
        writeOSLog(message: message, level: resolvedLevel, metadata: metadata, error: error)

        let shouldWriteFile = explicitFileLoggingEnabled ?? fileLoggingEnabled
        guard shouldWriteFile else { return }
        guard let directoryURL else {
            logger.error("keyboard app group container unavailable")
            return
        }

        cleanupOldLogs(in: directoryURL)
        let timestamp = Date()
        let entry = SharedKeyboardLogEntry(
            id: UUID().uuidString,
            timestamp: timestamp,
            source: "keyboard",
            category: "keyboard",
            level: resolvedLevel,
            message: message,
            method: "",
            url: "",
            requestHeaders: [:],
            requestBody: "",
            statusCode: nil,
            responseHeaders: [:],
            responseBody: "",
            error: error,
            durationMS: durationMS,
            metadata: metadata
        )

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            let fileURL = directoryURL.appendingPathComponent("\(Self.chunkFileFormatter.string(from: timestamp)).jsonl")
            let data = try JSONEncoder().encode(entry)
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(Data([0x0A]))
            handle.closeFile()
        } catch {
            logger.error("keyboard file log write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var directoryURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("logs", isDirectory: true)
    }

    private func cleanupOldLogs(in directoryURL: URL) {
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { return }
        let cutoff = Date().addingTimeInterval(-retention)
        for url in urls where url.pathExtension == "jsonl" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let date = Self.chunkFileFormatter.date(from: name), date < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func writeOSLog(message: String, level: String, metadata: [String: String], error: String?) {
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let text = [message, metadataText, error].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " | ")

        switch level {
        case "debug":
            logger.debug("\(text, privacy: .public)")
        case "warning":
            logger.info("warning: \(text, privacy: .public)")
        case "error":
            logger.error("\(text, privacy: .public)")
        default:
            logger.info("\(text, privacy: .public)")
        }
    }
}

private struct PinyinCandidateProvider {
    func candidates(for pinyin: String) -> [String] {
        let key = pinyin.lowercased()
        guard !key.isEmpty else { return [] }

        if let exact = Self.dictionary[key] {
            return Array(exact.prefix(8))
        }

        var results: [String] = []
        var seen = Set<String>()

        func append(_ words: [String]) {
            for word in words where !seen.contains(word) {
                seen.insert(word)
                results.append(word)
            }
        }

        let prefixMatches = Self.dictionary
            .filter { $0.key.hasPrefix(key) }
            .sorted {
                if $0.key.count != $1.key.count {
                    return $0.key.count < $1.key.count
                }
                return $0.key < $1.key
            }

        for match in prefixMatches {
            append(match.value)
            if results.count >= 8 { break }
        }

        return Array(results.prefix(8))
    }

    private static let dictionary: [String: [String]] = [
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
