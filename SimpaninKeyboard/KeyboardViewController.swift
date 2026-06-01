import KeyboardKit
import SwiftUI
import UIKit

final class KeyboardViewController: KeyboardInputViewController {
    private let pinyinState = PinyinKeyboardInputState()

    override func viewDidLoad() {
        super.viewDidLoad()
        setKeyboardCase(.lowercased)
        let standardActionHandler = services.actionHandler
        services.actionHandler = PinyinKeyboardActionHandler(
            controller: self,
            standardActionHandler: standardActionHandler,
            pinyinState: pinyinState
        )
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [pinyinState] controller in
            PinyinKeyboardView(
                services: controller.services,
                pinyinState: pinyinState,
                insertText: { [weak controller] text in
                    controller?.textDocumentProxy.insertText(text)
                }
            )
        }
    }
}

private final class PinyinKeyboardInputState: ObservableObject {
    @Published private(set) var engine = PinyinInputEngine()
    @Published var isCandidatePageVisible = false

    var hasComposition: Bool {
        engine.hasComposition
    }

    var candidates: [PinyinInputEngine.Candidate] {
        engine.candidates
    }

    var displayText: String {
        engine.displayText
    }

    func insertLetter(_ letter: String) {
        engine.insertLetter(letter.lowercased())
        isCandidatePageVisible = false
    }

    func deleteBackward() -> Bool {
        let didDelete = engine.deleteBackward()
        if engine.candidates.isEmpty {
            isCandidatePageVisible = false
        }
        return didDelete
    }

    func select(_ candidate: PinyinInputEngine.Candidate) -> String? {
        let committedText = engine.select(candidate)
        if engine.candidates.isEmpty {
            isCandidatePageVisible = false
        }
        return committedText
    }

    func commitCompositionAsText() -> String? {
        let text = engine.commitCompositionAsText()
        isCandidatePageVisible = false
        return text
    }
}

private final class PinyinKeyboardActionHandler: KeyboardActionHandler {
    private weak var controller: (any KeyboardController)?
    private let standardActionHandler: any KeyboardActionHandler
    private let pinyinState: PinyinKeyboardInputState

    init(
        controller: any KeyboardController,
        standardActionHandler: any KeyboardActionHandler,
        pinyinState: PinyinKeyboardInputState
    ) {
        self.controller = controller
        self.standardActionHandler = standardActionHandler
        self.pinyinState = pinyinState
    }

    func canHandle(_ gesture: Keyboard.Gesture, on action: KeyboardAction) -> Bool {
        standardActionHandler.canHandle(gesture, on: action)
    }

    func handle(_ action: KeyboardAction) {
        standardActionHandler.handle(action)
    }

    func handle(_ gesture: Keyboard.Gesture, on action: KeyboardAction) {
        guard gesture == .release else {
            standardActionHandler.handle(gesture, on: action)
            return
        }

        switch action {
        case .character(let value):
            guard isPinyinLetter(value) else {
                standardActionHandler.handle(gesture, on: action)
                return
            }
            pinyinState.insertLetter(value)
        case .backspace:
            guard pinyinState.hasComposition else {
                standardActionHandler.handle(gesture, on: action)
                return
            }
            if !pinyinState.deleteBackward() {
                standardActionHandler.handle(gesture, on: action)
            }
        case .space:
            guard let first = pinyinState.candidates.first else {
                standardActionHandler.handle(gesture, on: action)
                return
            }
            if let text = pinyinState.select(first) {
                controller?.insertText(text)
            }
        case .primary:
            if pinyinState.hasComposition,
               let text = pinyinState.commitCompositionAsText() {
                controller?.insertText(text)
            }
            standardActionHandler.handle(gesture, on: action)
        default:
            if pinyinState.hasComposition,
               let text = pinyinState.commitCompositionAsText() {
                controller?.insertText(text)
            }
            standardActionHandler.handle(gesture, on: action)
        }
    }

    func handle(_ suggestion: Autocomplete.Suggestion) {
        standardActionHandler.handle(suggestion)
    }

    func handleDrag(
        on action: KeyboardAction,
        from startLocation: CGPoint,
        to currentLocation: CGPoint
    ) {
        standardActionHandler.handleDrag(on: action, from: startLocation, to: currentLocation)
    }

    func triggerFeedback(for gesture: Keyboard.Gesture, on action: KeyboardAction) {
        // Disable KeyboardKit's combined feedback path to avoid key haptics.
    }

    func triggerAudioFeedback(_ feedback: Feedback.Audio) {
        standardActionHandler.triggerAudioFeedback(feedback)
    }

    func triggerHapticFeedback(_ feedback: Feedback.Haptic) {
        // Key vibration is intentionally disabled for this keyboard.
    }

    private func isPinyinLetter(_ value: String) -> Bool {
        value.count == 1 && value.rangeOfCharacter(from: .letters) != nil
    }
}

private struct PinyinKeyboardView: View {
    let services: Keyboard.Services
    @ObservedObject var pinyinState: PinyinKeyboardInputState
    let insertText: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            KeyboardView(
                services: services,
                buttonContent: { params in
                    if case .shift(let keyboardCase) = params.item.action {
                        PinyinShiftButtonContent(keyboardCase: keyboardCase)
                    } else {
                        params.view
                    }
                },
                buttonView: { $0.view },
                collapsedView: { $0.view },
                emojiKeyboard: { $0.view },
                toolbar: { _ in
                    PinyinCandidateToolbar(
                        pinyinState: pinyinState,
                        insertText: insertText
                    )
                }
            )

            if pinyinState.isCandidatePageVisible {
                PinyinExpandedCandidateOverlay(
                    pinyinState: pinyinState,
                    insertText: insertText
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: pinyinState.isCandidatePageVisible)
    }
}

private struct PinyinShiftButtonContent: View {
    let keyboardCase: Keyboard.KeyboardCase

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }

    private var imageName: String {
        switch keyboardCase {
        case .uppercased:
            return "ios-icon/大写图标"
        case .lowercased:
            return "ios-icon/小写图标"
        }
    }
}

private struct PinyinCandidateToolbar: View {
    @ObservedObject var pinyinState: PinyinKeyboardInputState
    let insertText: (String) -> Void

    private let candidateBatchSize = 30

    var body: some View {
        candidateInputArea
            .opacity(pinyinState.isCandidatePageVisible ? 0 : 1)
            .allowsHitTesting(!pinyinState.isCandidatePageVisible)
        .frame(maxWidth: .infinity)
    }

    private var candidateInputArea: some View {
        VStack(spacing: 7) {
            compositionBar
            migratedCandidateStrip
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var compositionBar: some View {
        HStack(spacing: 8) {
            Text(pinyinState.displayText.isEmpty ? "中文拼音" : pinyinState.displayText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(pinyinState.hasComposition ? .primary : .secondary)
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
                    ForEach(Array(pinyinState.candidates.prefix(candidateBatchSize).enumerated()), id: \.element.id) { index, candidate in
                        candidateButton(candidate, index: index, expanded: false)
                    }

                    if pinyinState.candidates.isEmpty {
                        Color.clear.frame(width: 1, height: 30)
                    }
                }
                .frame(minWidth: 0, alignment: .leading)
                .padding(.bottom, 1)
            }
            .scrollDisabled(pinyinState.candidates.count <= 3)

            candidateExpandButton
        }
        .frame(height: 32)
    }

    private var candidateExpandButton: some View {
        Button {
            guard !pinyinState.candidates.isEmpty else { return }
            pinyinState.isCandidatePageVisible = true
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(pinyinState.candidates.isEmpty ? 0 : 1)
        .allowsHitTesting(!pinyinState.candidates.isEmpty)
    }

    private func candidateButton(
        _ candidate: PinyinInputEngine.Candidate,
        index: Int,
        expanded: Bool
    ) -> some View {
        PinyinCandidateButton(
            candidate: candidate,
            index: index,
            expanded: expanded,
            pinyinState: pinyinState,
            insertText: insertText
        )
    }
}

private struct PinyinExpandedCandidateOverlay: View {
    @ObservedObject var pinyinState: PinyinKeyboardInputState
    let insertText: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    pinyinState.isCandidatePageVisible = false
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
                    ForEach(Array(pinyinState.candidates.enumerated()), id: \.element.id) { index, candidate in
                        PinyinCandidateButton(
                            candidate: candidate,
                            index: index,
                            expanded: true,
                            pinyinState: pinyinState,
                            insertText: insertText
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemBackground))
        .clipped()
    }
}

private struct PinyinCandidateButton: View {
    let candidate: PinyinInputEngine.Candidate
    let index: Int
    let expanded: Bool
    @ObservedObject var pinyinState: PinyinKeyboardInputState
    let insertText: (String) -> Void

    var body: some View {
        Button {
            if let committedText = pinyinState.select(candidate) {
                insertText(committedText)
            }
            pinyinState.isCandidatePageVisible = false
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
