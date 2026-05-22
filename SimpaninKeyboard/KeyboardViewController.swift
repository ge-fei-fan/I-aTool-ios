import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    fileprivate enum KeyboardMode {
        case letters
        case numbers
        case symbols
    }

    private enum ShiftState {
        case off
        case on
    }

    private struct SelectedCompositionSegment {
        let pinyin: String
        let text: String
    }

    private let candidateProvider = PinyinCandidateProvider()
    private let keyboardBackdropView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let rootStack = UIStackView()
    private let trackpadBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let compositionBar = CompositionBarView()
    private let candidateScrollView = UIScrollView()
    private let candidateStack = UIStackView()
    private let utilityOverlayView = UIView()
    private let utilityOverlayButton = UIButton(type: .system)
    private var allCandidates: [String] = []
    private var visibleCandidateCount = 0
    private var highlightedCandidateIndex = 0
    private var keyButtons: [UIButton] = []
    private var selectedCompositionSegments: [SelectedCompositionSegment] = []
    private var compositionBuffer = ""
    private var compositionCursorOffset = 0
    private var keyboardMode: KeyboardMode = .letters
    private var shiftState: ShiftState = .off
    private var isTrackpadActive = false
    private var suppressNextKeyTap = false
    private var trackpadPreviousX: CGFloat = 0
    private var trackpadAccumulatedX: CGFloat = 0
    private var hasInsertedTextInCurrentContext = false
    private let trackpadActivationFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let trackpadMovementFeedback = UISelectionFeedbackGenerator()

    private static let candidateBatchSize = 30
    private static let trackpadStepWidth: CGFloat = 10

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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if !hasActiveComposition && documentContextIsExplicitlyEmpty {
            hasInsertedTextInCurrentContext = false
        }
        updateReturnKeyAppearance()
    }

    private func setupKeyboard() {
        view.backgroundColor = keyboardBackground

        keyboardBackdropView.translatesAutoresizingMaskIntoConstraints = false
        keyboardBackdropView.isUserInteractionEnabled = false
        view.addSubview(keyboardBackdropView)

        rootStack.axis = .vertical
        rootStack.spacing = 7
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        trackpadBlurView.translatesAutoresizingMaskIntoConstraints = false
        trackpadBlurView.alpha = 0
        trackpadBlurView.isUserInteractionEnabled = false
        view.addSubview(trackpadBlurView)

        NSLayoutConstraint.activate([
            keyboardBackdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardBackdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardBackdropView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardBackdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            trackpadBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trackpadBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            trackpadBlurView.topAnchor.constraint(equalTo: view.topAnchor),
            trackpadBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 258)
        ])

        trackpadActivationFeedback.prepare()
        trackpadMovementFeedback.prepare()

        compositionBar.translatesAutoresizingMaskIntoConstraints = false
        compositionBar.onOffsetSelected = { [weak self] offset in
            self?.moveCompositionCursor(toCompositionTextOffset: offset)
        }
        rootStack.addArrangedSubview(compositionBar)
        compositionBar.heightAnchor.constraint(equalToConstant: 18).isActive = true

        candidateScrollView.showsHorizontalScrollIndicator = false
        candidateScrollView.alwaysBounceHorizontal = true
        candidateScrollView.clipsToBounds = false
        candidateScrollView.delegate = self
        rootStack.addArrangedSubview(candidateScrollView)
        candidateScrollView.heightAnchor.constraint(equalToConstant: 30).isActive = true

        candidateStack.axis = .horizontal
        candidateStack.spacing = 6
        candidateStack.alignment = .fill
        candidateStack.distribution = .fill
        candidateStack.isLayoutMarginsRelativeArrangement = true
        candidateStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0)
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScrollView.addSubview(candidateStack)

        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScrollView.frameLayoutGuide.heightAnchor)
        ])

        utilityOverlayView.translatesAutoresizingMaskIntoConstraints = false
        utilityOverlayView.isUserInteractionEnabled = true
        utilityOverlayView.isHidden = true
        utilityOverlayView.backgroundColor = .clear
        view.addSubview(utilityOverlayView)

        utilityOverlayButton.translatesAutoresizingMaskIntoConstraints = false
        utilityOverlayButton.setTitle("⌘", for: .normal)
        utilityOverlayButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        utilityOverlayButton.backgroundColor = candidateBackground
        utilityOverlayButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 14, bottom: 2, right: 14)
        utilityOverlayButton.layer.cornerRadius = 7
        utilityOverlayButton.layer.borderWidth = 0.5
        utilityOverlayView.addSubview(utilityOverlayButton)

        NSLayoutConstraint.activate([
            utilityOverlayView.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            utilityOverlayView.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            utilityOverlayView.topAnchor.constraint(equalTo: compositionBar.topAnchor),
            utilityOverlayView.bottomAnchor.constraint(equalTo: candidateScrollView.bottomAnchor),
            utilityOverlayButton.leadingAnchor.constraint(equalTo: utilityOverlayView.leadingAnchor, constant: 8),
            utilityOverlayButton.centerYAnchor.constraint(equalTo: utilityOverlayView.centerYAnchor),
            utilityOverlayButton.heightAnchor.constraint(equalToConstant: 24),
            utilityOverlayButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        view.bringSubviewToFront(trackpadBlurView)
    }

    private func renderKeyboard() {
        keyButtons.removeAll()
        rootStack.arrangedSubviews.dropFirst(2).forEach { view in
            rootStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let rows: [[KeySpec]]
        switch keyboardMode {
        case .letters:
            rows = letterRows
        case .numbers:
            rows = numberRows
        case .symbols:
            rows = symbolRows
        }

        for row in rows {
            let usesUniformLetterKeys = keyboardMode == .letters && row.contains { $0.kind.isPrimary }
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 6
            rowStack.alignment = .fill
            rowStack.distribution = usesUniformLetterKeys ? .fill : .fillProportionally
            var rowSpacers: [UIView] = []
            var sideKeys: [UIButton] = []

            for key in row {
                if case .spacer = key.kind {
                    let spacer = KeyboardKeySpacer()
                    spacer.widthUnit = key.widthUnit
                    rowStack.addArrangedSubview(spacer)
                    spacer.heightAnchor.constraint(equalToConstant: 40).isActive = true
                    rowSpacers.append(spacer)
                    continue
                }

                let button = makeButton(for: key)
                button.widthUnit = key.widthUnit
                rowStack.addArrangedSubview(button)
                button.heightAnchor.constraint(equalToConstant: 40).isActive = true
                if usesUniformLetterKeys, key.kind.isPrimary {
                    button.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 0.1, constant: -5.4).isActive = true
                }
                if usesUniformLetterKeys, case .shift = key.kind {
                    sideKeys.append(button)
                }
                if usesUniformLetterKeys, case .backspace = key.kind {
                    sideKeys.append(button)
                }
                keyButtons.append(button)
            }

            if rowSpacers.count == 2 {
                rowSpacers[0].widthAnchor.constraint(equalTo: rowSpacers[1].widthAnchor).isActive = true
            }
            if sideKeys.count == 2 {
                sideKeys[0].widthAnchor.constraint(equalTo: sideKeys[1].widthAnchor).isActive = true
            }

            rootStack.addArrangedSubview(rowStack)
        }

        updateCandidates()
        applyTheme()
    }

    private var letterRows: [[KeySpec]] {
        let row1 = "qwertyuiop".map { KeySpec(.character(String($0))) }
        let row2 = [KeySpec(.spacer, widthUnit: 0.5)] + "asdfghjkl".map { KeySpec(.character(String($0))) } + [KeySpec(.spacer, widthUnit: 0.5)]
        let row3 = [KeySpec(.shift, widthUnit: 1.5)] + "zxcvbnm".map { KeySpec(.character(String($0))) } + [KeySpec(.backspace, widthUnit: 1.5)]
        let row4 = [
            KeySpec(.modeSwitch(.numbers), title: "123", widthUnit: 1.35),
            KeySpec(.space, title: "空格", widthUnit: 4.8),
            KeySpec(.returnKey, widthUnit: 1.55)
        ]
        return [row1, row2, row3, row4]
    }

    private var numberRows: [[KeySpec]] {
        [
            "1234567890".map { KeySpec(.character(String($0))) },
            ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { KeySpec(.character($0)) },
            [KeySpec(.modeSwitch(.symbols), title: "#+=", widthUnit: 1.35)] + [".", ",", "?", "!", "'"].map { KeySpec(.character($0)) } + [KeySpec(.backspace, widthUnit: 1.35)],
            [
                KeySpec(.modeSwitch(.letters), title: "ABC", widthUnit: 1.35),
                KeySpec(.space, title: "空格", widthUnit: 4.8),
                KeySpec(.returnKey, widthUnit: 1.55)
            ]
        ]
    }

    private var symbolRows: [[KeySpec]] {
        [
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { KeySpec(.character($0)) },
            ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"].map { KeySpec(.character($0)) },
            [KeySpec(.modeSwitch(.numbers), title: "123", widthUnit: 1.35)] + [".", ",", "?", "!", "'"].map { KeySpec(.character($0)) } + [KeySpec(.backspace, widthUnit: 1.35)],
            [
                KeySpec(.modeSwitch(.letters), title: "ABC", widthUnit: 1.35),
                KeySpec(.space, title: "空格", widthUnit: 4.8),
                KeySpec(.returnKey, widthUnit: 1.55)
            ]
        ]
    }

    private func makeButton(for spec: KeySpec) -> KeyboardKeyButton {
        let button = KeyboardKeyButton(type: .system)
        button.kind = spec.kind
        button.layer.cornerRadius = 6
        button.layer.shadowOpacity = 0.22
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.titleLabel?.font = font(for: spec.kind)
        button.setTitle(title(for: spec), for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.handle(spec.kind)
        }, for: .touchUpInside)
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleKeyLongPress(_:)))
        recognizer.minimumPressDuration = 0.35
        recognizer.cancelsTouchesInView = true
        button.addGestureRecognizer(recognizer)
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
            return returnKeyTitle
        case .spacer:
            return ""
        case .modeSwitch(let target):
            switch target {
            case .letters:
                return "ABC"
            case .numbers:
                return "123"
            case .symbols:
                return "#+="
            }
        }
    }

    private func font(for kind: KeyKind) -> UIFont {
        switch kind {
        case .character:
            return .systemFont(ofSize: 22, weight: .regular)
        case .shift, .backspace:
            return .systemFont(ofSize: 26, weight: .regular)
        default:
            return .systemFont(ofSize: 16, weight: .regular)
        }
    }

    private func handle(_ kind: KeyKind) {
        if suppressNextKeyTap || isTrackpadActive {
            suppressNextKeyTap = false
            return
        }

        switch kind {
        case .character(let value):
            if keyboardMode == .letters, value.rangeOfCharacter(from: .letters) != nil {
                let letter = shiftState == .on ? value.uppercased() : value.lowercased()
                insertCompositionText(letter)
                updateCandidates(resetScroll: true)
            } else {
                commitCompositionAsText()
                textDocumentProxy.insertText(value)
                hasInsertedTextInCurrentContext = true
                updateCandidates(resetScroll: true)
            }
        case .shift:
            shiftState = shiftState == .on ? .off : .on
            renderKeyboard()
        case .backspace:
            if hasActiveComposition {
                deleteCompositionBackward()
            } else {
                textDocumentProxy.deleteBackward()
                if documentContextIsExplicitlyEmpty {
                    hasInsertedTextInCurrentContext = false
                }
            }
            updateCandidates(resetScroll: true)
        case .space:
            if hasActiveComposition {
                if let first = candidates(for: activeCandidatePinyin).first {
                    replaceCompositionWith(first)
                } else {
                    commitCompositionAsText()
                    textDocumentProxy.insertText(" ")
                    hasInsertedTextInCurrentContext = true
                }
            } else {
                textDocumentProxy.insertText(" ")
                hasInsertedTextInCurrentContext = true
            }
        case .returnKey:
            handleReturnKey()
        case .spacer:
            break
        case .modeSwitch(let target):
            commitCompositionAsText()
            keyboardMode = target
            renderKeyboard()
        }
    }

    private func handleReturnKey() {
        guard isReturnKeyEnabled else { return }
        if hasPendingCandidates {
            finalizeComposition()
        } else if isSendInput {
            finalizeComposition()
            textDocumentProxy.insertText("\n")
            hasInsertedTextInCurrentContext = true
        } else if isSearchInput || isMultilineInput {
            finalizeComposition()
            textDocumentProxy.insertText("\n")
            hasInsertedTextInCurrentContext = true
        } else {
            finalizeComposition()
        }
        updateReturnKeyAppearance()
    }

    @objc private func handleKeyLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.view != nil else { return }
        let locationX = recognizer.location(in: view).x

        switch recognizer.state {
        case .began:
            isTrackpadActive = true
            suppressNextKeyTap = true
            trackpadPreviousX = locationX
            trackpadAccumulatedX = 0
            triggerTrackpadActivationFeedback()
            trackpadMovementFeedback.prepare()
            setTrackpadBlurVisible(true)
        case .changed:
            guard isTrackpadActive else { return }
            let delta = locationX - trackpadPreviousX
            trackpadPreviousX = locationX
            trackpadAccumulatedX += delta

            while abs(trackpadAccumulatedX) >= Self.trackpadStepWidth {
                let offset = trackpadAccumulatedX > 0 ? 1 : -1
                textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
                trackpadAccumulatedX -= CGFloat(offset) * Self.trackpadStepWidth
                triggerTrackpadMovementFeedback()
                trackpadMovementFeedback.prepare()
            }
        case .ended, .cancelled, .failed:
            isTrackpadActive = false
            trackpadAccumulatedX = 0
            setTrackpadBlurVisible(false)
            trackpadActivationFeedback.prepare()
            updateCandidates()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.suppressNextKeyTap = false
            }
        default:
            break
        }
    }

    private func setTrackpadBlurVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.trackpadBlurView.alpha = visible ? 1 : 0
        }
    }

    private func triggerTrackpadActivationFeedback() {
        trackpadActivationFeedback.prepare()
        trackpadActivationFeedback.impactOccurred(intensity: 1)
        trackpadMovementFeedback.selectionChanged()
        AudioServicesPlaySystemSound(1519)
    }

    private func triggerTrackpadMovementFeedback() {
        trackpadMovementFeedback.selectionChanged()
    }

    private func replaceCompositionWith(_ text: String) {
        guard hasActiveComposition else {
            textDocumentProxy.insertText(text)
            hasInsertedTextInCurrentContext = true
            resetCompositionState()
            refreshCompositionDisplay()
            updateCandidates(resetScroll: true)
            return
        }

        let pinyin = activeCandidatePinyin
        if selectedCompositionSegments.isEmpty {
            removeActivePinyinPrefix()
        } else {
            compositionBuffer = ""
            compositionCursorOffset = 0
        }
        selectedCompositionSegments.append(SelectedCompositionSegment(pinyin: pinyin, text: text))

        if compositionBuffer.isEmpty {
            textDocumentProxy.insertText(selectedCompositionText)
            hasInsertedTextInCurrentContext = true
            resetCompositionState()
            refreshCompositionDisplay()
        } else {
            compositionCursorOffset = compositionBuffer.count
            refreshCompositionDisplay()
        }
        updateCandidates(resetScroll: true)
    }

    private func updateCandidates(resetScroll: Bool = false) {
        guard keyboardMode == .letters else {
            allCandidates = []
            visibleCandidateCount = 0
            renderVisibleCandidates()
            updateReturnKeyAppearance()
            return
        }
        let pinyin = activeCandidatePinyin
        if pinyin.isEmpty {
            allCandidates = []
        } else {
            allCandidates = self.candidates(for: pinyin)
        }
        visibleCandidateCount = min(Self.candidateBatchSize, allCandidates.count)
        if resetScroll || highlightedCandidateIndex >= visibleCandidateCount {
            highlightedCandidateIndex = 0
        }
        renderVisibleCandidates()
        if resetScroll {
            candidateScrollView.setContentOffset(.zero, animated: false)
        }
        updateReturnKeyAppearance()
    }

    private func renderVisibleCandidates() {
        candidateStack.arrangedSubviews.forEach { view in
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        utilityOverlayView.isHidden = hasActiveComposition || !allCandidates.isEmpty

        guard !allCandidates.isEmpty else {
            return
        }

        for (index, candidate) in allCandidates.prefix(visibleCandidateCount).enumerated() {
            let isHighlighted = index == highlightedCandidateIndex
            let button = UIButton(type: .system)
            button.setTitle(candidate, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: isHighlighted ? .semibold : .regular)
            button.setTitleColor(isHighlighted ? highlightedCandidateText : primaryText, for: .normal)
            button.backgroundColor = isHighlighted ? highlightedCandidateBackground : .clear
            button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 12, bottom: 2, right: 12)
            button.layer.cornerRadius = 7
            button.layer.borderWidth = 0.5
            button.layer.borderColor = (isHighlighted ? UIColor.clear : candidateBorder).cgColor
            button.layer.shadowColor = isHighlighted ? candidateShadow.cgColor : UIColor.clear.cgColor
            button.layer.shadowOpacity = isHighlighted ? (isDark ? 0.35 : 0.18) : 0
            button.layer.shadowRadius = 1
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.addAction(UIAction { [weak self] _ in
                self?.highlightedCandidateIndex = index
                self?.replaceCompositionWith(candidate)
            }, for: .touchUpInside)
            candidateStack.addArrangedSubview(button)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
    }

    private func appendMoreCandidatesIfNeeded() {
        guard visibleCandidateCount < allCandidates.count else { return }
        visibleCandidateCount = min(visibleCandidateCount + Self.candidateBatchSize, allCandidates.count)
        renderVisibleCandidates()
    }

    private func applyTheme() {
        view.backgroundColor = keyboardBackground
        keyboardBackdropView.effect = UIBlurEffect(style: .systemThinMaterial)

        for button in keyButtons {
            if let keyButton = button as? KeyboardKeyButton, case .returnKey = keyButton.kind {
                keyButton.setTitle(returnKeyTitle, for: .normal)
                keyButton.isEnabled = isReturnKeyEnabled
                keyButton.alpha = isReturnKeyEnabled ? 1 : 0.45
            } else {
                button.alpha = 1
            }
            let title = button.title(for: .normal) ?? ""
            let isSpecial = ["123", "ABC", "#+=", "⌫", "⇧", "搜索", "确认", "发送", "换行"].contains(title)
            button.backgroundColor = isSpecial ? specialKeyBackground : keyBackground
            button.setTitleColor(primaryText, for: .normal)
            button.layer.shadowColor = shadowColor.cgColor
        }
        utilityOverlayButton.setTitleColor(secondaryText, for: .normal)
        utilityOverlayButton.backgroundColor = candidateBackground
        utilityOverlayButton.layer.borderColor = candidateBorder.cgColor
        updateCompositionBarAppearance()
    }

    private func updateReturnKeyAppearance() {
        for button in keyButtons.compactMap({ $0 as? KeyboardKeyButton }) {
            guard case .returnKey = button.kind else { continue }
            button.setTitle(returnKeyTitle, for: .normal)
            button.isEnabled = isReturnKeyEnabled
            button.alpha = isReturnKeyEnabled ? 1 : 0.45
        }
    }

    private func updateCompositionBarAppearance() {
        compositionBar.configure(textColor: primaryText, cursorColor: compositionCursorColor)
    }

    private var keyboardBackground: UIColor {
        isDark ? UIColor(red: 0.13, green: 0.14, blue: 0.14, alpha: 0.72) : UIColor(red: 0.73, green: 0.75, blue: 0.78, alpha: 0.72)
    }

    private var keyBackground: UIColor {
        isDark ? UIColor(red: 0.39, green: 0.39, blue: 0.41, alpha: 1) : .white
    }

    private var specialKeyBackground: UIColor {
        isDark ? UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1)
    }

    private var candidateBackground: UIColor {
        isDark ? UIColor(red: 0.31, green: 0.31, blue: 0.33, alpha: 1) : UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    }

    private var highlightedCandidateBackground: UIColor {
        .white
    }

    private var highlightedCandidateText: UIColor {
        .black
    }

    private var candidateBorder: UIColor {
        isDark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.06)
    }

    private var candidateShadow: UIColor {
        isDark ? .black : UIColor(white: 0.35, alpha: 1)
    }

    private var compositionCursorColor: UIColor {
        isDark ? UIColor(red: 0.62, green: 0.78, blue: 1, alpha: 1) : UIColor(red: 0.05, green: 0.36, blue: 0.86, alpha: 1)
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

    private var hasActiveComposition: Bool {
        !selectedCompositionSegments.isEmpty || !compositionBuffer.isEmpty
    }

    private var returnKeyTitle: String {
        if hasPendingCandidates {
            return "确认"
        }
        if isSendInput {
            return "发送"
        }
        if isSearchInput {
            return "搜索"
        }
        if isMultilineInput {
            return "换行"
        }
        return "确认"
    }

    private var isReturnKeyEnabled: Bool {
        if hasPendingCandidates {
            return true
        }
        if isSearchInput {
            return hasDocumentText
        }
        if isSendInput {
            return hasDocumentText
        }
        return true
    }

    private var hasPendingCandidates: Bool {
        hasActiveComposition && !allCandidates.isEmpty
    }

    private var isSearchInput: Bool {
        textDocumentProxy.returnKeyType == .search || textDocumentProxy.keyboardType == .webSearch
    }

    private var isSendInput: Bool {
        textDocumentProxy.returnKeyType == .send
    }

    private var isMultilineInput: Bool {
        textDocumentProxy.returnKeyType == .default && !isSearchInput
    }

    private var hasDocumentText: Bool {
        if hasActiveComposition {
            return true
        }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        return !before.isEmpty || !after.isEmpty || hasInsertedTextInCurrentContext
    }

    private var documentContextIsExplicitlyEmpty: Bool {
        guard let before = textDocumentProxy.documentContextBeforeInput,
              let after = textDocumentProxy.documentContextAfterInput else {
            return false
        }
        return before.isEmpty && after.isEmpty
    }

    private var selectedCompositionText: String {
        selectedCompositionSegments.map(\.text).joined()
    }

    private var selectedCompositionPinyin: String {
        selectedCompositionSegments.map(\.pinyin).joined()
    }

    private var compositionText: String {
        selectedCompositionText + compositionBuffer
    }

    private var activeCandidatePinyin: String {
        guard !compositionBuffer.isEmpty else { return "" }
        if !selectedCompositionSegments.isEmpty {
            return compositionBuffer
        }
        if compositionCursorOffset > 0 && compositionCursorOffset < compositionBuffer.count {
            let end = compositionBuffer.index(compositionBuffer.startIndex, offsetBy: compositionCursorOffset)
            return String(compositionBuffer[..<end])
        }
        return compositionBuffer
    }

    private func insertCompositionText(_ text: String) {
        let insertIndex = compositionBuffer.index(compositionBuffer.startIndex, offsetBy: compositionCursorOffset)
        compositionBuffer.insert(contentsOf: text, at: insertIndex)
        compositionCursorOffset += text.count
        refreshCompositionDisplay()
    }

    private func deleteCompositionBackward() {
        if !selectedCompositionSegments.isEmpty {
            rollbackLastSelectedSegment()
            return
        }
        guard compositionCursorOffset > 0 else { return }
        let removeIndex = compositionBuffer.index(compositionBuffer.startIndex, offsetBy: compositionCursorOffset - 1)
        compositionBuffer.remove(at: removeIndex)
        compositionCursorOffset -= 1
        if compositionBuffer.isEmpty {
            clearCompositionAfterDeletion()
        } else {
            refreshCompositionDisplay()
        }
    }

    private func clearCompositionAfterDeletion() {
        resetCompositionState()
        refreshCompositionDisplay()
    }

    private func moveCompositionCursor(toCompositionTextOffset textOffset: Int) {
        guard hasActiveComposition else { return }
        let rawCompositionOffset = textOffset - selectedCompositionPinyin.count
        compositionCursorOffset = max(0, min(compositionBuffer.count, rawCompositionOffset))
        refreshCompositionDisplay()
        updateCandidates(resetScroll: true)
    }

    private func refreshCompositionDisplay() {
        let display = pinyinDisplay()
        compositionBar.update(text: display.text, cursorOffset: display.cursorOffset, rawOffsets: display.rawOffsets)
    }

    private func pinyinDisplay() -> (text: String, cursorOffset: Int, rawOffsets: [Int]) {
        let prefix = segmentedPinyin(selectedCompositionPinyin)
        let current = segmentedPinyin(compositionBuffer)
        let text = [prefix, current].filter { !$0.isEmpty }.joined(separator: prefix.isEmpty || current.isEmpty ? "" : "'")
        let rawCursor = selectedCompositionPinyin.count + compositionCursorOffset
        return (text, displayOffset(forRawOffset: rawCursor, in: text), rawOffsets(forDisplayText: text))
    }

    private func segmentedPinyin(_ pinyin: String) -> String {
        guard !pinyin.isEmpty else { return "" }
        let segments = PinyinSegmenter.segment(pinyin)
        guard segments.count > 1, segments.joined() == pinyin else { return pinyin }
        return segments.joined(separator: "'")
    }

    private func rawOffsets(forDisplayText text: String) -> [Int] {
        var offsets: [Int] = []
        var rawOffset = 0
        offsets.append(rawOffset)
        for character in text {
            if character != "'" {
                rawOffset += 1
            }
            offsets.append(rawOffset)
        }
        return offsets
    }

    private func displayOffset(forRawOffset rawOffset: Int, in displayText: String) -> Int {
        let offsets = rawOffsets(forDisplayText: displayText)
        return offsets.lastIndex(of: rawOffset) ?? min(rawOffset, displayText.count)
    }

    private func commitCompositionAsText() {
        finalizeComposition()
    }

    private func finalizeComposition() {
        let text = compositionText
        guard !text.isEmpty else {
            resetCompositionState()
            refreshCompositionDisplay()
            updateCandidates(resetScroll: true)
            return
        }
        textDocumentProxy.insertText(text)
        hasInsertedTextInCurrentContext = true
        resetCompositionState()
        refreshCompositionDisplay()
        updateCandidates(resetScroll: true)
    }

    private func removeActivePinyinPrefix() {
        let prefixLength = activeCandidatePinyin.count
        guard prefixLength > 0 else { return }
        let end = compositionBuffer.index(compositionBuffer.startIndex, offsetBy: prefixLength)
        compositionBuffer.removeSubrange(compositionBuffer.startIndex..<end)
        compositionCursorOffset = compositionBuffer.count
    }

    private func rollbackLastSelectedSegment() {
        guard let segment = selectedCompositionSegments.popLast() else { return }
        compositionBuffer = segment.pinyin + compositionBuffer
        compositionCursorOffset = compositionBuffer.count
        refreshCompositionDisplay()
    }

    private func resetCompositionState() {
        selectedCompositionSegments = []
        compositionBuffer = ""
        compositionCursorOffset = 0
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
    var kind: KeyKind = .character("")
    var widthUnit: CGFloat = 1

    override var intrinsicContentSize: CGSize {
        CGSize(width: 32 * widthUnit, height: 40)
    }
}

private final class KeyboardKeySpacer: UIView {
    var widthUnit: CGFloat = 1

    override var intrinsicContentSize: CGSize {
        CGSize(width: 32 * widthUnit, height: 40)
    }
}

private final class CompositionBarView: UIView {
    var onOffsetSelected: ((Int) -> Void)?

    private var text = ""
    private var cursorOffset = 0
    private var rawOffsets: [Int] = [0]
    private let font = UIFont.systemFont(ofSize: 15, weight: .regular)
    private let textInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    private var barTextColor = UIColor.black
    private var barCursorColor = UIColor.systemBlue

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(textColor: UIColor, cursorColor: UIColor) {
        barTextColor = textColor
        barCursorColor = cursorColor
        setNeedsDisplay()
    }

    func update(text: String, cursorOffset: Int, rawOffsets: [Int]? = nil) {
        self.text = text
        self.cursorOffset = max(0, min(text.count, cursorOffset))
        self.rawOffsets = rawOffsets ?? Array(0...text.count)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard !text.isEmpty else { return }

        let textRect = bounds.inset(by: textInsets)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: barTextColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textOrigin = CGPoint(x: textRect.minX, y: bounds.midY - textSize.height / 2)
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)

        let cursorX = max(textRect.minX, min(textRect.minX + width(upTo: cursorOffset), textRect.maxX))
        let cursorTop = max(textRect.minY + 1, bounds.midY - 6)
        let cursorBottom = min(textRect.maxY - 1, bounds.midY + 6)
        let cursorPath = UIBezierPath()
        cursorPath.move(to: CGPoint(x: cursorX, y: cursorTop))
        cursorPath.addLine(to: CGPoint(x: cursorX, y: cursorBottom))
        barCursorColor.setStroke()
        cursorPath.lineWidth = 1.3
        cursorPath.stroke()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard !text.isEmpty else { return }
        let point = recognizer.location(in: self)
        let textRect = bounds.inset(by: textInsets)
        let x = max(0, min(point.x - textRect.minX, textRect.width))
        let displayOffset = nearestOffset(for: x)
        let safeOffset = max(0, min(displayOffset, rawOffsets.count - 1))
        onOffsetSelected?(rawOffsets[safeOffset])
    }

    private func nearestOffset(for x: CGFloat) -> Int {
        guard !text.isEmpty else { return 0 }
        var bestOffset = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for offset in 0...text.count {
            let distance = abs(width(upTo: offset) - x)
            if distance < bestDistance {
                bestDistance = distance
                bestOffset = offset
            }
        }
        return bestOffset
    }

    private func width(upTo offset: Int) -> CGFloat {
        guard offset > 0 else { return 0 }
        let safeOffset = max(0, min(text.count, offset))
        let end = text.index(text.startIndex, offsetBy: safeOffset)
        let prefix = String(text[..<end]) as NSString
        return ceil(prefix.size(withAttributes: [.font: font]).width)
    }
}

extension KeyboardViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === candidateScrollView else { return }
        let remaining = scrollView.contentSize.width - scrollView.bounds.width - scrollView.contentOffset.x
        if remaining < 120 {
            appendMoreCandidatesIfNeeded()
        }
    }
}

private enum KeyKind {
    case character(String)
    case shift
    case backspace
    case space
    case returnKey
    case spacer
    case modeSwitch(KeyboardViewController.KeyboardMode)

    var isPrimary: Bool {
        if case .character = self {
            return true
        }
        return false
    }
}

private struct PinyinCandidate {
    let text: String
    let weight: Int
}

private struct PinyinSegmenter {
    private static let syllables: Set<String> = [
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
        "za", "zai", "zan", "zang", "zao", "ze", "zei", "zen", "zeng", "zha", "zhai", "zhan", "zhang", "zhao", "zhe", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu", "zhua", "zhuai", "zhuan", "zhuang", "zhui", "zhun", "zhuo", "zi", "zong", "zou", "zu", "zuan", "zui", "zun", "zuo"
    ]

    static func segment(_ key: String) -> [String] {
        var index = key.startIndex
        var result: [String] = []

        while index < key.endIndex {
            var best: String?
            var end = key.index(index, offsetBy: min(6, key.distance(from: index, to: key.endIndex)), limitedBy: key.endIndex) ?? key.endIndex
            while end > index {
                let piece = String(key[index..<end])
                if syllables.contains(piece) {
                    best = piece
                    break
                }
                end = key.index(before: end)
            }

            guard let best else { return [] }
            result.append(best)
            index = key.index(index, offsetBy: best.count)
        }

        return result
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

        var candidates: [PinyinCandidate] = []

        candidates += weightedCandidates(for: key, baseWeight: 1_000_000)

        let segments = PinyinSegmenter.segment(key)
        if segments.count == 2 {
            candidates += longestPrefixCandidates(for: key, baseWeight: 850_000)
            candidates += phraseCandidates(from: segments, baseWeight: 750_000)
        } else if segments.count > 2 {
            candidates += phraseCandidates(from: segments, baseWeight: 850_000)
            candidates += longestPrefixCandidates(for: key, baseWeight: 750_000)
        } else {
            candidates += longestPrefixCandidates(for: key, baseWeight: 600_000)
        }
        candidates += fallbackCandidates(for: key, baseWeight: 100_000)

        return merge(candidates).map(\.text)
    }

    private func weightedCandidates(for key: String, baseWeight: Int) -> [PinyinCandidate] {
        guard let lineCandidates = bundledCandidates(for: key) else { return [] }
        return lineCandidates.map { candidate in
            PinyinCandidate(text: candidate.text, weight: candidate.weight + baseWeight)
        }
    }

    private func longestPrefixCandidates(for key: String, baseWeight: Int) -> [PinyinCandidate] {
        var lookupKey = key
        while !lookupKey.isEmpty {
            lookupKey.removeLast()
            guard !lookupKey.isEmpty else { break }
            let candidates = weightedCandidates(for: lookupKey, baseWeight: baseWeight)
            if !candidates.isEmpty {
                return candidates
            }
        }
        return []
    }

    private func phraseCandidates(from segments: [String], baseWeight: Int) -> [PinyinCandidate] {
        let groups = segments.map { segment in
            weightedCandidates(for: segment, baseWeight: 0).prefix(8).map { $0 }
        }
        guard groups.allSatisfy({ !$0.isEmpty }) else { return [] }

        var results: [PinyinCandidate] = []

        func build(index: Int, text: String, weight: Int) {
            if results.count >= 80 { return }
            if index == groups.count {
                results.append(PinyinCandidate(text: text, weight: baseWeight + weight / max(1, groups.count)))
                return
            }

            for candidate in groups[index] {
                build(index: index + 1, text: text + candidate.text, weight: weight + candidate.weight)
            }
        }

        build(index: 0, text: "", weight: 0)
        return results
    }

    private func fallbackCandidates(for key: String, baseWeight: Int) -> [PinyinCandidate] {
        var candidates: [PinyinCandidate] = []

        if let exact = Self.fallbackDictionary[key] {
            candidates += exact.enumerated().map { index, text in
                PinyinCandidate(text: text, weight: baseWeight + 10_000 - index)
            }
        }

        let prefixCandidates = Self.fallbackDictionary
            .filter { $0.key.hasPrefix(key) }
            .sorted { $0.key.count == $1.key.count ? $0.key < $1.key : $0.key.count < $1.key.count }
            .flatMap(\.value)

        candidates += prefixCandidates.enumerated().map { index, text in
            PinyinCandidate(text: text, weight: baseWeight - index)
        }

        return candidates
    }

    private func merge(_ candidates: [PinyinCandidate]) -> [PinyinCandidate] {
        var bestByText: [String: Int] = [:]
        for candidate in candidates where !candidate.text.isEmpty {
            bestByText[candidate.text] = max(bestByText[candidate.text] ?? Int.min, candidate.weight)
        }
        return bestByText
            .map { PinyinCandidate(text: $0.key, weight: $0.value) }
            .sorted {
                if $0.weight != $1.weight {
                    return $0.weight > $1.weight
                }
                if $0.text.count != $1.text.count {
                    return $0.text.count < $1.text.count
                }
                return $0.text < $1.text
            }
    }

    private func bundledCandidates(for key: String) -> [PinyinCandidate]? {
        guard let lexiconURL, let indexURL, recordCount > 0 else { return nil }
        guard let record = findRecord(for: key, in: indexURL) else { return nil }
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
                .enumerated()
                .map { index, field in
                    Self.parseCandidateField(String(field), fallbackWeight: 120 - index)
                }
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

    private static func parseCandidateField(_ field: String, fallbackWeight: Int) -> PinyinCandidate {
        guard let separator = field.lastIndex(of: ":") else {
            return PinyinCandidate(text: field, weight: fallbackWeight)
        }

        let text = String(field[..<separator])
        let weightText = String(field[field.index(after: separator)...])
        return PinyinCandidate(text: text, weight: Int(weightText) ?? fallbackWeight)
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
