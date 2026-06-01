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
    @State private var isCandidatePageVisible = false

    private let candidateBatchSize = 30

    var body: some View {
        VStack(spacing: 7) {
            candidateInputArea
            ZStack(alignment: .top) {
                keyRows
                    .opacity(isCandidatePageVisible ? 0 : 1)
                    .offset(y: isCandidatePageVisible ? 120 : 0)
                    .allowsHitTesting(!isCandidatePageVisible)

                if isCandidatePageVisible {
                    candidateExpandedPage
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.22), value: isCandidatePageVisible)
        .onChange(of: engine.candidates) { candidates in
            if candidates.isEmpty {
                isCandidatePageVisible = false
            }
        }
    }

    private var candidateInputArea: some View {
        VStack(spacing: 7) {
            compositionBar
            migratedCandidateStrip
        }
    }

    private var compositionBar: some View {
        HStack(spacing: 8) {
            Text(engine.displayText.isEmpty ? "中文拼音" : engine.displayText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(engine.hasComposition ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(.secondarySystemBackground).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var migratedCandidateStrip: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(engine.candidates.prefix(candidateBatchSize).enumerated()), id: \.element.id) { index, candidate in
                        candidateButton(candidate, index: index, expanded: false)
                    }

                    if engine.candidates.isEmpty {
                        Color.clear.frame(width: 1, height: 30)
                    }
                }
                .frame(minWidth: 0, alignment: .leading)
                .padding(.bottom, 1)
            }
            .scrollDisabled(engine.candidates.count <= 3)

            candidateExpandButton
        }
        .frame(height: 32)
    }

    private var candidateExpandButton: some View {
        Button {
            guard !engine.candidates.isEmpty else { return }
            isCandidatePageVisible = true
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(engine.candidates.isEmpty ? 0 : 1)
        .allowsHitTesting(!engine.candidates.isEmpty)
    }

    private var candidateExpandedPage: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    isCandidatePageVisible = false
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 32)
            .padding(.trailing, 1)

            ScrollView(.vertical, showsIndicators: false) {
                CandidateFlowLayout(spacing: 6) {
                    ForEach(Array(engine.candidates.enumerated()), id: \.element.id) { index, candidate in
                        candidateButton(candidate, index: index, expanded: true)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 204, alignment: .top)
        .background(Color(.secondarySystemBackground))
        .clipped()
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
                "_\\|~<>€£¥".map { .character(String($0)) },
                [.modeSwitch("123", .numbers)] + ".,?!'".map { .character(String($0)) } + [.backspace],
                [.modeSwitch("ABC", .letters), .nextKeyboard, .space, .returnKey]
            ]
        }
    }

    private func candidateButton(
        _ candidate: PinyinInputEngine.Candidate,
        index: Int,
        expanded: Bool
    ) -> some View {
        Button {
            selectCandidate(candidate)
        } label: {
            Text(candidate.text)
                .font(.system(size: 19, weight: index == 0 ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, expanded ? 6 : 2)
                .frame(minWidth: expanded ? 56 : 48, minHeight: expanded ? 34 : 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                isCandidatePageVisible = false
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
            if engine.candidates.isEmpty {
                isCandidatePageVisible = false
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
            isCandidatePageVisible = false
        }
    }

    private func selectCandidate(_ candidate: PinyinInputEngine.Candidate) {
        if let committedText = engine.select(candidate) {
            insertText(committedText)
        }
        if engine.candidates.isEmpty {
            isCandidatePageVisible = false
        }
    }

    private func commitCompositionIfNeeded() {
        if let text = engine.commitCompositionAsText() {
            insertText(text)
        }
        isCandidatePageVisible = false
    }
}

private struct CandidateFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = max(56, proposal.width ?? 320)
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(max(size.width, 56), maxWidth)
            let height = max(size.height, 34)
            let candidateSpacing = rowWidth == 0 ? 0 : spacing

            if rowWidth > 0 && rowWidth + candidateSpacing + width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }

            rowWidth += (rowWidth == 0 ? 0 : spacing) + width
            rowHeight = max(rowHeight, height)
        }

        if rowHeight > 0 {
            totalHeight += rowHeight
        }
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = max(56, bounds.width)
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(max(size.width, 56), maxWidth)
            let height = max(size.height, 34)
            let candidateSpacing = x == bounds.minX ? 0 : spacing

            if x > bounds.minX && x + candidateSpacing + width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            } else if x > bounds.minX {
                x += spacing
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: width, height: height)
            )
            x += width
            rowHeight = max(rowHeight, height)
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
            return isShifted ? "⇪" : "⇧"
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
