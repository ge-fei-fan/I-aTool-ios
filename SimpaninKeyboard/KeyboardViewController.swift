import KeyboardKit
import SwiftUI
import UIKit

final class KeyboardViewController: KeyboardInputViewController {
    private var hostingController: UIHostingController<ChinesePinyinKeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        installKeyboardView()
    }

    private func installKeyboardView() {
        let keyboardView = ChinesePinyinKeyboardView(
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            deleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            submitReturn: { [weak self] in
                self?.textDocumentProxy.insertText("\n")
            },
            advanceToNextInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )

        let hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 258)
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }
}

private enum PinyinKeyboardMode {
    case letters
    case numbers
    case symbols
}

private struct ChinesePinyinKeyboardView: View {
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let submitReturn: () -> Void
    let advanceToNextInputMode: () -> Void

    @State private var engine = PinyinInputEngine()
    @State private var mode: PinyinKeyboardMode = .letters
    @State private var isShifted = false

    var body: some View {
        VStack(spacing: 7) {
            compositionBar
            candidateBar
            keyRows
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private var compositionBar: some View {
        HStack {
            Text(engine.displayText.isEmpty ? "中文拼音" : engine.displayText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(engine.displayText.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(.secondarySystemBackground).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var candidateBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(engine.candidates) { candidate in
                    Button {
                        selectCandidate(candidate)
                    } label: {
                        Text(candidate.text)
                            .font(.system(size: 16, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color(.systemBackground).opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if engine.candidates.isEmpty {
                    Text(" ")
                        .frame(height: 30)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 32)
    }

    private var keyRows: some View {
        VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex]) { key in
                        keyButton(key)
                    }
                }
                .frame(height: 42)
            }
        }
    }

    private var rows: [[PinyinKeyboardKey]] {
        switch mode {
        case .letters:
            return [
                "qwertyuiop".map { .character(String($0)) },
                "asdfghjkl".map { .character(String($0)) },
                [.shift] + "zxcvbnm".map { .character(String($0)) } + [.backspace],
                [.modeSwitch("123", .numbers), .nextKeyboard, .space, .returnKey]
            ]
        case .numbers:
            return [
                "1234567890".map { .character(String($0)) },
                "-/:;()$&@\"".map { .character(String($0)) },
                [.modeSwitch("#+=", .symbols)] + ".,?!'".map { .character(String($0)) } + [.backspace],
                [.modeSwitch("ABC", .letters), .nextKeyboard, .space, .returnKey]
            ]
        case .symbols:
            return [
                "[]{}#%^*+=".map { .character(String($0)) },
                "_\\|~<>€£¥·".map { .character(String($0)) },
                [.modeSwitch("123", .numbers)] + ".,?!'".map { .character(String($0)) } + [.backspace],
                [.modeSwitch("ABC", .letters), .nextKeyboard, .space, .returnKey]
            ]
        }
    }

    private func keyButton(_ key: PinyinKeyboardKey) -> some View {
        Button {
            handle(key)
        } label: {
            Text(key.title(isShifted: isShifted))
                .font(.system(size: key.fontSize, weight: key.isPrimary ? .regular : .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: key.width == nil ? .infinity : key.width, minHeight: 42, maxHeight: 42)
                .background(key.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func handle(_ key: PinyinKeyboardKey) {
        switch key {
        case .character(let value):
            if mode == .letters, value.rangeOfCharacter(from: .letters) != nil {
                engine.insertLetter(isShifted ? value.uppercased() : value.lowercased())
            } else {
                commitCompositionIfNeeded()
                insertText(value)
            }
        case .shift:
            isShifted.toggle()
        case .backspace:
            if !engine.deleteBackward() {
                deleteBackward()
            }
        case .space:
            if let first = engine.candidates.first {
                selectCandidate(first)
            } else {
                commitCompositionIfNeeded()
                insertText(" ")
            }
        case .returnKey:
            commitCompositionIfNeeded()
            submitReturn()
        case .nextKeyboard:
            commitCompositionIfNeeded()
            advanceToNextInputMode()
        case .modeSwitch(_, let target):
            commitCompositionIfNeeded()
            mode = target
            isShifted = false
        }
    }

    private func selectCandidate(_ candidate: PinyinInputEngine.Candidate) {
        if let committedText = engine.select(candidate) {
            insertText(committedText)
        }
    }

    private func commitCompositionIfNeeded() {
        if let text = engine.commitCompositionAsText() {
            insertText(text)
        }
    }
}

private enum PinyinKeyboardKey: Identifiable, Equatable {
    case character(String)
    case shift
    case backspace
    case space
    case returnKey
    case nextKeyboard
    case modeSwitch(String, PinyinKeyboardMode)

    var id: String {
        switch self {
        case .character(let value): return "char-\(value)"
        case .shift: return "shift"
        case .backspace: return "backspace"
        case .space: return "space"
        case .returnKey: return "return"
        case .nextKeyboard: return "next"
        case .modeSwitch(let title, _): return "mode-\(title)"
        }
    }

    var isPrimary: Bool {
        if case .character = self { return true }
        return false
    }

    var width: CGFloat? {
        switch self {
        case .space:
            return 150
        case .shift, .backspace, .returnKey, .nextKeyboard, .modeSwitch:
            return 48
        case .character:
            return nil
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .character:
            return 22
        case .space:
            return 15
        default:
            return 14
        }
    }

    var backgroundColor: Color {
        isPrimary ? Color(.systemBackground) : Color(.secondarySystemBackground)
    }

    func title(isShifted: Bool) -> String {
        switch self {
        case .character(let value):
            return isShifted ? value.uppercased() : value
        case .shift:
            return isShifted ? "⇧" : "⇧"
        case .backspace:
            return "⌫"
        case .space:
            return "空格"
        case .returnKey:
            return "确认"
        case .nextKeyboard:
            return "🌐"
        case .modeSwitch(let title, _):
            return title
        }
    }
}
