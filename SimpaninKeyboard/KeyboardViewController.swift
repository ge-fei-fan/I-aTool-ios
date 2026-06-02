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
        applyLockedKeyboardCase()
        setupKeyboardView { [pinyinState] controller in
            PinyinKeyboardView(
                keyboardContext: controller.state.keyboardContext,
                services: controller.services,
                pinyinState: pinyinState,
                insertText: { [weak controller] text in
                    controller?.textDocumentProxy.insertText(text)
                }
            )
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyLockedKeyboardCase()
    }

    private func applyLockedKeyboardCase() {
        setKeyboardCase(pinyinState.isUppercaseLocked ? .uppercased : .lowercased)
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
    static let candidateToggleHitAreaDebugOpacity: Double = 0.35
    static let expandedCandidateMinHitHeight: CGFloat = 44
    static let expandedCandidateVerticalPadding: CGFloat = 10
    static let candidatePanelAnimationDuration: TimeInterval = 0.22
}

private final class PinyinKeyboardInputState: ObservableObject {
    private static let candidateRefreshDelay: TimeInterval = 0.012

    private var engine = PinyinInputEngine()
    private let candidateQueue = DispatchQueue(label: "com.local.simpanin.keyboard.candidates", qos: .userInitiated)
    private var candidateRefreshWorkItem: DispatchWorkItem?
    private var candidateRefreshGeneration = 0
    private var appliedCandidateGeneration = 0

    @Published private(set) var displayText = ""
    @Published private(set) var hasComposition = false
    @Published private(set) var candidates: [PinyinInputEngine.Candidate] = []
    @Published private(set) var isCandidateRefreshPending = false
    @Published var isChineseInputEnabled = true
    @Published var isCandidatePageVisible = false
    @Published var isUppercaseLocked = false

    deinit {
        candidateRefreshWorkItem?.cancel()
    }

    func insertLetter(_ letter: String) {
        engine.insertLetter(letter)
        hideCandidatePageIfNeeded()
        refreshPublishedComposition()
        scheduleCandidateRefresh(resetCandidatesWhenEmpty: false)
    }

    func deleteBackward() -> Bool {
        let didDelete = engine.deleteBackward()
        refreshPublishedComposition()
        scheduleCandidateRefresh(resetCandidatesWhenEmpty: !engine.hasComposition)
        return didDelete
    }

    func select(_ candidate: PinyinInputEngine.Candidate) -> String? {
        guard !isCandidateRefreshPending else { return nil }
        let committedText = engine.select(candidate)
        refreshPublishedComposition()
        if committedText != nil {
            hideCandidatePageIfNeeded()
        }
        scheduleCandidateRefresh(resetCandidatesWhenEmpty: false)
        return committedText
    }

    func commitCompositionAsText() -> String? {
        let text = engine.commitCompositionAsText()
        hideCandidatePageIfNeeded()
        refreshPublishedComposition()
        scheduleCandidateRefresh(resetCandidatesWhenEmpty: false)
        return text
    }

    func toggleChineseInput() {
        isChineseInputEnabled.toggle()
        hideCandidatePageIfNeeded()
        refreshPublishedComposition()
        scheduleCandidateRefresh(resetCandidatesWhenEmpty: true)
    }

    func firstFreshCandidateForCommit() -> PinyinInputEngine.Candidate? {
        guard isChineseInputEnabled else { return nil }
        if isCandidateRefreshPending || appliedCandidateGeneration != candidateRefreshGeneration {
            candidateRefreshWorkItem?.cancel()
            candidateRefreshWorkItem = nil
            candidateRefreshGeneration += 1
            let generation = candidateRefreshGeneration
            applyCandidateRefreshResult(engine.candidates, generation: generation)
        }
        return candidates.first
    }

    private func scheduleCandidateRefresh(resetCandidatesWhenEmpty: Bool) {
        candidateRefreshGeneration += 1
        candidateRefreshWorkItem?.cancel()
        let generation = candidateRefreshGeneration

        guard isChineseInputEnabled else {
            applyCandidateRefreshResult([], generation: generation)
            return
        }

        if resetCandidatesWhenEmpty, !engine.hasComposition {
            applyCandidateRefreshResult([], generation: generation)
            return
        }

        let engineSnapshot = engine
        setCandidateRefreshPending(true)

        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem {
            guard !workItem.isCancelled else { return }
            let refreshedCandidates = engineSnapshot.candidates
            guard !workItem.isCancelled else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.candidateRefreshGeneration == generation,
                      !workItem.isCancelled else {
                    return
                }
                self.applyCandidateRefreshResult(refreshedCandidates, generation: generation)
            }
        }
        candidateRefreshWorkItem = workItem
        candidateQueue.asyncAfter(deadline: .now() + Self.candidateRefreshDelay, execute: workItem)
    }

    private func applyCandidateRefreshResult(
        _ refreshedCandidates: [PinyinInputEngine.Candidate],
        generation: Int
    ) {
        guard generation == candidateRefreshGeneration else { return }
        candidateRefreshWorkItem = nil
        setCandidateRefreshPending(false)
        appliedCandidateGeneration = generation
        if candidates != refreshedCandidates {
            candidates = refreshedCandidates
        }
        if refreshedCandidates.isEmpty {
            hideCandidatePageIfNeeded()
        }
    }

    private func refreshPublishedComposition() {
        let nextDisplayText = engine.displayText
        if displayText != nextDisplayText {
            displayText = nextDisplayText
        }

        let nextHasComposition = engine.hasComposition
        if hasComposition != nextHasComposition {
            hasComposition = nextHasComposition
        }
    }

    private func setCandidateRefreshPending(_ isPending: Bool) {
        if isCandidateRefreshPending != isPending {
            isCandidateRefreshPending = isPending
        }
    }

    private func hideCandidatePageIfNeeded() {
        if isCandidatePageVisible {
            isCandidatePageVisible = false
        }
    }
}

private final class PinyinKeyboardActionHandler: KeyboardActionHandler {
    private static let languageSwitchActionName = "simpanin.inputMode.toggleChineseEnglish"

    private weak var controller: KeyboardInputViewController?
    private let standardActionHandler: any KeyboardActionHandler
    private let pinyinState: PinyinKeyboardInputState

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
        if shouldHandlePinyinAction(action) {
            return true
        }
        return standardActionHandler.canHandle(gesture, on: action)
    }

    func handle(_ action: KeyboardAction) {
        switch action {
        case .custom(named: Self.languageSwitchActionName):
            handleLanguageSwitch()
        case .shift(let keyboardCase):
            handleShift(keyboardCase)
        case .character(let value) where shouldRouteLetterToPinyin(value):
            pinyinState.insertLetter(value)
            applyLockedKeyboardCase()
        case .backspace where pinyinState.hasComposition:
            if pinyinState.deleteBackward() {
                applyLockedKeyboardCase()
            } else {
                standardActionHandler.handle(action)
                applyLockedKeyboardCase()
            }
        case .backspace:
            handlePlainBackspace()
        case .primary:
            if pinyinState.hasComposition,
               let text = pinyinState.commitCompositionAsText() {
                controller?.insertText(text)
            }
            standardActionHandler.handle(action)
            applyLockedKeyboardCaseDeferred()
        default:
            standardActionHandler.handle(action)
            applyLockedKeyboardCase()
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
        case .custom(named: Self.languageSwitchActionName):
            handleLanguageSwitch()
        case .shift(let keyboardCase):
            handleShift(keyboardCase)
        case .character(let value):
            guard shouldRouteLetterToPinyin(value) else {
                handleStandardAction(gesture, on: action)
                return
            }
            pinyinState.insertLetter(value)
            applyLockedKeyboardCase()
        case .backspace:
            guard pinyinState.hasComposition else {
                handlePlainBackspace()
                return
            }
            if pinyinState.deleteBackward() {
                applyLockedKeyboardCase()
            } else {
                handleStandardAction(gesture, on: action)
            }
        case .space:
            guard let first = pinyinState.firstFreshCandidateForCommit() else {
                handleStandardAction(gesture, on: action)
                return
            }
            if let text = pinyinState.select(first) {
                controller?.insertText(text)
            }
            applyLockedKeyboardCase()
        case .primary:
            if pinyinState.hasComposition,
               let text = pinyinState.commitCompositionAsText() {
                controller?.insertText(text)
            }
            handleStandardAction(gesture, on: action)
            applyLockedKeyboardCaseDeferred()
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

    private func shouldRouteLetterToPinyin(_ value: String) -> Bool {
        pinyinState.isChineseInputEnabled && isPinyinLetter(value)
    }

    private func shouldHandlePinyinAction(_ action: KeyboardAction) -> Bool {
        switch action {
        case .custom(named: Self.languageSwitchActionName):
            return true
        case .character(let value):
            return shouldRouteLetterToPinyin(value)
        case .backspace, .shift, .space, .primary:
            return true
        default:
            return false
        }
    }

    private func shouldConsumePreReleaseGesture(on action: KeyboardAction) -> Bool {
        switch action {
        case .character(let value):
            return shouldRouteLetterToPinyin(value)
        case .backspace:
            return true
        default:
            return false
        }
    }

    private func handleShift(_ keyboardCase: Keyboard.KeyboardCase) {
        pinyinState.isUppercaseLocked.toggle()
        applyLockedKeyboardCase()
    }

    private func handleLanguageSwitch() {
        if pinyinState.hasComposition,
           let text = pinyinState.commitCompositionAsText() {
            controller?.insertText(text)
        }
        pinyinState.toggleChineseInput()
        applyLockedKeyboardCase()
    }

    private func handleStandardAction(_ gesture: Keyboard.Gesture, on action: KeyboardAction) {
        standardActionHandler.handle(gesture, on: action)
        applyLockedKeyboardCase()
    }

    private func handlePlainBackspace() {
        if canDeleteBackwardInDocument {
            controller?.textDocumentProxy.deleteBackward()
        }
        applyLockedKeyboardCase()
    }

    private var canDeleteBackwardInDocument: Bool {
        controller?.textDocumentProxy.documentContextBeforeInput?.isEmpty == false
    }

    private func applyLockedKeyboardCase() {
        controller?.setKeyboardCase(pinyinState.isUppercaseLocked ? .uppercased : .lowercased)
    }

    private func applyLockedKeyboardCaseDeferred() {
        applyLockedKeyboardCase()
        DispatchQueue.main.async { [weak self] in
            self?.applyLockedKeyboardCase()
        }
    }
}

private struct PinyinKeyboardView: View {
    private static let languageSwitchActionName = "simpanin.inputMode.toggleChineseEnglish"

    @ObservedObject var keyboardContext: KeyboardContext
    let services: Keyboard.Services
    @ObservedObject var pinyinState: PinyinKeyboardInputState
    let insertText: (String) -> Void

    var body: some View {
        KeyboardView(
            layout: keyboardLayout,
            services: services,
            buttonContent: { params in
                if case .shift(let keyboardCase) = params.item.action {
                    PinyinShiftButtonContent(keyboardCase: keyboardCase)
                } else if case .custom(named: Self.languageSwitchActionName) = params.item.action {
                    PinyinLanguageSwitchButtonContent(isChineseInputEnabled: pinyinState.isChineseInputEnabled)
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
        .overlay(alignment: .topLeading) {
            edgeBlankTapOverlay
        }
        .animation(.easeOut(duration: PinyinKeyboardMetrics.candidatePanelAnimationDuration), value: pinyinState.isCandidatePageVisible)
        .clipped()
    }

    @ViewBuilder
    private var edgeBlankTapOverlay: some View {
        if pinyinState.isChineseInputEnabled && !pinyinState.isCandidatePageVisible {
            PinyinKeyboardEdgeBlankTapOverlay(isUppercaseLocked: pinyinState.isUppercaseLocked) { letter in
                pinyinState.insertLetter(letter)
            }
        }
    }

    private var keyboardLayout: KeyboardLayout {
        var layout = KeyboardLayout.standard(for: keyboardContext)
        let utilityKeySide = utilityKeySide(in: layout)
        layout.itemRows = layout.itemRows.map { row in
            row.map { item in
                resizedUtilityItem(item, side: utilityKeySide)
            }
        }
        layout.itemRows.insert(languageSwitchItem(side: utilityKeySide), after: .space)
        return layout
    }

    private func utilityKeySide(in layout: KeyboardLayout) -> CGFloat {
        for row in layout.itemRows {
            for item in row {
                if isPrimaryAction(item.action) {
                    return item.size.height
                }
            }
        }
        return CGFloat(layout.idealItemHeight)
    }

    private func resizedUtilityItem(
        _ item: KeyboardLayout.Item,
        side: CGFloat
    ) -> KeyboardLayout.Item {
        guard isNumericKeyboardTypeAction(item.action) else { return item }
        return item.withWidth(.points(side))
    }

    private func isPrimaryAction(_ action: KeyboardAction) -> Bool {
        if case .primary = action {
            return true
        }
        return false
    }

    private func isNumericKeyboardTypeAction(_ action: KeyboardAction) -> Bool {
        if case .keyboardType(.numeric) = action {
            return true
        }
        return false
    }

    private func languageSwitchItem(side: CGFloat) -> KeyboardLayout.Item {
        let adjustedSide = max(0, side - 2)
        KeyboardLayout.Item(
            action: .custom(named: Self.languageSwitchActionName),
            size: .init(width: .points(adjustedSide), height: adjustedSide)
        )
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

private struct PinyinKeyboardEdgeBlankTapOverlay: View {
    let isUppercaseLocked: Bool
    let insertLetter: (String) -> Void

    private let rowCount: CGFloat = 4
    private let secondLetterRowIndex: CGFloat = 1
    private let sideHitWidthRatio: CGFloat = 0.085
    private let sideHitWidthRange: ClosedRange<CGFloat> = 24...42

    var body: some View {
        GeometryReader { proxy in
            let keyboardTop = PinyinKeyboardMetrics.candidateToolbarHeight
            let keyboardHeight = max(0, proxy.size.height - keyboardTop)
            let rowHeight = keyboardHeight / rowCount
            let hitWidth = min(
                sideHitWidthRange.upperBound,
                max(sideHitWidthRange.lowerBound, proxy.size.width * sideHitWidthRatio)
            )
            let rowTop = keyboardTop + rowHeight * secondLetterRowIndex

            ZStack(alignment: .topLeading) {
                edgeHitArea(letter: isUppercaseLocked ? "A" : "a")
                    .frame(width: hitWidth, height: rowHeight)
                    .offset(x: 0, y: rowTop)

                edgeHitArea(letter: isUppercaseLocked ? "L" : "l")
                    .frame(width: hitWidth, height: rowHeight)
                    .offset(x: proxy.size.width - hitWidth, y: rowTop)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func edgeHitArea(letter: String) -> some View {
        Color.primary.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture {
                insertLetter(letter)
            }
    }
}

private extension KeyboardLayout.Item {
    func withWidth(_ width: KeyboardLayout.ItemWidth) -> KeyboardLayout.Item {
        KeyboardLayout.Item(
            action: action,
            secondaryAction: secondaryAction,
            size: .init(width: width, height: size.height),
            alignment: alignment,
            edgeInsets: edgeInsets
        )
    }
}

private struct PinyinLanguageSwitchButtonContent: View {
    let isChineseInputEnabled: Bool

    var body: some View {
        Text(isChineseInputEnabled ? "中" : "英")
            .font(.system(size: 16, weight: .semibold))
            .minimumScaleFactor(0.8)
            .lineLimit(1)
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
            guard !pinyinState.candidates.isEmpty,
                  !pinyinState.isCandidateRefreshPending else { return }
            withAnimation(.easeOut(duration: PinyinKeyboardMetrics.candidatePanelAnimationDuration)) {
                pinyinState.isCandidatePageVisible.toggle()
            }
        } label: {
            Image(systemName: pinyinState.isCandidatePageVisible ? "chevron.up" : "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 32)
                .frame(width: PinyinKeyboardMetrics.candidateExpandHitWidth, height: PinyinKeyboardMetrics.candidateExpandHitHeight)
                .background(Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(pinyinState.candidates.isEmpty ? 0 : 1)
        .allowsHitTesting(!pinyinState.candidates.isEmpty && !pinyinState.isCandidateRefreshPending)
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
                    .background(Color.clear)
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
            guard !pinyinState.isCandidateRefreshPending else { return }
            if let committedText = pinyinState.select(candidate) {
                insertText(committedText)
            }
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
        .allowsHitTesting(!pinyinState.isCandidateRefreshPending)
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
