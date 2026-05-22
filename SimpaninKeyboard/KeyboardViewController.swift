import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    fileprivate enum KeyboardMode {
        case letters
        case numbers
        case symbols
    }

    private enum InputLanguage {
        case chinese
        case english
    }

    private enum ShiftState {
        case off
        case on
    }

    private enum CandidateMode {
        case composition
        case association
    }

    private struct SelectedCompositionSegment {
        let pinyin: String
        let text: String
        let recordsSelection: Bool
    }

    private struct KeyboardCandidate {
        let text: String
        let consumeLength: Int
        let recordsSelection: Bool

        init(text: String, consumeLength: Int, recordsSelection: Bool = true) {
            self.text = text
            self.consumeLength = consumeLength
            self.recordsSelection = recordsSelection
        }
    }

    private let candidateProvider = PinyinCandidateProvider()
    private let associationProvider = PinyinAssociationProvider()
    private let keyboardBackdropView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let rootStack = UIStackView()
    private let trackpadBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let keyPreviewView = KeyPreviewView()
    private let compositionBar = CompositionBarView()
    private let candidateBarStack = UIStackView()
    private let candidateScrollView = UIScrollView()
    private let candidateStack = UIStackView()
    private let candidateExpandButton = UIButton(type: .system)
    private let candidatePageView = UIView()
    private let candidatePageScrollView = UIScrollView()
    private let candidatePageStack = UIStackView()
    private let candidatePageCollapseButton = UIButton(type: .system)
    private let keyboardRowsStack = UIStackView()
    private let utilityOverlayView = UIView()
    private let utilityOverlayButton = UIButton(type: .system)
    private var allCandidates: [KeyboardCandidate] = []
    private var visibleCandidateCount = 0
    private var highlightedCandidateIndex = 0
    private var candidateMode: CandidateMode = .composition
    private var associationContext: String?
    private var keyButtons: [UIButton] = []
    private var selectedCompositionSegments: [SelectedCompositionSegment] = []
    private var compositionBuffer = ""
    private var compositionCursorOffset = 0
    private var keyboardMode: KeyboardMode = .letters
    private var inputLanguage: InputLanguage = .chinese
    private var shiftState: ShiftState = .off
    private weak var previewedKeyButton: KeyboardKeyButton?
    private var isCandidatePageVisible = false
    private var candidatePageRenderedWidth: CGFloat = 0
    private var isTrackpadActive = false
    private var suppressNextKeyTap = false
    private var trackpadPreviousX: CGFloat = 0
    private var trackpadAccumulatedX: CGFloat = 0
    private var hasInsertedTextInCurrentContext = false
    private let trackpadActivationFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let trackpadMovementFeedback = UISelectionFeedbackGenerator()

    private static let candidateBatchSize = 30
    private static let utilityFillText = "kk223344"
    private static let trackpadStepWidth: CGFloat = 10
    private static let keyPreviewHorizontalInset: CGFloat = 4
    private static let previewableLetterScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

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
        updateKeyboardBackdropAppearance()
        updateReturnKeyAppearance()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard isCandidatePageVisible else { return }
        let width = candidatePageView.bounds.width
        if abs(width - candidatePageRenderedWidth) > 1 {
            renderCandidatePage()
        }
    }

    private func setupKeyboard() {
        updateKeyboardBackdropAppearance()

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

        keyPreviewView.isHidden = true
        keyPreviewView.alpha = 0
        view.addSubview(keyPreviewView)

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

        candidateBarStack.axis = .horizontal
        candidateBarStack.spacing = 6
        candidateBarStack.alignment = .fill
        candidateBarStack.distribution = .fill
        rootStack.addArrangedSubview(candidateBarStack)
        candidateBarStack.heightAnchor.constraint(equalToConstant: 30).isActive = true

        candidateScrollView.showsHorizontalScrollIndicator = false
        candidateScrollView.alwaysBounceHorizontal = true
        candidateScrollView.clipsToBounds = false
        candidateScrollView.delegate = self
        candidateBarStack.addArrangedSubview(candidateScrollView)

        candidateExpandButton.translatesAutoresizingMaskIntoConstraints = false
        candidateExpandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        candidateExpandButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        candidateExpandButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        candidateExpandButton.layer.cornerRadius = 7
        candidateExpandButton.layer.borderWidth = 0.5
        candidateExpandButton.isHidden = true
        candidateExpandButton.addAction(UIAction { [weak self] _ in
            self?.setCandidatePageVisible(true)
        }, for: .touchUpInside)
        candidateBarStack.addArrangedSubview(candidateExpandButton)
        candidateExpandButton.widthAnchor.constraint(equalToConstant: 34).isActive = true

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

        keyboardRowsStack.axis = .vertical
        keyboardRowsStack.spacing = 10
        keyboardRowsStack.alignment = .fill
        keyboardRowsStack.distribution = .fill
        rootStack.addArrangedSubview(keyboardRowsStack)

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
        utilityOverlayButton.addAction(UIAction { [weak self] _ in
            self?.handleUtilityFillButtonTap()
        }, for: .touchUpInside)
        utilityOverlayView.addSubview(utilityOverlayButton)

        setupCandidatePage()

        NSLayoutConstraint.activate([
            utilityOverlayView.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            utilityOverlayView.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            utilityOverlayView.topAnchor.constraint(equalTo: compositionBar.topAnchor),
            utilityOverlayView.bottomAnchor.constraint(equalTo: candidateBarStack.bottomAnchor),
            utilityOverlayButton.leadingAnchor.constraint(equalTo: utilityOverlayView.leadingAnchor, constant: 8),
            utilityOverlayButton.centerYAnchor.constraint(equalTo: utilityOverlayView.centerYAnchor),
            utilityOverlayButton.heightAnchor.constraint(equalToConstant: 28),
            utilityOverlayButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        view.bringSubviewToFront(candidatePageView)
        view.bringSubviewToFront(trackpadBlurView)
        view.bringSubviewToFront(keyPreviewView)
    }

    private func setupCandidatePage() {
        candidatePageView.translatesAutoresizingMaskIntoConstraints = false
        candidatePageView.isHidden = true
        candidatePageView.layer.cornerRadius = 10
        candidatePageView.layer.masksToBounds = true
        view.addSubview(candidatePageView)

        candidatePageCollapseButton.translatesAutoresizingMaskIntoConstraints = false
        candidatePageCollapseButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        candidatePageCollapseButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)
        candidatePageCollapseButton.layer.cornerRadius = 7
        candidatePageCollapseButton.layer.borderWidth = 0.5
        candidatePageCollapseButton.addAction(UIAction { [weak self] _ in
            self?.setCandidatePageVisible(false)
        }, for: .touchUpInside)
        candidatePageView.addSubview(candidatePageCollapseButton)

        candidatePageScrollView.translatesAutoresizingMaskIntoConstraints = false
        candidatePageScrollView.showsVerticalScrollIndicator = true
        candidatePageView.addSubview(candidatePageScrollView)

        candidatePageStack.axis = .vertical
        candidatePageStack.spacing = 6
        candidatePageStack.alignment = .fill
        candidatePageStack.distribution = .fill
        candidatePageStack.translatesAutoresizingMaskIntoConstraints = false
        candidatePageScrollView.addSubview(candidatePageStack)

        NSLayoutConstraint.activate([
            candidatePageView.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            candidatePageView.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            candidatePageView.topAnchor.constraint(equalTo: candidateBarStack.topAnchor),
            candidatePageView.bottomAnchor.constraint(equalTo: rootStack.bottomAnchor),

            candidatePageCollapseButton.topAnchor.constraint(equalTo: candidatePageView.topAnchor, constant: 4),
            candidatePageCollapseButton.trailingAnchor.constraint(equalTo: candidatePageView.trailingAnchor, constant: -4),
            candidatePageCollapseButton.heightAnchor.constraint(equalToConstant: 26),
            candidatePageCollapseButton.widthAnchor.constraint(equalToConstant: 42),

            candidatePageScrollView.leadingAnchor.constraint(equalTo: candidatePageView.leadingAnchor, constant: 6),
            candidatePageScrollView.trailingAnchor.constraint(equalTo: candidatePageView.trailingAnchor, constant: -6),
            candidatePageScrollView.topAnchor.constraint(equalTo: candidatePageCollapseButton.bottomAnchor, constant: 4),
            candidatePageScrollView.bottomAnchor.constraint(equalTo: candidatePageView.bottomAnchor, constant: -6),

            candidatePageStack.leadingAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.leadingAnchor),
            candidatePageStack.trailingAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.trailingAnchor),
            candidatePageStack.topAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.topAnchor),
            candidatePageStack.bottomAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.bottomAnchor),
            candidatePageStack.widthAnchor.constraint(equalTo: candidatePageScrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func renderKeyboard() {
        hideKeyPreview(animated: false)
        setCandidatePageVisible(false)
        keyButtons.removeAll()
        keyboardRowsStack.arrangedSubviews.forEach { view in
            keyboardRowsStack.removeArrangedSubview(view)
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
                    spacer.heightAnchor.constraint(equalToConstant: 41).isActive = true
                    rowSpacers.append(spacer)
                    continue
                }

                let button = makeButton(for: key)
                button.widthUnit = key.widthUnit
                rowStack.addArrangedSubview(button)
                button.heightAnchor.constraint(equalToConstant: 41).isActive = true
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

            keyboardRowsStack.addArrangedSubview(rowStack)
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
            KeySpec(.space, title: "空格", widthUnit: 3.55),
            KeySpec(.languageSwitch, widthUnit: 1),
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
                KeySpec(.space, title: "空格", widthUnit: 3.55),
                KeySpec(.languageSwitch, widthUnit: 1),
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
                KeySpec(.space, title: "空格", widthUnit: 3.55),
                KeySpec(.languageSwitch, widthUnit: 1),
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
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.contentEdgeInsets = .zero
        button.titleEdgeInsets = .zero
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.font = font(for: spec.kind)
        button.setTitle(title(for: spec), for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.handle(spec.kind)
        }, for: .touchUpInside)
        if shouldPreviewKey(spec.kind) {
            bindKeyPreviewEvents(to: button)
        }
        if case .space = spec.kind {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleKeyLongPress(_:)))
            recognizer.minimumPressDuration = 0.35
            recognizer.cancelsTouchesInView = true
            button.addGestureRecognizer(recognizer)
        }
        return button
    }

    private func shouldPreviewKey(_ kind: KeyKind) -> Bool {
        guard keyboardMode == .letters, case .character(let value) = kind else { return false }
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first else { return false }
        return Self.previewableLetterScalars.contains(scalar)
    }

    private func bindKeyPreviewEvents(to button: KeyboardKeyButton) {
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button = button else { return }
            self?.showKeyPreview(for: button)
        }, for: [.touchDown, .touchDragInside, .touchDragEnter])
        button.addAction(UIAction { [weak self] _ in
            self?.hideKeyPreview()
        }, for: [.touchDragExit, .touchUpInside, .touchUpOutside, .touchCancel])
    }

    private func showKeyPreview(for button: KeyboardKeyButton) {
        guard shouldPreviewKey(button.kind),
              let previewText = button.title(for: .normal),
              !previewText.isEmpty else {
            hideKeyPreview(animated: false)
            return
        }

        previewedKeyButton = button
        keyPreviewView.configure(
            text: previewText,
            backgroundColor: keyPreviewBackground,
            textColor: primaryText,
            shadowColor: shadowColor
        )

        let buttonFrame = button.convert(button.bounds, to: view)
        let previewSize = keyPreviewView.preferredSize(forButtonWidth: buttonFrame.width)
        let minX = Self.keyPreviewHorizontalInset
        let maxX = max(minX, view.bounds.width - previewSize.width - Self.keyPreviewHorizontalInset)
        let centeredX = buttonFrame.midX - previewSize.width / 2
        let originX = min(max(centeredX, minX), maxX)
        let originY = max(0, buttonFrame.minY - previewSize.height + 3)

        keyPreviewView.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: previewSize)
        keyPreviewView.isHidden = false
        keyPreviewView.alpha = 1
        keyPreviewView.setNeedsLayout()
        keyPreviewView.setNeedsDisplay()
        view.bringSubviewToFront(keyPreviewView)
    }

    private func hideKeyPreview(animated: Bool = true) {
        previewedKeyButton = nil
        guard !keyPreviewView.isHidden else { return }

        let hide = {
            self.keyPreviewView.alpha = 0
        }
        let complete: (Bool) -> Void = { _ in
            if self.previewedKeyButton == nil {
                self.keyPreviewView.isHidden = true
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.08,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: hide,
                completion: complete
            )
        } else {
            hide()
            complete(true)
        }
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
        case .languageSwitch:
            return inputLanguage == .chinese ? "英" : "中"
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
            if keyboardMode == .letters, inputLanguage == .chinese, value.rangeOfCharacter(from: .letters) != nil {
                associationContext = nil
                let letter = shiftState == .on ? value.uppercased() : value.lowercased()
                insertCompositionText(letter)
                updateCandidates(resetScroll: true)
            } else {
                commitCompositionAsText()
                associationContext = nil
                let text = keyboardMode == .letters && value.rangeOfCharacter(from: .letters) != nil
                    ? (shiftState == .on ? value.uppercased() : value.lowercased())
                    : value
                textDocumentProxy.insertText(text)
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
                associationContext = nil
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
                associationContext = nil
                hasInsertedTextInCurrentContext = true
            }
        case .returnKey:
            handleReturnKey()
        case .languageSwitch:
            commitCompositionAsText()
            associationContext = nil
            inputLanguage = inputLanguage == .chinese ? .english : .chinese
            renderKeyboard()
        case .spacer:
            break
        case .modeSwitch(let target):
            commitCompositionAsText()
            associationContext = nil
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
        guard let button = recognizer.view as? KeyboardKeyButton, case .space = button.kind else { return }
        let locationX = recognizer.location(in: view).x

        switch recognizer.state {
        case .began:
            hideKeyPreview(animated: false)
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
        if visible {
            view.bringSubviewToFront(trackpadBlurView)
        }
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

    private func handleCandidateSelection(_ candidate: KeyboardCandidate, index: Int) {
        highlightedCandidateIndex = index
        switch candidateMode {
        case .composition:
            replaceCompositionWith(candidate)
        case .association:
            insertAssociationCandidate(candidate.text)
        }
        if isCandidatePageVisible {
            setCandidatePageVisible(false)
        }
    }

    private func insertAssociationCandidate(_ text: String) {
        textDocumentProxy.insertText(text)
        hasInsertedTextInCurrentContext = true
        associationContext = limitedAssociationContext((associationContext ?? "") + text)
        updateCandidates(resetScroll: true)
    }

    private func limitedAssociationContext(_ text: String) -> String {
        let maxContextLength = 16
        guard text.count > maxContextLength else { return text }
        return String(text.suffix(maxContextLength))
    }

    private func replaceCompositionWith(_ candidate: KeyboardCandidate) {
        guard hasActiveComposition else {
            textDocumentProxy.insertText(candidate.text)
            hasInsertedTextInCurrentContext = true
            resetCompositionState()
            refreshCompositionDisplay()
            updateCandidates(resetScroll: true)
            return
        }

        let activePinyin = activeCandidatePinyin
        let consumeLength = max(0, min(candidate.consumeLength, activePinyin.count))
        let consumedPinyin = String(activePinyin.prefix(consumeLength))
        guard !consumedPinyin.isEmpty else { return }

        if candidate.recordsSelection {
            candidateProvider.recordSelection(candidate.text, for: consumedPinyin)
        }
        removeActivePinyinPrefix(length: consumeLength)
        selectedCompositionSegments.append(SelectedCompositionSegment(
            pinyin: consumedPinyin,
            text: candidate.text,
            recordsSelection: candidate.recordsSelection
        ))

        if compositionBuffer.isEmpty {
            let committedText = selectedCompositionText
            let committedPinyin = selectedCompositionPinyin
            if selectedCompositionSegments.count > 1, selectedCompositionSegments.allSatisfy({ $0.recordsSelection }) {
                candidateProvider.recordSelection(committedText, for: committedPinyin)
            }
            textDocumentProxy.insertText(committedText)
            hasInsertedTextInCurrentContext = true
            associationContext = limitedAssociationContext(committedText)
            resetCompositionState()
            refreshCompositionDisplay()
        } else {
            compositionCursorOffset = compositionBuffer.count
            refreshCompositionDisplay()
        }
        updateCandidates(resetScroll: true)
    }

    private func updateCandidates(resetScroll: Bool = false) {
        guard keyboardMode == .letters, inputLanguage == .chinese else {
            allCandidates = []
            visibleCandidateCount = 0
            candidateMode = .composition
            setCandidatePageVisible(false)
            renderVisibleCandidates()
            updateReturnKeyAppearance()
            return
        }
        let pinyin = activeCandidatePinyin
        if pinyin.isEmpty {
            if !hasActiveComposition, let associationContext {
                candidateMode = .association
                allCandidates = associationProvider.associations(for: associationContext).map { candidate in
                    KeyboardCandidate(text: candidate, consumeLength: 0)
                }
            } else {
                candidateMode = .composition
                allCandidates = []
            }
        } else {
            candidateMode = .composition
            allCandidates = self.candidates(for: pinyin)
        }
        visibleCandidateCount = min(Self.candidateBatchSize, allCandidates.count)
        if resetScroll || highlightedCandidateIndex >= visibleCandidateCount {
            highlightedCandidateIndex = 0
        }
        if allCandidates.isEmpty {
            setCandidatePageVisible(false)
        }
        renderVisibleCandidates()
        renderCandidatePageIfNeeded()
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
        updateCandidateExpandButtonVisibility()

        guard !allCandidates.isEmpty else {
            return
        }

        for (index, candidate) in allCandidates.prefix(visibleCandidateCount).enumerated() {
            let button = makeCandidateButton(candidate: candidate, index: index)
            candidateStack.addArrangedSubview(button)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
    }

    private func makeCandidateButton(candidate: KeyboardCandidate, index: Int) -> UIButton {
        let isHighlighted = index == highlightedCandidateIndex
        let button = UIButton(type: .system)
        button.setTitle(candidate.text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: isHighlighted ? .semibold : .regular)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
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
            self?.handleCandidateSelection(candidate, index: index)
        }, for: .touchUpInside)
        return button
    }

    private func updateCandidateExpandButtonVisibility() {
        let canExpand = keyboardMode == .letters && inputLanguage == .chinese && !allCandidates.isEmpty
        candidateExpandButton.isHidden = !canExpand
        if !canExpand {
            setCandidatePageVisible(false)
        }
    }

    private func setCandidatePageVisible(_ visible: Bool) {
        let shouldShow = visible && keyboardMode == .letters && inputLanguage == .chinese && !allCandidates.isEmpty
        guard isCandidatePageVisible != shouldShow || candidatePageView.isHidden == shouldShow else { return }

        isCandidatePageVisible = shouldShow
        candidatePageView.isHidden = !shouldShow
        if shouldShow {
            hideKeyPreview(animated: false)
            candidatePageScrollView.setContentOffset(.zero, animated: false)
            renderCandidatePage()
            view.bringSubviewToFront(candidatePageView)
            view.bringSubviewToFront(trackpadBlurView)
            view.bringSubviewToFront(keyPreviewView)
        } else {
            clearCandidatePage()
        }
    }

    private func renderCandidatePageIfNeeded() {
        guard isCandidatePageVisible else { return }
        renderCandidatePage()
    }

    private func renderCandidatePage() {
        clearCandidatePage()
        candidatePageRenderedWidth = candidatePageView.bounds.width
        guard !allCandidates.isEmpty else { return }

        let spacing: CGFloat = 6
        let minButtonWidth: CGFloat = 56
        let contentWidth = max(candidatePageView.bounds.width - 12, minButtonWidth)
        let columnCount = max(2, Int((contentWidth + spacing) / (minButtonWidth + spacing)))

        var rowStack: UIStackView?
        for (index, candidate) in allCandidates.enumerated() {
            if index % columnCount == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.spacing = spacing
                newRow.alignment = .fill
                newRow.distribution = .fillEqually
                candidatePageStack.addArrangedSubview(newRow)
                rowStack = newRow
            }

            let button = makeCandidateButton(candidate: candidate, index: index)
            rowStack?.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }

        if let rowStack = rowStack {
            let remainder = rowStack.arrangedSubviews.count % columnCount
            if remainder > 0 {
                for _ in 0..<(columnCount - remainder) {
                    let spacer = UIView()
                    rowStack.addArrangedSubview(spacer)
                    spacer.heightAnchor.constraint(equalToConstant: 34).isActive = true
                }
            }
        }
    }

    private func clearCandidatePage() {
        candidatePageStack.arrangedSubviews.forEach { view in
            candidatePageStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        candidatePageRenderedWidth = 0
    }

    private func appendMoreCandidatesIfNeeded() {
        guard visibleCandidateCount < allCandidates.count else { return }
        visibleCandidateCount = min(visibleCandidateCount + Self.candidateBatchSize, allCandidates.count)
        renderVisibleCandidates()
    }

    private func applyTheme() {
        updateKeyboardBackdropAppearance()

        for button in keyButtons {
            if let keyButton = button as? KeyboardKeyButton, case .returnKey = keyButton.kind {
                keyButton.setTitle(returnKeyTitle, for: .normal)
                keyButton.isEnabled = isReturnKeyEnabled
                keyButton.alpha = isReturnKeyEnabled ? 1 : 0.45
            } else {
                button.alpha = 1
            }
            let title = button.title(for: .normal) ?? ""
            let isSpecial = ["123", "ABC", "#+=", "⌫", "⇧", "英", "中", "搜索", "确认", "发送", "换行"].contains(title)
            button.backgroundColor = isSpecial ? specialKeyBackground : keyBackground
            button.setTitleColor(primaryText, for: .normal)
            button.layer.shadowColor = shadowColor.cgColor
        }
        utilityOverlayButton.setTitleColor(secondaryText, for: .normal)
        utilityOverlayButton.backgroundColor = candidateBackground
        utilityOverlayButton.layer.borderColor = candidateBorder.cgColor
        candidateExpandButton.tintColor = secondaryText
        candidateExpandButton.backgroundColor = candidateBackground
        candidateExpandButton.layer.borderColor = candidateBorder.cgColor
        candidatePageCollapseButton.tintColor = secondaryText
        candidatePageCollapseButton.backgroundColor = candidateBackground
        candidatePageCollapseButton.layer.borderColor = candidateBorder.cgColor
        updateCompositionBarAppearance()
        renderCandidatePageIfNeeded()
        if let previewedKeyButton = previewedKeyButton {
            showKeyPreview(for: previewedKeyButton)
        }
    }

    private func updateKeyboardBackdropAppearance() {
        if usesTransparentSearchBackdrop {
            view.backgroundColor = .clear
            keyboardBackdropView.effect = nil
            keyboardBackdropView.backgroundColor = .clear
        } else {
            view.backgroundColor = keyboardBackground
            keyboardBackdropView.effect = UIBlurEffect(style: .systemThinMaterial)
            keyboardBackdropView.backgroundColor = .clear
        }
        compositionBar.backgroundColor = .clear
        candidateScrollView.backgroundColor = .clear
        candidateStack.backgroundColor = .clear
        candidateBarStack.backgroundColor = .clear
        candidatePageView.backgroundColor = keyboardBackground
        candidatePageScrollView.backgroundColor = .clear
        candidatePageStack.backgroundColor = .clear
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

    private var usesTransparentSearchBackdrop: Bool {
        isSearchInput
    }

    private var keyBackground: UIColor {
        isDark ? UIColor(red: 0.39, green: 0.39, blue: 0.41, alpha: 1) : .white
    }

    private var keyPreviewBackground: UIColor {
        isDark ? UIColor(red: 0.46, green: 0.46, blue: 0.48, alpha: 1) : .white
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

    private func candidates(for pinyin: String) -> [KeyboardCandidate] {
        guard !pinyin.isEmpty else { return [] }
        let candidates = candidateProvider.candidates(for: pinyin).map { candidate in
            KeyboardCandidate(text: candidate.text, consumeLength: candidate.consumeLength)
        }
        return candidates + englishLetterCandidates(for: pinyin, existingCandidates: candidates)
    }

    private func englishLetterCandidates(
        for pinyin: String,
        existingCandidates: [KeyboardCandidate]
    ) -> [KeyboardCandidate] {
        let scalars = pinyin.unicodeScalars
        guard !scalars.isEmpty, scalars.allSatisfy({ Self.previewableLetterScalars.contains($0) }) else { return [] }

        var seen = Set(existingCandidates.map { $0.text })
        return [pinyin.uppercased(), pinyin.lowercased()].compactMap { text in
            guard seen.insert(text).inserted else { return nil }
            return KeyboardCandidate(text: text, consumeLength: pinyin.count, recordsSelection: false)
        }
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

    private func handleUtilityFillButtonTap() {
        hideKeyPreview(animated: false)
        setCandidatePageVisible(false)
        finalizeComposition()
        associationContext = nil
        textDocumentProxy.insertText(Self.utilityFillText)
        hasInsertedTextInCurrentContext = true
        updateCandidates(resetScroll: true)
    }

    private func finalizeComposition() {
        let text = compositionText
        guard !text.isEmpty else {
            associationContext = nil
            resetCompositionState()
            refreshCompositionDisplay()
            updateCandidates(resetScroll: true)
            return
        }
        textDocumentProxy.insertText(text)
        hasInsertedTextInCurrentContext = true
        associationContext = nil
        resetCompositionState()
        refreshCompositionDisplay()
        updateCandidates(resetScroll: true)
    }

    private func removeActivePinyinPrefix(length: Int) {
        let prefixLength = max(0, min(length, compositionBuffer.count))
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
        CGSize(width: 32 * widthUnit, height: 41)
    }
}

private final class KeyPreviewView: UIView {
    private let label = UILabel()
    private var fillColor = UIColor.white
    private var tailHeight: CGFloat { 10 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear

        label.textAlignment = .center
        label.font = .systemFont(ofSize: 34, weight: .regular)
        addSubview(label)

        layer.shadowOpacity = 0.24
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, backgroundColor: UIColor, textColor: UIColor, shadowColor: UIColor) {
        label.text = text
        label.textColor = textColor
        fillColor = backgroundColor
        layer.shadowColor = shadowColor.cgColor
        setNeedsDisplay()
    }

    func preferredSize(forButtonWidth buttonWidth: CGFloat) -> CGSize {
        CGSize(width: max(54, min(72, buttonWidth + 24)), height: 68)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bubbleRect = bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: tailHeight, right: 0))
        label.frame = bubbleRect.insetBy(dx: 0, dy: 4)
        layer.shadowPath = previewPath(in: bounds).cgPath
    }

    override func draw(_ rect: CGRect) {
        fillColor.setFill()
        previewPath(in: bounds).fill()
    }

    private func previewPath(in rect: CGRect) -> UIBezierPath {
        let bubbleRect = rect.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: tailHeight, right: 0))
        let path = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 12)
        let tailWidth: CGFloat = 15
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: rect.midX - tailWidth / 2, y: bubbleRect.maxY - 1))
        tail.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        tail.addLine(to: CGPoint(x: rect.midX + tailWidth / 2, y: bubbleRect.maxY - 1))
        tail.close()
        path.append(tail)
        return path
    }
}

private final class KeyboardKeySpacer: UIView {
    var widthUnit: CGFloat = 1

    override var intrinsicContentSize: CGSize {
        CGSize(width: 32 * widthUnit, height: 41)
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
    case languageSwitch
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
    let tier: Int
    let wordLength: Int
    let syllableCount: Int
    let consumeLength: Int

    init(text: String, weight: Int, tier: Int = 2, wordLength: Int? = nil, syllableCount: Int = 1, consumeLength: Int = 0) {
        self.text = text
        self.weight = weight
        self.tier = tier
        self.wordLength = wordLength ?? text.count
        self.syllableCount = syllableCount
        self.consumeLength = consumeLength
    }
}

private struct PinyinCompletion {
    let key: String
    let consumeLength: Int
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

    private static let completionPriority: [String: [String]] = [
        "k": ["kan", "kao", "kai", "kuai", "ke", "kong", "kou", "ku", "kang", "ken", "keng", "ka", "kuan", "kuang", "kui", "kun", "kuo", "kua"],
        "x": ["xiang", "xin", "xing", "xian", "xiao", "xue", "xi", "xia", "xie", "xiu", "xu", "xuan", "xun", "xiong"]
    ]

    private static let orderedSyllables = syllables.sorted {
        if $0.count != $1.count {
            return $0.count < $1.count
        }
        return $0 < $1
    }

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

    static func completionKeys(for key: String, limit: Int) -> [PinyinCompletion] {
        let partial = partialSegmentation(for: key)
        guard !partial.remainder.isEmpty, partial.remainder.count <= 3 else {
            return []
        }
        let chunks = prefixChunks(for: partial.remainder)
        guard !chunks.isEmpty else { return [] }

        let completions = chunks.map { completionSyllables(for: $0) }
        guard completions.allSatisfy({ !$0.isEmpty }) else { return [] }

        let baseKey = partial.segments.joined(separator: "")
        let baseConsumeLength = partial.segments.reduce(0) { $0 + $1.count }
        var results: [PinyinCompletion] = []
        var seen: Set<String> = []

        func append(_ key: String, consumedChunks: Int) {
            guard results.count < limit, key != baseKey, seen.insert(key).inserted else { return }
            let consumeLength = baseConsumeLength + chunks.prefix(consumedChunks).reduce(0) { $0 + $1.count }
            results.append(PinyinCompletion(key: key, consumeLength: consumeLength))
        }

        let primaryCompletion = completions.compactMap { $0.first }.joined(separator: "")
        append(baseKey + primaryCompletion, consumedChunks: completions.count)
        if completions.count > 1 {
            for count in stride(from: completions.count - 1, through: 1, by: -1) {
                let partialCompletion = completions.prefix(count).compactMap { $0.first }.joined(separator: "")
                append(baseKey + partialCompletion, consumedChunks: count)
            }
        }

        func build(index: Int, key: String) {
            guard results.count < limit else { return }
            if index == completions.count {
                append(key, consumedChunks: completions.count)
                return
            }

            for syllable in completions[index] {
                build(index: index + 1, key: key + syllable)
                if results.count >= limit {
                    break
                }
            }
        }

        build(index: 0, key: baseKey)
        return results
    }

    private static func partialSegmentation(for key: String) -> (segments: [String], remainder: String) {
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

            guard let best else {
                return (result, String(key[index...]))
            }
            result.append(best)
            index = key.index(index, offsetBy: best.count)
        }

        return (result, "")
    }

    private static func prefixChunks(for remainder: String) -> [String] {
        var chunks: [String] = []
        var index = remainder.startIndex

        while index < remainder.endIndex {
            var best: String?
            var end = remainder.index(index, offsetBy: min(4, remainder.distance(from: index, to: remainder.endIndex)), limitedBy: remainder.endIndex) ?? remainder.endIndex
            while end > index {
                let piece = String(remainder[index..<end])
                if hasSyllable(withPrefix: piece) {
                    best = piece
                    break
                }
                end = remainder.index(before: end)
            }

            guard let best else { return [] }
            chunks.append(best)
            index = remainder.index(index, offsetBy: best.count)
        }

        return chunks
    }

    private static func completionSyllables(for prefix: String) -> [String] {
        let matching = orderedSyllables.filter { $0.hasPrefix(prefix) }
        guard !matching.isEmpty else { return [] }

        let priority = completionPriority[prefix] ?? []
        let prioritySet = Set(priority)
        return priority.filter { syllables.contains($0) && $0.hasPrefix(prefix) }
            + matching.filter { !prioritySet.contains($0) }
    }

    private static func hasSyllable(withPrefix prefix: String) -> Bool {
        orderedSyllables.contains { $0.hasPrefix(prefix) }
    }
}

private final class PinyinAssociationProvider {
    private struct IndexRecord {
        let key: String
        let offset: UInt64
        let length: Int
    }

    private static let recordSize = 44
    private static let keySize = 32

    private let associationsURL = Bundle.main.url(forResource: "PinyinAssociations", withExtension: "tsv")
    private let indexURL = Bundle.main.url(forResource: "PinyinAssociations", withExtension: "idx")
    private let recordCount: Int

    init() {
        if let indexURL,
           let size = try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.size] as? NSNumber {
            recordCount = size.intValue / Self.recordSize
        } else {
            recordCount = 0
        }
    }

    func associations(for context: String) -> [String] {
        let keys = lookupKeys(for: context)
        guard !keys.isEmpty else { return [] }

        var candidates: [PinyinCandidate] = []
        for (index, key) in keys.enumerated() {
            let baseWeight = 1_000_000 - index * 100_000
            candidates += weightedAssociations(for: key, baseWeight: baseWeight)
        }
        return merge(candidates).map(\.text)
    }

    private func lookupKeys(for context: String) -> [String] {
        let text = String(context.compactMap { character -> Character? in
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first,
                  scalar.value >= 0x4e00,
                  scalar.value <= 0x9fff else {
                return nil
            }
            return character
        })
        guard text.count >= 2 else { return [] }

        let maxLength = min(4, text.count)
        return stride(from: maxLength, through: 2, by: -1).map { length in
            let start = text.index(text.endIndex, offsetBy: -length)
            return String(text[start...])
        }
    }

    private func weightedAssociations(for key: String, baseWeight: Int) -> [PinyinCandidate] {
        guard let lineCandidates = bundledAssociations(for: key) else { return [] }
        return lineCandidates.map { candidate in
            PinyinCandidate(text: candidate.text, weight: candidate.weight + baseWeight)
        }
    }

    private func bundledAssociations(for key: String) -> [PinyinCandidate]? {
        guard let associationsURL, let indexURL, recordCount > 0 else { return nil }
        guard let record = findRecord(for: key, in: indexURL) else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: associationsURL) else { return nil }
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
                    Self.parseCandidateField(String(field), fallbackWeight: 80 - index)
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

            let offset = Self.uint64LE(data, start: Self.keySize)
            let length = Int(Self.uint32LE(data, start: Self.keySize + 8))
            return IndexRecord(key: key, offset: offset, length: length)
        } catch {
            return nil
        }
    }

    private func merge(_ candidates: [PinyinCandidate]) -> [PinyinCandidate] {
        var bestByText: [String: PinyinCandidate] = [:]
        for candidate in candidates where !candidate.text.isEmpty {
            if let current = bestByText[candidate.text], current.weight >= candidate.weight {
                continue
            }
            bestByText[candidate.text] = candidate
        }
        return Array(bestByText.values)
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

    private static func parseCandidateField(_ field: String, fallbackWeight: Int) -> PinyinCandidate {
        let parts = field.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 5 {
            let text = parts.dropLast(4).map(String.init).joined(separator: ":")
            let metadata = parts.suffix(4).map(String.init)
            return PinyinCandidate(
                text: text,
                weight: Int(metadata[0]) ?? fallbackWeight,
                tier: Int(metadata[1]) ?? 2,
                wordLength: Int(metadata[2]) ?? text.count,
                syllableCount: Int(metadata[3]) ?? 1
            )
        }

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
}

private final class PinyinCandidateProvider {
    private struct IndexRecord {
        let keyHash: UInt64
        let offset: UInt64
        let length: Int
    }

    private struct SelectionMemoryEntry {
        let count: Int
        let lastUsed: TimeInterval
    }

    private struct BeamPath {
        let text: String
        let score: Int
        let parts: Int
    }

    private enum MatchKind {
        case exact
        case completion
        case prefix
        case beam
        case fallback
    }

    private static let memoryDefaultsKey = "pinyinCandidateSelectionMemory.v2"
    private static let legacyMemoryDefaultsKey = "pinyinCandidateSelectionMemory.v1"
    private static let maxMemoryEntries = 1_000
    private static let maxMemoryCount = 100
    private static let memoryFrequencyStep = 160_000
    private static let maxMemoryBoost = 2_500_000
    private static let recordSize = 20
    private static let fnvOffsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let fnvPrime: UInt64 = 1_099_511_628_211
    private static let maxBeamSyllables = 8
    private static let maxBeamSpan = 4
    private static let maxBeamWidth = 8
    private static let maxCompletionKeys = 32
    private static let completionRankPenalty = 120_000

    private let lexiconURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "tsv")
    private let indexURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "idx")
    private let defaults = UserDefaults.standard
    private let recordCount: Int

    init() {
        if let indexURL,
           let size = try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.size] as? NSNumber {
            recordCount = size.intValue / Self.recordSize
        } else {
            recordCount = 0
        }
    }

    func candidates(for pinyin: String) -> [PinyinCandidate] {
        let key = Self.normalizedKey(pinyin)
        guard !key.isEmpty else { return [] }

        var lookupCache: [String: [PinyinCandidate]] = [:]
        var candidates: [PinyinCandidate] = []
        candidates += scoredCandidates(for: key, match: .exact, consumeLength: key.count, cache: &lookupCache)
        let completionCandidates = completionCandidates(for: key, cache: &lookupCache)
        candidates += completionCandidates

        let segments = PinyinSegmenter.segment(key)
        if segments.count > 1 {
            candidates += beamCandidates(from: segments, fullKey: key, cache: &lookupCache)
        }

        if !completionCandidates.isEmpty || candidates.count < 16 {
            candidates += longestPrefixCandidates(for: key, cache: &lookupCache)
        }
        candidates += fallbackCandidates(for: key)

        return applyUserMemory(to: merge(candidates), key: key)
    }

    func recordSelection(_ text: String, for pinyin: String) {
        let key = Self.normalizedKey(pinyin)
        guard !key.isEmpty, !text.isEmpty else { return }

        let memoryKey = Self.memoryKey(pinyin: key, text: text)
        var memory = selectionMemory
        let current = memory[memoryKey]
        let nextCount = min(Self.maxMemoryCount, (current?.count ?? 0) + 1)
        memory[memoryKey] = SelectionMemoryEntry(count: nextCount, lastUsed: Date().timeIntervalSince1970)

        if memory.count > Self.maxMemoryEntries {
            let sortedKeys = memory.sorted {
                if $0.value.count != $1.value.count {
                    return $0.value.count > $1.value.count
                }
                if $0.value.lastUsed != $1.value.lastUsed {
                    return $0.value.lastUsed > $1.value.lastUsed
                }
                return $0.key < $1.key
            }.prefix(Self.maxMemoryEntries).map(\.key)
            memory = Dictionary(uniqueKeysWithValues: sortedKeys.compactMap { key in
                memory[key].map { (key, $0) }
            })
        }

        let storage = memory.mapValues { entry in
            [
                "count": entry.count,
                "lastUsed": entry.lastUsed
            ] as [String: Any]
        }
        defaults.set(storage, forKey: Self.memoryDefaultsKey)
    }

    private func cachedBundledCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        if let cached = cache[key] {
            return cached
        }
        let candidates = bundledCandidates(for: key) ?? []
        cache[key] = candidates
        return candidates
    }

    private func scoredCandidates(
        for key: String,
        match: MatchKind,
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        cachedBundledCandidates(for: key, cache: &cache).map { candidate in
            scoredCandidate(candidate, match: match, consumeLength: consumeLength)
        }
    }

    private func longestPrefixCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        var lookupKey = key
        while !lookupKey.isEmpty {
            lookupKey.removeLast()
            guard !lookupKey.isEmpty else { break }
            let candidates = scoredCandidates(for: lookupKey, match: .prefix, consumeLength: lookupKey.count, cache: &cache)
            if !candidates.isEmpty {
                return candidates
            }
        }
        return []
    }

    private func completionCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        PinyinSegmenter.completionKeys(for: key, limit: Self.maxCompletionKeys).enumerated().flatMap { rank, completion in
            scoredCandidates(for: completion.key, match: .completion, consumeLength: completion.consumeLength, cache: &cache).prefix(4).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight - rank * Self.completionRankPenalty,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
        }
    }

    private func beamCandidates(
        from segments: [String],
        fullKey: String,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        guard segments.count > 1, segments.count <= Self.maxBeamSyllables else { return [] }

        var paths = Array(repeating: [BeamPath](), count: segments.count + 1)
        paths[0] = [BeamPath(text: "", score: 0, parts: 0)]

        for start in 0..<segments.count {
            guard !paths[start].isEmpty else { continue }
            let maxEnd = min(segments.count, start + Self.maxBeamSpan)
            for path in paths[start] {
                for end in (start + 1)...maxEnd {
                    let lookupKey = segments[start..<end].joined(separator: "")
                    guard lookupKey != fullKey else { continue }

                    let limit = end - start == 1 ? 4 : 8
                    let candidates = cachedBundledCandidates(for: lookupKey, cache: &cache).prefix(limit)
                    for candidate in candidates {
                        let text = path.text + candidate.text
                        guard text.count <= 16 else { continue }
                        let score = path.score + beamPartScore(candidate, span: end - start)
                        paths[end].append(BeamPath(text: text, score: score, parts: path.parts + 1))
                    }
                    paths[end] = pruneBeamPaths(paths[end])
                }
            }
        }

        return pruneBeamPaths(paths[segments.count])
            .filter { $0.parts > 1 }
            .map { path in
                let averageScore = path.score / max(1, path.parts)
                let score = 6_200_000 + averageScore - path.parts * 60_000
                return PinyinCandidate(
                    text: path.text,
                    weight: score,
                    tier: 2,
                    wordLength: path.text.count,
                    syllableCount: segments.count,
                    consumeLength: fullKey.count
                )
            }
    }

    private func pruneBeamPaths(_ paths: [BeamPath]) -> [BeamPath] {
        var bestByText: [String: BeamPath] = [:]
        for path in paths where !path.text.isEmpty || path.parts == 0 {
            if let current = bestByText[path.text], current.score >= path.score {
                continue
            }
            bestByText[path.text] = path
        }
        return bestByText.values.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.parts != $1.parts {
                return $0.parts < $1.parts
            }
            return $0.text < $1.text
        }.prefix(Self.maxBeamWidth).map { $0 }
    }

    private func fallbackCandidates(for key: String) -> [PinyinCandidate] {
        var candidates: [PinyinCandidate] = []

        if let exact = Self.fallbackDictionary[key] {
            candidates += exact.enumerated().map { index, text in
                PinyinCandidate(text: text, weight: 1_000_000 + 10_000 - index, tier: 5, consumeLength: key.count)
            }
        }

        let prefixCandidates = Self.fallbackDictionary
            .filter { $0.key.hasPrefix(key) }
            .sorted { $0.key.count == $1.key.count ? $0.key < $1.key : $0.key.count < $1.key.count }
            .flatMap(\.value)

        candidates += prefixCandidates.enumerated().map { index, text in
            PinyinCandidate(text: text, weight: 900_000 - index, tier: 5, consumeLength: key.count)
        }

        return candidates
    }

    private func scoredCandidate(_ candidate: PinyinCandidate, match: MatchKind, consumeLength: Int) -> PinyinCandidate {
        let baseScore: Int
        let lengthBonus: Int
        switch match {
        case .exact:
            baseScore = 10_000_000
            lengthBonus = min(candidate.wordLength, 8) * 45_000
        case .completion:
            baseScore = 8_400_000
            lengthBonus = min(candidate.wordLength, 8) * 35_000
        case .prefix:
            baseScore = 4_800_000
            lengthBonus = min(candidate.wordLength, 8) * 20_000
        case .beam:
            baseScore = 6_200_000
            lengthBonus = min(candidate.wordLength, 8) * 25_000
        case .fallback:
            baseScore = 900_000
            lengthBonus = 0
        }

        let score = baseScore
            + dictionaryScore(candidate.weight)
            + tierBonus(candidate.tier)
            + lengthBonus
            + min(candidate.syllableCount, 6) * 35_000

        return PinyinCandidate(
            text: candidate.text,
            weight: score,
            tier: candidate.tier,
            wordLength: candidate.wordLength,
            syllableCount: candidate.syllableCount,
            consumeLength: consumeLength
        )
    }

    private func beamPartScore(_ candidate: PinyinCandidate, span: Int) -> Int {
        let singleCharacterPenalty = span == 1 && candidate.wordLength == 1 ? 500_000 : 0
        return dictionaryScore(candidate.weight)
            + tierBonus(candidate.tier)
            + min(candidate.wordLength, 8) * 30_000
            + max(0, span - 1) * 350_000
            - singleCharacterPenalty
    }

    private func dictionaryScore(_ weight: Int) -> Int {
        min(max(weight, 1), 1_200_000)
    }

    private func tierBonus(_ tier: Int) -> Int {
        if tier <= 0 {
            return 600_000
        }
        switch tier {
        case 1:
            return 420_000
        case 2:
            return 260_000
        case 3:
            return 120_000
        case 4:
            return 40_000
        default:
            return 0
        }
    }

    private func merge(_ candidates: [PinyinCandidate]) -> [PinyinCandidate] {
        var bestByText: [String: PinyinCandidate] = [:]
        for candidate in candidates where !candidate.text.isEmpty {
            if let current = bestByText[candidate.text], current.weight >= candidate.weight {
                continue
            }
            bestByText[candidate.text] = candidate
        }
        return Array(bestByText.values)
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

    private func applyUserMemory(to candidates: [PinyinCandidate], key: String) -> [PinyinCandidate] {
        let memory = selectionMemory
        let now = Date().timeIntervalSince1970
        return candidates
            .map { candidate in
                let entry = memory[Self.memoryKey(pinyin: key, text: candidate.text)]
                let boost = memoryBoost(for: entry, now: now)
                return PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + boost,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
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

    private func memoryBoost(for entry: SelectionMemoryEntry?, now: TimeInterval) -> Int {
        guard let entry else { return 0 }

        let frequency = min(Self.maxMemoryCount, entry.count) * Self.memoryFrequencyStep
        let recency: Int
        if entry.lastUsed > 0 {
            let ageDays = max(0, (now - entry.lastUsed) / 86_400)
            recency = max(0, 350_000 - Int(ageDays * 20_000))
        } else {
            recency = 0
        }

        return min(Self.maxMemoryBoost, frequency + recency)
    }

    private var selectionMemory: [String: SelectionMemoryEntry] {
        if let rawMemory = defaults.dictionary(forKey: Self.memoryDefaultsKey) {
            return parseSelectionMemory(rawMemory)
        }
        guard let legacyMemory = defaults.dictionary(forKey: Self.legacyMemoryDefaultsKey) else { return [:] }
        return legacyMemory.compactMapValues { value in
            if let count = value as? Int {
                return SelectionMemoryEntry(count: count, lastUsed: 0)
            }
            if let count = value as? NSNumber {
                return SelectionMemoryEntry(count: count.intValue, lastUsed: 0)
            }
            return nil
        }
    }

    private func parseSelectionMemory(_ rawMemory: [String: Any]) -> [String: SelectionMemoryEntry] {
        return rawMemory.compactMapValues { value in
            if let entry = value as? [String: Any] {
                return Self.parseMemoryEntry(entry)
            }
            if let entry = value as? [String: NSNumber] {
                return SelectionMemoryEntry(
                    count: entry["count"]?.intValue ?? 0,
                    lastUsed: entry["lastUsed"]?.doubleValue ?? 0
                )
            }
            return nil
        }
    }

    private static func parseMemoryEntry(_ entry: [String: Any]) -> SelectionMemoryEntry {
        let count: Int
        if let value = entry["count"] as? Int {
            count = value
        } else if let value = entry["count"] as? NSNumber {
            count = value.intValue
        } else {
            count = 0
        }

        let lastUsed: TimeInterval
        if let value = entry["lastUsed"] as? TimeInterval {
            lastUsed = value
        } else if let value = entry["lastUsed"] as? NSNumber {
            lastUsed = value.doubleValue
        } else {
            lastUsed = 0
        }

        return SelectionMemoryEntry(count: count, lastUsed: lastUsed)
    }

    private static func memoryKey(pinyin: String, text: String) -> String {
        pinyin + "\t" + text
    }

    private func bundledCandidates(for key: String) -> [PinyinCandidate]? {
        guard let lexiconURL, let indexURL, recordCount > 0 else { return nil }
        let records = findRecords(for: key, in: indexURL)
        guard !records.isEmpty else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: lexiconURL) else { return nil }
        defer { try? handle.close() }

        for record in records {
            do {
                try handle.seek(toOffset: record.offset)
                let data = try handle.read(upToCount: record.length) ?? Data()
                guard let line = String(data: data, encoding: .utf8) else { continue }
                let fields = line
                    .trimmingCharacters(in: .newlines)
                    .split(separator: "\t", omittingEmptySubsequences: true)
                guard fields.first.map(String.init) == key else { continue }
                return fields
                    .dropFirst()
                    .enumerated()
                    .map { index, field in
                        Self.parseCandidateField(String(field), fallbackWeight: 120 - index)
                    }
            } catch {
                continue
            }
        }

        return nil
    }

    private func findRecords(for key: String, in indexURL: URL) -> [IndexRecord] {
        guard let handle = try? FileHandle(forReadingFrom: indexURL) else { return [] }
        defer { try? handle.close() }

        let targetHash = Self.hashKey(key)
        var low = 0
        var high = recordCount

        while low < high {
            let mid = (low + high) / 2
            guard let record = readRecord(at: mid, from: handle) else { return [] }
            if record.keyHash < targetHash {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var results: [IndexRecord] = []
        var index = low
        while index < recordCount {
            guard let record = readRecord(at: index, from: handle), record.keyHash == targetHash else {
                break
            }
            results.append(record)
            index += 1
        }

        return results
    }

    private func readRecord(at index: Int, from handle: FileHandle) -> IndexRecord? {
        do {
            try handle.seek(toOffset: UInt64(index * Self.recordSize))
            let data = try handle.read(upToCount: Self.recordSize) ?? Data()
            guard data.count == Self.recordSize else { return nil }

            let keyHash = Self.uint64LE(data, start: 0)
            let offset = Self.uint64LE(data, start: 8)
            let length = Int(Self.uint32LE(data, start: 16))
            return IndexRecord(keyHash: keyHash, offset: offset, length: length)
        } catch {
            return nil
        }
    }

    private static func normalizedKey(_ value: String) -> String {
        String(value.lowercased().filter { character in
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first else {
                return false
            }
            return scalar.value >= 97 && scalar.value <= 122
        })
    }

    private static func hashKey(_ key: String) -> UInt64 {
        var result = Self.fnvOffsetBasis
        for byte in key.utf8 {
            result ^= UInt64(byte)
            result = result &* Self.fnvPrime
        }
        return result
    }

    private static func parseCandidateField(_ field: String, fallbackWeight: Int) -> PinyinCandidate {
        let parts = field.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 5 {
            let text = parts.dropLast(4).map(String.init).joined(separator: ":")
            let metadata = parts.suffix(4).map(String.init)
            return PinyinCandidate(
                text: text,
                weight: Int(metadata[0]) ?? fallbackWeight,
                tier: Int(metadata[1]) ?? 2,
                wordLength: Int(metadata[2]) ?? text.count,
                syllableCount: Int(metadata[3]) ?? 1
            )
        }

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
