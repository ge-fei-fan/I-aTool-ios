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
        setKeyboardCase(.lowercased)
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

private enum PinyinKeyboardMetrics {
    static let candidateToolbarHeight: CGFloat = 75
    static let compositionBarHeight: CGFloat = 30
    static let candidateInputTopPadding: CGFloat = 4
    static let compositionCandidateSpacing: CGFloat = 7
    static let expandedCandidateOverlayTopOffset: CGFloat = candidateInputTopPadding + compositionBarHeight + compositionCandidateSpacing
    static let candidateExpandHitWidth: CGFloat = 48
    static let candidateExpandHitHeight: CGFloat = 44
    static let expandedCandidateMinHitHeight: CGFloat = 44
    static let expandedCandidateVerticalPadding: CGFloat = 10
    static let candidatePanelAnimationDuration: TimeInterval = 0.22
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
        engine.insertLetter(letter)
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
    private weak var controller: KeyboardInputViewController?
    private let standardActionHandler: any KeyboardActionHandler
    private let pinyinState: PinyinKeyboardInputState
    private var isManualUppercaseEnabled = false

    init(
        controller: KeyboardInputViewController,
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
        switch action {
        case .shift(let keyboardCase):
            handleShift(keyboardCase)
        case .character(let value) where isPinyinLetter(value):
            pinyinState.insertLetter(value)
        case .backspace where pinyinState.hasComposition:
            if pinyinState.deleteBackward() {
                applyLowercaseIfCompositionCleared()
            } else {
                standardActionHandler.handle(action)
                applyLowercaseState()
            }
        case .backspace:
            handlePlainBackspaceLowercasing()
        case .primary:
            if pinyinState.hasComposition,
               let text = pinyinState.commitCompositionAsText() {
                controller?.insertText(text)
            }
            standardActionHandler.handle(action)
            applyLowercaseState()
        default:
            standardActionHandler.handle(action)
            applyDefaultLowercaseIfNeeded()
        }
    }

    func handle(_ gesture: Keyboard.Gesture, on action: KeyboardAction) {
        guard gesture == .release else {
            if shouldConsumePreReleaseGesture(on: action) {
                return
            }
            standardActionHandler.handle(gesture, on: action)
            return
        }

        switch action {
        case .shift(let keyboardCase):
            handleShift(keyboardCase)
        case .character(let value):
            guard isPinyinLetter(value) else {
                handleStandardAction(gesture, on: action)
                return
            }
            pinyinState.insertLetter(value)
        case .backspace:
            guard pinyinState.hasComposition else {
                handlePlainBackspaceLowercasing()
                return
            }
            if pinyinState.deleteBackward() {
                applyLowercaseIfCompositionCleared()
            } else {
                handleStandardAction(gesture, on: action)
            }
        case .space:
            guard let first = pinyinState.candidates.first else {
                handleStandardAction(gesture, on: action)
                return
            }
            if let text = pinyinState.select(first) {
                controller?.insertText(text)
            }
            applyDefaultLowercaseIfNeeded()
        case .primary:
            if pinyinState.hasComposition,
               let text = pinyinState.commitCompositionAsText() {
                controller?.insertText(text)
            }
            handleStandardAction(gesture, on: action)
            applyLowercaseState()
        default:
            if pinyinState.hasComposition,
               let text = pinyinState.commitCompositionAsText() {
                controller?.insertText(text)
            }
            handleStandardAction(gesture, on: action)
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

    private func shouldConsumePreReleaseGesture(on action: KeyboardAction) -> Bool {
        switch action {
        case .character(let value):
            return isPinyinLetter(value)
        case .backspace:
            return true
        default:
            return false
        }
    }

    private func handleShift(_ keyboardCase: Keyboard.KeyboardCase) {
        switch keyboardCase {
        case .lowercased:
            isManualUppercaseEnabled = true
            controller?.setKeyboardCase(.uppercased)
        case .uppercased, .capsLocked:
            isManualUppercaseEnabled = false
            controller?.setKeyboardCase(.lowercased)
        }
    }

    private func handleStandardAction(_ gesture: Keyboard.Gesture, on action: KeyboardAction) {
        standardActionHandler.handle(gesture, on: action)
        applyDefaultLowercaseIfNeeded()
    }

    private func handlePlainBackspaceLowercasing() {
        if canDeleteBackwardInDocument {
            controller?.textDocumentProxy.deleteBackward()
        }
        applyLowercaseState()
    }

    private var canDeleteBackwardInDocument: Bool {
        controller?.textDocumentProxy.documentContextBeforeInput?.isEmpty == false
    }

    private func applyDefaultLowercaseIfNeeded() {
        if !isManualUppercaseEnabled {
            controller?.setKeyboardCase(.lowercased)
        }
    }

    private func applyLowercaseIfCompositionCleared() {
        if !pinyinState.hasComposition {
            applyLowercaseState()
        }
    }

    private func applyLowercaseState() {
        isManualUppercaseEnabled = false
        controller?.setKeyboardCase(.lowercased)
    }
}

private struct PinyinKeyboardView: View {
    let services: Keyboard.Services
    @ObservedObject var pinyinState: PinyinKeyboardInputState
    let insertText: (String) -> Void

    var body: some View {
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
        .overlay(alignment: .top) {
            expandedCandidateOverlay
        }
        .animation(.easeOut(duration: PinyinKeyboardMetrics.candidatePanelAnimationDuration), value: pinyinState.isCandidatePageVisible)
        .clipped()
    }

    @ViewBuilder
    private var expandedCandidateOverlay: some View {
        if pinyinState.isCandidatePageVisible {
            PinyinExpandedCandidateOverlay(
                pinyinState: pinyinState,
                insertText: insertText
            )
            .padding(.top, PinyinKeyboardMetrics.expandedCandidateOverlayTopOffset)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct PinyinShiftButtonContent: View {
    let keyboardCase: Keyboard.KeyboardCase

    var body: some View {
        icon
        .resizable()
        .scaledToFit()
        .frame(width: 24, height: 24)
    }

    private var icon: Image {
        if let image = bundleImage {
            return Image(uiImage: image)
        }
        return Image(systemName: fallbackSystemName)
    }

    private var bundleImage: UIImage? {
        guard let url = Bundle(for: KeyboardViewController.self).url(
            forResource: imageName,
            withExtension: "png",
            subdirectory: "ios-icon"
        ) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    private var imageName: String {
        switch keyboardCase {
        case .uppercased:
            return "大写图标"
        case .capsLocked:
            return "大写图标"
        case .lowercased:
            return "小写图标"
        }
    }

    private var fallbackSystemName: String {
        switch keyboardCase {
        case .uppercased, .capsLocked:
            return "shift.fill"
        case .lowercased:
            return "shift"
        }
    }
}

private struct PinyinCandidateToolbar: View {
    @ObservedObject var pinyinState: PinyinKeyboardInputState
    let insertText: (String) -> Void

    private let candidateBatchSize = 30

    var body: some View {
        ZStack {
            if pinyinState.isCandidatePageVisible {
                expandedCompositionArea
            } else {
                candidateInputArea
            }
        }
            .frame(maxWidth: .infinity)
            .frame(height: PinyinKeyboardMetrics.candidateToolbarHeight)
            .allowsHitTesting(!pinyinState.isCandidatePageVisible)
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

    private var expandedCompositionArea: some View {
        VStack(spacing: 0) {
            compositionBar
                .padding(.horizontal, 4)
                .padding(.top, PinyinKeyboardMetrics.candidateInputTopPadding)
            Spacer(minLength: 0)
        }
    }

    private var compositionBar: some View {
        HStack(spacing: 8) {
            Text(pinyinState.displayText.isEmpty ? "" : pinyinState.displayText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(pinyinState.hasComposition ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: PinyinKeyboardMetrics.compositionBarHeight)
        .background(Color(.secondarySystemBackground).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var migratedCandidateStrip: some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pinyinState.candidates.prefix(candidateBatchSize).enumerated()), id: \.element.id) { index, candidate in
                            candidateButton(candidate, index: index, expanded: false)
                        }

                        if pinyinState.candidates.isEmpty {
                            Color.clear.frame(width: 1, height: 30)
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                    .background(Color.primary.opacity(0.001))
                    .contentShape(Rectangle())
                    .padding(.bottom, 1)
                }
                .contentShape(Rectangle())
                .background(Color.primary.opacity(0.001))
                .scrollDisabled(pinyinState.candidates.count <= 3)
            }
            .frame(height: 32)

            candidateExpandButton
        }
        .frame(height: 32)
    }

    private var candidateExpandButton: some View {
        Button {
            guard !pinyinState.candidates.isEmpty else { return }
            withAnimation(.easeOut(duration: PinyinKeyboardMetrics.candidatePanelAnimationDuration)) {
                pinyinState.isCandidatePageVisible.toggle()
            }
        } label: {
            Image(systemName: pinyinState.isCandidatePageVisible ? "chevron.up" : "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 32)
                .frame(width: PinyinKeyboardMetrics.candidateExpandHitWidth, height: PinyinKeyboardMetrics.candidateExpandHitHeight)
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
            collapseHeader

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemBackground))
        .clipped()
    }

    private var collapseHeader: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: PinyinKeyboardMetrics.candidatePanelAnimationDuration)) {
                    pinyinState.isCandidatePageVisible = false
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: PinyinKeyboardMetrics.candidateExpandHitWidth, height: PinyinKeyboardMetrics.candidateExpandHitHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 4)
        .frame(height: PinyinKeyboardMetrics.candidateExpandHitHeight)
        .background(Color(.secondarySystemBackground))
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
                .padding(.vertical, expanded ? PinyinKeyboardMetrics.expandedCandidateVerticalPadding : 2)
                .frame(minWidth: expanded ? 56 : 48, minHeight: expanded ? PinyinKeyboardMetrics.expandedCandidateMinHitHeight : 30)
                .background(expanded ? Color.primary.opacity(0.001) : Color.clear)
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
