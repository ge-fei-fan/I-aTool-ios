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

    private enum QuickFillPanelTab {
        case commonPhrases
        case clipboard
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
    private let rootStack = KeyboardRootStack()
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
    private let utilityOverlayStack = UIStackView()
    private let utilityOverlayButton = UIButton(type: .system)
    private let candidateQueue = DispatchQueue(label: "com.local.fitnex.keyboard.candidates", qos: .userInitiated)
    private var utilityOverlayIconButtons: [UIButton] = []
    private var allCandidates: [KeyboardCandidate] = []
    private var visibleCandidateCount = 0
    private var highlightedCandidateIndex = 0
    private var candidateMode: CandidateMode = .composition
    private var candidateRefreshWorkItem: DispatchWorkItem?
    private var candidateRefreshGeneration = 0
    private var isCandidateRefreshPending = false
    private var associationContext: String?
    private var keyButtons: [UIButton] = []
    private var proxySpacerButtons: [KeyboardProxySpacerButton] = []
    private var edgeProxyButtons: [KeyboardProxySpacerButton] = []
    private var selectedCompositionSegments: [SelectedCompositionSegment] = []
    private var compositionBuffer = ""
    private var compositionCursorOffset = 0
    private var keyboardMode: KeyboardMode = .letters
    private var inputLanguage: InputLanguage = .chinese
    private var shiftState: ShiftState = .off
    private weak var previewedKeySourceView: UIView?
    private var previewedKeyText: String?
    private var pendingKeyPreviewHideWorkItem: DispatchWorkItem?
    private var keyPreviewShownAt: TimeInterval = 0
    private var isCandidatePageVisible = false
    private var candidatePageRenderedWidth: CGFloat = 0
    private var isTrackpadActive = false
    private var suppressNextKeyTap = false
    private var trackpadPreviousX: CGFloat = 0
    private var trackpadAccumulatedX: CGFloat = 0
    private var hasInsertedTextInCurrentContext = false
    private let trackpadActivationFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let trackpadMovementFeedback = UISelectionFeedbackGenerator()
    private var quickFillItems: [String] = []
    private var isQuickFillPanelVisible = false
    private var selectedQuickFillPanelTab: QuickFillPanelTab = .commonPhrases
    private var candidatePageTopToCandidateBarConstraint: NSLayoutConstraint?
    private var candidatePageTopToViewConstraint: NSLayoutConstraint?
    private var candidatePageCollapseButtonLeadingConstraint: NSLayoutConstraint?
    private var candidatePageCollapseButtonTrailingConstraint: NSLayoutConstraint?
    private var candidatePageScrollTopToCollapseConstraint: NSLayoutConstraint?
    private var candidatePageScrollTopToPageConstraint: NSLayoutConstraint?

    private static let candidateBatchSize = 30
    private static let candidatePanelAnimationDuration: TimeInterval = 0.22
    private static let candidateRefreshDelay: TimeInterval = 0.012
    private static let candidateToggleButtonWidth: CGFloat = 34
    private static let candidateToggleButtonHeight: CGFloat = 30
    private static let keyboardIconPointSize: CGFloat = 24
    private static let quickFillBackIconPointSize: CGFloat = 28
    private static let shiftKeyImagePointSize: CGFloat = 30
    private static let shiftKeyImageVerticalAlignment: CGFloat = 0.18
    private static let trackpadStepWidth: CGFloat = 10
    private static let keyPreviewHorizontalInset: CGFloat = 4
    private static let keyTouchOutset: CGFloat = 6
    private static let proxySpacerPreviewMinimumVisibleDuration: TimeInterval = 0.09
    private static let previewableLetterScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private enum KeyboardIconAsset {
        case diversity
        case heart
        case happy
        case arrowDown
        case arrowUp
        case back

        var fileName: String {
            switch self {
            case .diversity:
                return "icons8-diversity-50"
            case .heart:
                return "icons8-heart-50"
            case .happy:
                return "icons8-happy-50"
            case .arrowDown:
                return "icons8-expand-arrow-50"
            case .arrowUp:
                return "icons8-collapse-arrow-50"
            case .back:
                return "icons8-返回-48"
            }
        }
    }

    private enum KeyboardKeyIconAsset {
        case shift
        case backspace

        var fileName: String {
            switch self {
            case .shift:
                return "cat1"
            case .backspace:
                return "icons8-clear-symbol-48"
            }
        }
    }

    private var isDark: Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadQuickFillItems()
        setupKeyboard()
        renderKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadQuickFillItems()
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
        guard isCandidatePageVisible || isQuickFillPanelVisible else { return }
        let width = candidatePageView.bounds.width
        if abs(width - candidatePageRenderedWidth) > 1 {
            if isQuickFillPanelVisible {
                renderQuickFillPanel()
            } else {
                renderCandidatePage()
            }
        }
    }

    private func setupKeyboard() {
        updateKeyboardBackdropAppearance()

        keyboardBackdropView.translatesAutoresizingMaskIntoConstraints = false
        keyboardBackdropView.isUserInteractionEnabled = false
        view.addSubview(keyboardBackdropView)

        rootStack.axis = .vertical
        rootStack.spacing = 7
        rootStack.touchTargetOutset = Self.keyTouchOutset
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
        // Clear button is disabled for now.
        // compositionBar.onClearRequested = { [weak self] in
        //     self?.clearCompositionFromBar()
        // }
        rootStack.addArrangedSubview(compositionBar)
        compositionBar.heightAnchor.constraint(equalToConstant: 30).isActive = true

        candidateBarStack.axis = .horizontal
        candidateBarStack.spacing = 6
        candidateBarStack.alignment = .fill
        candidateBarStack.distribution = .fill
        rootStack.addArrangedSubview(candidateBarStack)
        candidateBarStack.heightAnchor.constraint(equalToConstant: 32).isActive = true

        candidateScrollView.showsHorizontalScrollIndicator = false
        candidateScrollView.alwaysBounceHorizontal = true
        candidateScrollView.clipsToBounds = true
        candidateScrollView.delegate = self
        candidateBarStack.addArrangedSubview(candidateScrollView)

        candidateExpandButton.translatesAutoresizingMaskIntoConstraints = false
        configureCandidateToggleButton(candidateExpandButton, asset: .arrowDown, fallbackSystemName: "chevron.down")
        candidateExpandButton.isHidden = true
        candidateExpandButton.addAction(UIAction { [weak self] _ in
            self?.setCandidatePageVisible(true)
        }, for: .touchUpInside)
        candidateBarStack.addArrangedSubview(candidateExpandButton)
        candidateExpandButton.widthAnchor.constraint(equalToConstant: Self.candidateToggleButtonWidth).isActive = true

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
        keyboardRowsStack.spacing = 12
        keyboardRowsStack.alignment = .fill
        keyboardRowsStack.distribution = .fill
        rootStack.addArrangedSubview(keyboardRowsStack)

        utilityOverlayView.translatesAutoresizingMaskIntoConstraints = false
        utilityOverlayView.isUserInteractionEnabled = true
        utilityOverlayView.isHidden = true
        utilityOverlayView.backgroundColor = .clear
        view.addSubview(utilityOverlayView)

        utilityOverlayStack.translatesAutoresizingMaskIntoConstraints = false
        utilityOverlayStack.axis = .horizontal
        utilityOverlayStack.alignment = .top
        utilityOverlayStack.distribution = .equalSpacing
        utilityOverlayStack.spacing = 16
        utilityOverlayView.addSubview(utilityOverlayStack)

        configureUtilityIconButton(utilityOverlayButton, asset: .diversity, fallbackSystemName: "person.2", accessibilityLabel: "Function")
        utilityOverlayButton.isUserInteractionEnabled = false
        utilityOverlayStack.addArrangedSubview(utilityOverlayButton)
        utilityOverlayIconButtons.append(utilityOverlayButton)

        let utilityItems: [(asset: KeyboardIconAsset, fallbackSystemName: String, label: String, dismissesKeyboard: Bool, opensQuickFill: Bool)] = [
            (asset: .heart, fallbackSystemName: "heart", label: "Quick fill", dismissesKeyboard: false, opensQuickFill: true),
            (asset: .happy, fallbackSystemName: "face.smiling", label: "Dictation", dismissesKeyboard: false, opensQuickFill: false),
            (asset: .happy, fallbackSystemName: "face.smiling", label: "Cursor", dismissesKeyboard: false, opensQuickFill: false),
            (asset: .happy, fallbackSystemName: "face.smiling", label: "Emoji", dismissesKeyboard: false, opensQuickFill: false),
            (asset: .arrowDown, fallbackSystemName: "chevron.down", label: "Dismiss keyboard", dismissesKeyboard: true, opensQuickFill: false)
        ]
        utilityItems.forEach { item in
            let button = UIButton(type: .system)
            configureUtilityIconButton(
                button,
                asset: item.asset,
                fallbackSystemName: item.fallbackSystemName,
                accessibilityLabel: item.label
            )
            if item.opensQuickFill {
                button.addAction(UIAction { [weak self] _ in
                    self?.handleUtilityFillButtonTap()
                }, for: .touchUpInside)
            } else if item.dismissesKeyboard {
                button.addAction(UIAction { [weak self] _ in
                    self?.dismissKeyboard()
                }, for: .touchUpInside)
            } else {
                button.isUserInteractionEnabled = false
            }
            utilityOverlayStack.addArrangedSubview(button)
            utilityOverlayIconButtons.append(button)
        }

        setupCandidatePage()

        NSLayoutConstraint.activate([
            utilityOverlayView.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            utilityOverlayView.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            utilityOverlayView.topAnchor.constraint(equalTo: candidateBarStack.topAnchor),
            utilityOverlayView.bottomAnchor.constraint(equalTo: candidateBarStack.bottomAnchor),
            utilityOverlayStack.leadingAnchor.constraint(equalTo: utilityOverlayView.leadingAnchor, constant: 14),
            utilityOverlayStack.trailingAnchor.constraint(equalTo: utilityOverlayView.trailingAnchor, constant: -14),
            utilityOverlayStack.topAnchor.constraint(equalTo: utilityOverlayView.topAnchor),
            utilityOverlayStack.heightAnchor.constraint(equalToConstant: 32)
        ])
        view.bringSubviewToFront(candidatePageView)
        view.bringSubviewToFront(trackpadBlurView)
        view.bringSubviewToFront(keyPreviewView)
    }

    private func setupCandidatePage() {
        candidatePageView.translatesAutoresizingMaskIntoConstraints = false
        candidatePageView.isHidden = true
        candidatePageView.layer.cornerRadius = 0
        candidatePageView.layer.masksToBounds = true
        view.addSubview(candidatePageView)

        candidatePageCollapseButton.translatesAutoresizingMaskIntoConstraints = false
        configureCandidateToggleButton(candidatePageCollapseButton, asset: .arrowUp, fallbackSystemName: "chevron.up")
        candidatePageCollapseButton.addAction(UIAction { [weak self] _ in
            if self?.isQuickFillPanelVisible == true {
                self?.setQuickFillPanelVisible(false)
            } else {
                self?.setCandidatePageVisible(false)
            }
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

        candidatePageTopToCandidateBarConstraint = candidatePageView.topAnchor.constraint(equalTo: candidateBarStack.topAnchor)
        candidatePageTopToViewConstraint = candidatePageView.topAnchor.constraint(equalTo: view.topAnchor)
        candidatePageCollapseButtonLeadingConstraint = candidatePageCollapseButton.leadingAnchor.constraint(equalTo: candidatePageView.leadingAnchor, constant: 8)
        candidatePageCollapseButtonTrailingConstraint = candidatePageCollapseButton.trailingAnchor.constraint(equalTo: candidatePageView.trailingAnchor, constant: -8)
        candidatePageScrollTopToCollapseConstraint = candidatePageScrollView.topAnchor.constraint(equalTo: candidatePageCollapseButton.bottomAnchor, constant: 4)
        candidatePageScrollTopToPageConstraint = candidatePageScrollView.topAnchor.constraint(equalTo: candidatePageView.topAnchor)

        NSLayoutConstraint.activate([
            candidatePageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidatePageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidatePageTopToCandidateBarConstraint!,
            candidatePageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            candidatePageCollapseButton.topAnchor.constraint(equalTo: candidatePageView.topAnchor, constant: 4),
            candidatePageCollapseButton.heightAnchor.constraint(equalToConstant: Self.candidateToggleButtonHeight),
            candidatePageCollapseButton.widthAnchor.constraint(equalToConstant: Self.candidateToggleButtonWidth),
            candidatePageCollapseButtonTrailingConstraint!,

            candidatePageScrollView.leadingAnchor.constraint(equalTo: candidatePageView.leadingAnchor, constant: 6),
            candidatePageScrollView.trailingAnchor.constraint(equalTo: candidatePageView.trailingAnchor, constant: -6),
            candidatePageScrollTopToCollapseConstraint!,
            candidatePageScrollView.bottomAnchor.constraint(equalTo: candidatePageView.bottomAnchor, constant: -6),

            candidatePageStack.leadingAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.leadingAnchor),
            candidatePageStack.trailingAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.trailingAnchor),
            candidatePageStack.topAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.topAnchor),
            candidatePageStack.bottomAnchor.constraint(equalTo: candidatePageScrollView.contentLayoutGuide.bottomAnchor),
            candidatePageStack.widthAnchor.constraint(equalTo: candidatePageScrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func configureCandidateToggleButton(_ button: UIButton, asset: KeyboardIconAsset, fallbackSystemName: String) {
        button.setImage(keyboardIcon(asset, fallbackSystemName: fallbackSystemName), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 0.5
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
    }

    private func configureQuickFillBackButton(_ button: UIButton) {
        button.setImage(keyboardIcon(.back, fallbackSystemName: "chevron.left", pointSize: Self.quickFillBackIconPointSize), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 0
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.tintColor = primaryText
        button.backgroundColor = .clear
        button.layer.borderColor = UIColor.clear.cgColor
    }

    private func applyQuickFillPanelChrome(_ visible: Bool) {
        candidatePageTopToCandidateBarConstraint?.isActive = false
        candidatePageTopToViewConstraint?.isActive = false
        candidatePageCollapseButtonLeadingConstraint?.isActive = false
        candidatePageCollapseButtonTrailingConstraint?.isActive = false
        candidatePageScrollTopToCollapseConstraint?.isActive = false
        candidatePageScrollTopToPageConstraint?.isActive = false
        candidatePageTopToCandidateBarConstraint?.isActive = !visible
        candidatePageTopToViewConstraint?.isActive = visible
        candidatePageCollapseButtonLeadingConstraint?.isActive = visible
        candidatePageCollapseButtonTrailingConstraint?.isActive = !visible
        candidatePageScrollTopToCollapseConstraint?.isActive = !visible
        candidatePageScrollTopToPageConstraint?.isActive = visible
        candidatePageScrollView.showsVerticalScrollIndicator = !visible

        if visible {
            configureQuickFillBackButton(candidatePageCollapseButton)
        } else {
            configureCandidateToggleButton(candidatePageCollapseButton, asset: .arrowUp, fallbackSystemName: "chevron.up")
            candidatePageCollapseButton.tintColor = secondaryText
            candidatePageCollapseButton.backgroundColor = .clear
            candidatePageCollapseButton.layer.borderColor = UIColor.clear.cgColor
        }
    }

    private func configureUtilityIconButton(
        _ button: UIButton,
        asset: KeyboardIconAsset,
        fallbackSystemName: String,
        accessibilityLabel: String
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.layer.borderWidth = 0
        button.layer.shadowOpacity = 0
        button.contentEdgeInsets = .zero
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .top
        button.accessibilityLabel = accessibilityLabel
        button.setTitle(nil, for: .normal)
        button.setImage(keyboardIcon(asset, fallbackSystemName: fallbackSystemName), for: .normal)
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    private func keyboardIcon(
        _ asset: KeyboardIconAsset,
        fallbackSystemName: String,
        pointSize: CGFloat = KeyboardViewController.keyboardIconPointSize
    ) -> UIImage? {
        if let url = Bundle(for: Self.self).url(forResource: asset.fileName, withExtension: "png", subdirectory: "ios-icon"),
           let image = UIImage(contentsOfFile: url.path) {
            return resizedTemplateImage(image, pointSize: pointSize)
        }
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return UIImage(systemName: fallbackSystemName, withConfiguration: configuration)
    }

    private func keyboardKeyIcon(
        _ asset: KeyboardKeyIconAsset,
        fallbackSystemName: String,
        fallbackWeight: UIImage.SymbolWeight,
        pointSize: CGFloat = KeyboardViewController.keyboardIconPointSize,
        renderingMode: UIImage.RenderingMode = .alwaysTemplate,
        aspectFill: Bool = false,
        verticalAlignment: CGFloat = 0.5
    ) -> UIImage? {
        if let url = Bundle(for: Self.self).url(forResource: asset.fileName, withExtension: "png", subdirectory: "ios-icon"),
           let image = UIImage(contentsOfFile: url.path) {
            return resizedKeyboardImage(
                image,
                pointSize: pointSize,
                renderingMode: renderingMode,
                aspectFill: aspectFill,
                verticalAlignment: verticalAlignment
            )
        }
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: fallbackWeight)
        return UIImage(systemName: fallbackSystemName, withConfiguration: configuration)
    }

    private func resizedTemplateImage(_ image: UIImage, pointSize: CGFloat) -> UIImage {
        resizedKeyboardImage(image, pointSize: pointSize, renderingMode: .alwaysTemplate)
    }

    private func resizedKeyboardImage(
        _ image: UIImage,
        pointSize: CGFloat,
        renderingMode: UIImage.RenderingMode,
        aspectFill: Bool = false,
        verticalAlignment: CGFloat = 0.5
    ) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let drawRect: CGRect
            if aspectFill {
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let maxOffsetY = max(0, scaledSize.height - size.height)
                let clampedVerticalAlignment = min(max(verticalAlignment, 0), 1)
                drawRect = CGRect(
                    x: (size.width - scaledSize.width) / 2,
                    y: -maxOffsetY * clampedVerticalAlignment,
                    width: scaledSize.width,
                    height: scaledSize.height
                )
            } else {
                drawRect = CGRect(origin: .zero, size: size)
            }
            image.draw(in: drawRect)
        }
        return resized.withRenderingMode(renderingMode)
    }

    private func renderKeyboard() {
        hideKeyPreview(animated: false)
        setCandidatePageVisible(false, animated: false)
        edgeProxyButtons.forEach { $0.removeFromSuperview() }
        edgeProxyButtons.removeAll()
        keyButtons.removeAll()
        proxySpacerButtons.removeAll()
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

        for (rowIndex, row) in rows.enumerated() {
            let usesUniformLetterKeys = keyboardMode == .letters && row.contains { $0.kind.isPrimary }
            let alignsControlRow = row.contains { key in
                if case .space = key.kind {
                    return true
                }
                return false
            }
            let usesSquareEdgeControlRow = !alignsControlRow && row.contains { key in
                isThirdRowEdgeControlKey(key.kind)
            }
            let rowStack = KeyboardRowStack()
            rowStack.touchTargetOutset = Self.keyTouchOutset
            rowStack.axis = .horizontal
            rowStack.spacing = 6
            rowStack.alignment = .fill
            rowStack.distribution = usesUniformLetterKeys || alignsControlRow || usesSquareEdgeControlRow ? .fill : .fillProportionally
            var rowSpacers: [UIView] = []
            var squareEdgeRowFlexibleButtons: [KeyboardKeyButton] = []
            var modeSwitchButton: KeyboardKeyButton?
            var spaceButton: KeyboardKeyButton?
            var languageButton: KeyboardKeyButton?
            var returnButton: KeyboardKeyButton?
            var previewSourceButtonsByCharacter: [String: KeyboardKeyButton] = [:]
            var pendingProxyPreviewSpacers: [(button: KeyboardProxySpacerButton, proxyKind: KeyKind)] = []

            for key in row {
                if case .spacer = key.kind {
                    let spacer: UIView
                    if let proxyKind = key.proxyKind {
                        let proxySpacer = KeyboardProxySpacerButton(type: .custom)
                        proxySpacer.widthUnit = key.widthUnit
                        proxySpacer.accessibilityLabel = title(for: KeySpec(proxyKind))
                        if let previewKey = previewLookupKey(for: proxyKind),
                           let previewSourceView = previewSourceButtonsByCharacter[previewKey] {
                            proxySpacer.previewSourceView = previewSourceView
                            proxySpacer.forwardedKeyButton = previewSourceView
                        } else {
                            pendingProxyPreviewSpacers.append((proxySpacer, proxyKind))
                        }
                        proxySpacer.addAction(UIAction { [weak self] _ in
                            self?.handle(proxyKind)
                        }, for: .touchUpInside)
                        if shouldPreviewKey(proxyKind) {
                            bindKeyPreviewEvents(
                                to: proxySpacer,
                                previewText: title(for: KeySpec(proxyKind)),
                                sourceViewProvider: { [weak proxySpacer] in
                                    proxySpacer?.previewSourceView ?? proxySpacer?.forwardedKeyButton
                                },
                                highlightedControlProvider: { [weak proxySpacer] in
                                    proxySpacer?.forwardedKeyButton
                                },
                                minimumVisibleDuration: Self.proxySpacerPreviewMinimumVisibleDuration
                            )
                        }
                        proxySpacerButtons.append(proxySpacer)
                        spacer = proxySpacer
                    } else {
                        let plainSpacer = KeyboardKeySpacer()
                        plainSpacer.widthUnit = key.widthUnit
                        spacer = plainSpacer
                    }
                    rowStack.addArrangedSubview(spacer)
                    spacer.heightAnchor.constraint(equalToConstant: 42).isActive = true
                    rowSpacers.append(spacer)
                    continue
                }

                let button = makeButton(for: key)
                button.widthUnit = key.widthUnit
                if let previewKey = previewLookupKey(for: key.kind) {
                    previewSourceButtonsByCharacter[previewKey] = button
                    for pending in pendingProxyPreviewSpacers where previewLookupKey(for: pending.proxyKind) == previewKey {
                        pending.button.previewSourceView = button
                        pending.button.forwardedKeyButton = button
                    }
                }
                rowStack.addArrangedSubview(button)
                button.heightAnchor.constraint(equalToConstant: 42).isActive = true
                if usesSquareEdgeControlRow {
                    if isThirdRowEdgeControlKey(key.kind) {
                        button.widthAnchor.constraint(equalToConstant: 42).isActive = true
                    } else if !usesUniformLetterKeys, key.kind.isPrimary {
                        squareEdgeRowFlexibleButtons.append(button)
                    }
                }
                if usesUniformLetterKeys, usesLetterKeyWidth(for: key.kind) {
                    button.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 0.1, constant: -5.4).isActive = true
                }
                if alignsControlRow {
                    switch key.kind {
                    case .modeSwitch(_):
                        modeSwitchButton = button
                    case .space:
                        spaceButton = button
                    case .languageSwitch:
                        languageButton = button
                    case .returnKey:
                        returnButton = button
                    default:
                        break
                    }
                }
                keyButtons.append(button)
            }

            if rowSpacers.count == 2 {
                rowSpacers[0].widthAnchor.constraint(equalTo: rowSpacers[1].widthAnchor).isActive = true
            }
            if squareEdgeRowFlexibleButtons.count > 1 {
                for button in squareEdgeRowFlexibleButtons.dropFirst() {
                    button.widthAnchor.constraint(equalTo: squareEdgeRowFlexibleButtons[0].widthAnchor).isActive = true
                }
            }
            if alignsControlRow,
               let modeSwitchButton = modeSwitchButton,
               let spaceButton = spaceButton,
               let languageButton = languageButton,
               let returnButton = returnButton {
                applyControlRowAlignment(
                    rowStack: rowStack,
                    modeSwitchButton: modeSwitchButton,
                    spaceButton: spaceButton,
                    languageButton: languageButton,
                    returnButton: returnButton
                )
            }

            keyboardRowsStack.addArrangedSubview(rowStack)
            if keyboardMode == .letters, rowIndex == 0 {
                installTopRowEdgeProxyButtons(rowStack: rowStack, previewSourceButtonsByCharacter: previewSourceButtonsByCharacter)
            }
        }

        updateCandidates()
        applyTheme()
    }

    private func installTopRowEdgeProxyButtons(
        rowStack: KeyboardRowStack,
        previewSourceButtonsByCharacter: [String: KeyboardKeyButton]
    ) {
        guard let qButton = previewSourceButtonsByCharacter["q"],
              let pButton = previewSourceButtonsByCharacter["p"] else { return }

        let leftButton = makeEdgeProxyButton(for: .character("q"), previewSourceView: qButton)
        let rightButton = makeEdgeProxyButton(for: .character("p"), previewSourceView: pButton)

        view.addSubview(leftButton)
        view.addSubview(rightButton)
        NSLayoutConstraint.activate([
            leftButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftButton.trailingAnchor.constraint(equalTo: qButton.centerXAnchor),
            leftButton.topAnchor.constraint(equalTo: rowStack.topAnchor),
            leftButton.bottomAnchor.constraint(equalTo: rowStack.bottomAnchor),
            rightButton.leadingAnchor.constraint(equalTo: pButton.centerXAnchor),
            rightButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightButton.topAnchor.constraint(equalTo: rowStack.topAnchor),
            rightButton.bottomAnchor.constraint(equalTo: rowStack.bottomAnchor)
        ])

        edgeProxyButtons = [leftButton, rightButton]
        proxySpacerButtons.append(contentsOf: edgeProxyButtons)
        view.bringSubviewToFront(candidatePageView)
        view.bringSubviewToFront(trackpadBlurView)
        view.bringSubviewToFront(keyPreviewView)
    }

    private func makeEdgeProxyButton(for proxyKind: KeyKind, previewSourceView: KeyboardKeyButton) -> KeyboardProxySpacerButton {
        let button = KeyboardProxySpacerButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = title(for: KeySpec(proxyKind))
        button.previewSourceView = previewSourceView
        button.forwardedKeyButton = previewSourceView
        button.addAction(UIAction { [weak self] _ in
            self?.handle(proxyKind)
        }, for: .touchUpInside)
        if shouldPreviewKey(proxyKind) {
            bindKeyPreviewEvents(
                to: button,
                previewText: title(for: KeySpec(proxyKind)),
                sourceViewProvider: { [weak button] in
                    button?.previewSourceView ?? button?.forwardedKeyButton
                },
                highlightedControlProvider: { [weak button] in
                    button?.forwardedKeyButton
                },
                minimumVisibleDuration: Self.proxySpacerPreviewMinimumVisibleDuration
            )
        }
        return button
    }

    private func applyControlRowAlignment(
        rowStack: UIStackView,
        modeSwitchButton: KeyboardKeyButton,
        spaceButton: KeyboardKeyButton,
        languageButton: KeyboardKeyButton,
        returnButton: KeyboardKeyButton
    ) {
        let rowSpacing = rowStack.spacing
        NSLayoutConstraint.activate([
            modeSwitchButton.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 0.25, constant: -4.5),
            spaceButton.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 0.4, constant: 8.4 - (2 * rowSpacing)),
            languageButton.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 0.12, constant: -1.8),
            returnButton.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 0.23, constant: -8.1)
        ])
    }

    private func usesLetterKeyWidth(for kind: KeyKind) -> Bool {
        switch kind {
        case .character(_):
            return true
        default:
            return false
        }
    }

    private func isThirdRowEdgeControlKey(_ kind: KeyKind) -> Bool {
        switch kind {
        case .modeSwitch(.numbers), .modeSwitch(.symbols), .shift, .backspace:
            return true
        default:
            return false
        }
    }

    private var letterRows: [[KeySpec]] {
        let row1 = "qwertyuiop".map { KeySpec(.character(String($0))) }
        let row2 = [KeySpec(.spacer, widthUnit: 0.5, proxyKind: .character("a"))] + "asdfghjkl".map { KeySpec(.character(String($0))) } + [KeySpec(.spacer, widthUnit: 0.5, proxyKind: .character("l"))]
        let row3 = [KeySpec(.shift), KeySpec(.spacer, widthUnit: 0.5)] + "zxcvbnm".map { KeySpec(.character(String($0))) } + [KeySpec(.spacer, widthUnit: 0.5), KeySpec(.backspace)]
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
            punctuationKeys(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]),
            [KeySpec(.modeSwitch(.symbols), title: "#+=")] + punctuationKeys([".", ",", "?", "!", "'"]) + [KeySpec(.backspace)],
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
            punctuationKeys(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]),
            punctuationKeys(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"]),
            [KeySpec(.modeSwitch(.numbers), title: "123")] + punctuationKeys([".", ",", "?", "!", "'"]) + [KeySpec(.backspace)],
            [
                KeySpec(.modeSwitch(.letters), title: "ABC", widthUnit: 1.35),
                KeySpec(.space, title: "空格", widthUnit: 3.55),
                KeySpec(.languageSwitch, widthUnit: 1),
                KeySpec(.returnKey, widthUnit: 1.55)
            ]
        ]
    }

    private func punctuationKeys(_ values: [String]) -> [KeySpec] {
        values.map { KeySpec(.character(localizedPunctuation($0))) }
    }

    private func localizedPunctuation(_ value: String) -> String {
        guard inputLanguage == .chinese else { return value }

        switch value {
        case ":":
            return "："
        case ";":
            return "；"
        case "(":
            return "（"
        case ")":
            return "）"
        case "$":
            return "¥"
        case "\"":
            return "“"
        case ".":
            return "。"
        case ",":
            return "，"
        case "?":
            return "？"
        case "!":
            return "！"
        case "'":
            return "’"
        case "[":
            return "【"
        case "]":
            return "】"
        case "{":
            return "《"
        case "}":
            return "》"
        case "%":
            return "％"
        case "\\":
            return "、"
        case "|":
            return "｜"
        case "~":
            return "～"
        case "<":
            return "〈"
        case ">":
            return "〉"
        default:
            return value
        }
    }

    private func makeButton(for spec: KeySpec) -> KeyboardKeyButton {
        let button = KeyboardKeyButton(type: .system)
        button.kind = spec.kind
        button.touchOutset = Self.keyTouchOutset
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
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.titleLabel?.baselineAdjustment = .alignCenters
        if case .shift = spec.kind {
            button.setImage(keyboardKeyIcon(.shift, fallbackSystemName: "shift", fallbackWeight: .light, pointSize: Self.shiftKeyImagePointSize, renderingMode: .alwaysOriginal, aspectFill: true, verticalAlignment: Self.shiftKeyImageVerticalAlignment), for: .normal)
            button.tintColor = primaryText
            button.accessibilityLabel = "Shift"
        } else if case .backspace = spec.kind {
            button.setImage(keyboardKeyIcon(.backspace, fallbackSystemName: "delete.left", fallbackWeight: .light), for: .normal)
            button.tintColor = primaryText
            button.accessibilityLabel = "删除"
        } else {
            button.setTitle(title(for: spec), for: .normal)
        }
        button.addAction(UIAction { [weak self] _ in
            self?.handle(spec.kind)
        }, for: .touchUpInside)
        if shouldPreviewKey(spec.kind) {
            bindKeyPreviewEvents(to: button, previewText: title(for: spec))
        }
        if case .space = spec.kind {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleKeyLongPress(_:)))
            recognizer.minimumPressDuration = 0.35
            recognizer.cancelsTouchesInView = false
            button.addGestureRecognizer(recognizer)
        }
        return button
    }

    private func shouldPreviewKey(_ kind: KeyKind) -> Bool {
        guard case .character(let value) = kind else { return false }
        guard value.unicodeScalars.count == 1 else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func previewLookupKey(for kind: KeyKind) -> String? {
        guard case .character(let value) = kind else { return nil }
        return value.lowercased()
    }

    private func bindKeyPreviewEvents(
        to control: UIControl,
        previewText: String,
        sourceViewProvider: (() -> UIView?)? = nil,
        highlightedControlProvider: (() -> UIControl?)? = nil,
        minimumVisibleDuration: TimeInterval = 0
    ) {
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let control = control else { return }
            highlightedControlProvider?()?.isHighlighted = true
            self?.showKeyPreview(from: sourceViewProvider?() ?? control, text: previewText)
        }, for: [.touchDown, .touchDragInside, .touchDragEnter])
        control.addAction(UIAction { [weak self] _ in
            highlightedControlProvider?()?.isHighlighted = false
            self?.hideKeyPreview(minimumVisibleDuration: minimumVisibleDuration)
        }, for: [.touchDragExit, .touchUpInside, .touchUpOutside, .touchCancel])
    }

    private func showKeyPreview(from sourceView: UIView, text previewText: String) {
        guard !previewText.isEmpty else {
            hideKeyPreview(animated: false)
            return
        }

        pendingKeyPreviewHideWorkItem?.cancel()
        pendingKeyPreviewHideWorkItem = nil
        keyPreviewShownAt = ProcessInfo.processInfo.systemUptime
        previewedKeySourceView = sourceView
        previewedKeyText = previewText
        keyPreviewView.configure(
            text: previewText,
            backgroundColor: keyPreviewBackground,
            textColor: primaryText,
            shadowColor: shadowColor
        )

        let buttonFrame = sourceView.convert(sourceView.bounds, to: view)
        let previewSize = keyPreviewView.preferredSize(forButtonWidth: buttonFrame.width)
        let minX = Self.keyPreviewHorizontalInset
        let maxX = max(minX, view.bounds.width - previewSize.width - Self.keyPreviewHorizontalInset)
        let centeredX = buttonFrame.midX - previewSize.width / 2
        let originX = min(max(centeredX, minX), maxX)
        let originY = max(0, buttonFrame.minY - previewSize.height + 3)
        let minTailCenterX: CGFloat = 14
        let maxTailCenterX = previewSize.width - minTailCenterX
        keyPreviewView.tailCenterX = min(max(buttonFrame.midX - originX, minTailCenterX), maxTailCenterX)

        keyPreviewView.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: previewSize)
        keyPreviewView.isHidden = false
        keyPreviewView.alpha = 1
        keyPreviewView.setNeedsLayout()
        keyPreviewView.setNeedsDisplay()
        view.bringSubviewToFront(keyPreviewView)
    }

    private func hideKeyPreview(animated: Bool = true, minimumVisibleDuration: TimeInterval = 0) {
        pendingKeyPreviewHideWorkItem?.cancel()
        pendingKeyPreviewHideWorkItem = nil

        if minimumVisibleDuration > 0,
           !keyPreviewView.isHidden {
            let remainingDuration = minimumVisibleDuration - (ProcessInfo.processInfo.systemUptime - keyPreviewShownAt)
            if remainingDuration > 0 {
                previewedKeySourceView = nil
                previewedKeyText = nil
                let workItem = DispatchWorkItem { [weak self] in
                    self?.pendingKeyPreviewHideWorkItem = nil
                    self?.hideKeyPreview(animated: animated)
                }
                pendingKeyPreviewHideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + remainingDuration, execute: workItem)
                return
            }
        }

        previewedKeySourceView = nil
        previewedKeyText = nil
        guard !keyPreviewView.isHidden else { return }

        let hide = {
            self.keyPreviewView.alpha = 0
        }
        let complete: (Bool) -> Void = { _ in
            if self.previewedKeySourceView == nil {
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
        case .character(let value):
            if shiftState == .off,
               value.unicodeScalars.count == 1,
               value.rangeOfCharacter(from: .lowercaseLetters) != nil {
                return .systemFont(ofSize: 26, weight: .light)
            }
            return .systemFont(ofSize: 23, weight: .regular)
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
        candidateRefreshGeneration += 1
        candidateRefreshWorkItem?.cancel()
        let generation = candidateRefreshGeneration

        guard keyboardMode == .letters, inputLanguage == .chinese else {
            applyCandidateRefreshResult([], mode: .composition, resetScroll: resetScroll)
            return
        }

        let pinyin = activeCandidatePinyin
        let queryMode: CandidateMode
        let associationQuery: String?
        if pinyin.isEmpty {
            if !hasActiveComposition, let associationContext {
                queryMode = .association
                associationQuery = associationContext
            } else {
                applyCandidateRefreshResult([], mode: .composition, resetScroll: resetScroll)
                return
            }
        } else {
            queryMode = .composition
            associationQuery = nil
        }

        isCandidateRefreshPending = true
        candidateMode = queryMode
        updateCandidateControlsEnabled()
        if isCandidatePageVisible {
            setCandidatePageVisible(false)
        }
        if resetScroll {
            candidateScrollView.setContentOffset(.zero, animated: false)
        }
        updateReturnKeyAppearance()

        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem { [weak self] in
            guard !workItem.isCancelled else { return }
            guard let self else { return }

            let candidates: [KeyboardCandidate]
            switch queryMode {
            case .composition:
                candidates = self.candidates(for: pinyin)
            case .association:
                candidates = self.associationProvider.associations(for: associationQuery ?? "").map { candidate in
                    KeyboardCandidate(text: candidate, consumeLength: 0)
                }
            }

            guard !workItem.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.candidateRefreshGeneration == generation,
                      !workItem.isCancelled else {
                    return
                }
                self.applyCandidateRefreshResult(candidates, mode: queryMode, resetScroll: resetScroll)
            }
        }
        candidateRefreshWorkItem = workItem
        candidateQueue.asyncAfter(deadline: .now() + Self.candidateRefreshDelay, execute: workItem)
    }

    private func applyCandidateRefreshResult(
        _ candidates: [KeyboardCandidate],
        mode: CandidateMode,
        resetScroll: Bool
    ) {
        isCandidateRefreshPending = false
        candidateMode = mode
        allCandidates = candidates
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

    private func updateCandidateControlsEnabled() {
        candidateExpandButton.isUserInteractionEnabled = !isCandidateRefreshPending
        candidateStack.arrangedSubviews.forEach { view in
            if let button = view as? UIButton {
                button.isUserInteractionEnabled = !isCandidateRefreshPending
            }
        }
    }

    private func renderVisibleCandidates() {
        candidateStack.arrangedSubviews.forEach { view in
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        utilityOverlayView.isHidden = hasActiveComposition || !allCandidates.isEmpty || isQuickFillPanelVisible
        updateCandidateExpandButtonVisibility()

        guard !allCandidates.isEmpty else {
            return
        }

        for (index, candidate) in allCandidates.prefix(visibleCandidateCount).enumerated() {
            let button = makeCandidateButton(candidate: candidate, index: index)
            button.isUserInteractionEnabled = !isCandidateRefreshPending
            candidateStack.addArrangedSubview(button)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
    }

    private func makeCandidateButton(candidate: KeyboardCandidate, index: Int, expanded: Bool = false) -> UIButton {
        let isHighlighted = index == highlightedCandidateIndex
        let button = UIButton(type: .system)
        button.setTitle(candidate.text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 19, weight: isHighlighted ? .semibold : .regular)
        button.titleLabel?.numberOfLines = expanded ? 0 : 1
        button.titleLabel?.lineBreakMode = expanded ? .byCharWrapping : .byTruncatingTail
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(primaryText, for: .normal)
        button.backgroundColor = .clear
        button.contentEdgeInsets = expanded ? UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12) : UIEdgeInsets(top: 2, left: 12, bottom: 2, right: 12)
        button.layer.cornerRadius = 0
        button.layer.borderWidth = 0
        button.layer.borderColor = UIColor.clear.cgColor
        button.layer.shadowColor = UIColor.clear.cgColor
        button.layer.shadowOpacity = 0
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = .zero
        button.addAction(UIAction { [weak self] _ in
            self?.handleCandidateSelection(candidate, index: index)
        }, for: .touchUpInside)
        return button
    }

    private func candidatePageButtonSize(for text: String, maxWidth: CGFloat) -> CGSize {
        let horizontalInset: CGFloat = 24
        let verticalInset: CGFloat = 12
        let minimumWidth: CGFloat = 56
        let minimumHeight: CGFloat = 34
        let font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        let unconstrainedSize = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).size
        let preferredWidth = ceil(unconstrainedSize.width) + horizontalInset
        let width = min(max(minimumWidth, preferredWidth), maxWidth)
        let textWidth = max(1, width - horizontalInset)
        let wrappedSize = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).size
        return CGSize(width: width, height: max(minimumHeight, ceil(wrappedSize.height) + verticalInset))
    }

    private func updateCandidateExpandButtonVisibility() {
        let canExpand = keyboardMode == .letters && inputLanguage == .chinese && !allCandidates.isEmpty
        candidateExpandButton.isHidden = !canExpand
        candidateExpandButton.isUserInteractionEnabled = !isCandidateRefreshPending
        if !canExpand {
            setCandidatePageVisible(false)
        }
    }

    private func setCandidatePageVisible(_ visible: Bool, animated: Bool = true) {
        let shouldShow = visible && keyboardMode == .letters && inputLanguage == .chinese && !allCandidates.isEmpty
        guard isCandidatePageVisible != shouldShow || candidatePageView.isHidden == shouldShow else { return }

        if shouldShow {
            setQuickFillPanelVisible(false, animated: false)
            applyQuickFillPanelChrome(false)
        }

        isCandidatePageVisible = shouldShow
        view.layoutIfNeeded()

        if shouldShow {
            hideKeyPreview(animated: false)
            candidatePageScrollView.setContentOffset(.zero, animated: false)
            renderCandidatePage()
            candidatePageView.backgroundColor = candidatePageBackground
            candidatePageView.isHidden = false
            candidatePageView.alpha = 1
            view.bringSubviewToFront(candidatePageView)
            view.bringSubviewToFront(trackpadBlurView)
            view.bringSubviewToFront(keyPreviewView)

            let candidatePageOffset = candidatePageDismissOffset
            let keyboardOffset = keyboardRowsDismissOffset
            let animations = {
                self.candidatePageView.transform = .identity
                self.keyboardRowsStack.transform = CGAffineTransform(translationX: 0, y: keyboardOffset)
            }

            if animated {
                candidatePageView.transform = CGAffineTransform(translationX: 0, y: candidatePageOffset)
                keyboardRowsStack.transform = .identity
                UIView.animate(
                    withDuration: Self.candidatePanelAnimationDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState],
                    animations: animations
                )
            } else {
                animations()
            }
        } else {
            let animations = {
                self.candidatePageView.transform = CGAffineTransform(translationX: 0, y: self.candidatePageDismissOffset)
                self.keyboardRowsStack.transform = .identity
            }
            let complete: (Bool) -> Void = { _ in
                guard !self.isCandidatePageVisible else { return }
                self.candidatePageView.isHidden = true
                self.candidatePageView.transform = .identity
                self.clearCandidatePage()
            }

            if animated && !candidatePageView.isHidden {
                UIView.animate(
                    withDuration: Self.candidatePanelAnimationDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState],
                    animations: animations,
                    completion: complete
                )
            } else {
                animations()
                complete(true)
            }
        }
    }

    private var candidatePageDismissOffset: CGFloat {
        max(candidatePageView.bounds.height, view.bounds.height - candidatePageView.frame.minY, 1) + 12
    }

    private var keyboardRowsDismissOffset: CGFloat {
        max(keyboardRowsStack.bounds.height, view.bounds.height - keyboardRowsStack.frame.minY, 1) + 12
    }

    private func renderCandidatePageIfNeeded() {
        guard isCandidatePageVisible else { return }
        renderCandidatePage()
    }

    private func renderCandidatePage() {
        clearCandidatePage()
        candidatePageRenderedWidth = candidatePageView.bounds.width
        candidatePageStack.spacing = 6
        guard !allCandidates.isEmpty else { return }

        let spacing: CGFloat = 6
        let minButtonWidth: CGFloat = 56
        let contentWidth = max(candidatePageView.bounds.width - 12, minButtonWidth)
        var rowStack: UIStackView?
        var rowWidth: CGFloat = 0

        for (index, candidate) in allCandidates.enumerated() {
            let size = candidatePageButtonSize(for: candidate.text, maxWidth: contentWidth)
            let needsNewRow = rowStack == nil || rowWidth + spacing + size.width > contentWidth

            if needsNewRow {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.spacing = spacing
                newRow.alignment = .top
                newRow.distribution = .fill
                candidatePageStack.addArrangedSubview(newRow)
                rowStack = newRow
                rowWidth = 0
            }

            let button = makeCandidateButton(candidate: candidate, index: index, expanded: true)
            rowStack?.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: size.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: size.height).isActive = true
            rowWidth += (rowWidth == 0 ? 0 : spacing) + size.width
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
            let isSpecial = (button as? KeyboardKeyButton)?.kind.isSpecialKey == true
            button.backgroundColor = isSpecial ? specialKeyBackground : keyBackground
            button.setTitleColor(primaryText, for: .normal)
            button.tintColor = primaryText
            button.layer.shadowColor = shadowColor.cgColor
        }
        for button in proxySpacerButtons {
            button.applyAppearance(backgroundColor: proxySpacerBackground, shadowColor: shadowColor, showsShadow: false)
        }
        for button in utilityOverlayIconButtons {
            button.setTitleColor(secondaryText, for: .normal)
            button.tintColor = secondaryText
            button.backgroundColor = .clear
            button.layer.borderColor = UIColor.clear.cgColor
        }
        candidateExpandButton.tintColor = secondaryText
        candidateExpandButton.backgroundColor = .clear
        candidateExpandButton.layer.borderColor = UIColor.clear.cgColor
        candidatePageCollapseButton.tintColor = secondaryText
        candidatePageCollapseButton.backgroundColor = .clear
        candidatePageCollapseButton.layer.borderColor = UIColor.clear.cgColor
        updateCompositionBarAppearance()
        renderCandidatePageIfNeeded()
        if let previewedKeySourceView = previewedKeySourceView,
           let previewedKeyText = previewedKeyText {
            showKeyPreview(from: previewedKeySourceView, text: previewedKeyText)
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
        candidatePageView.backgroundColor = isQuickFillPanelVisible ? quickFillPanelBackground : candidatePageBackground
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
        compositionBar.configure(
            textColor: primaryText,
            cursorColor: compositionCursorColor,
            mascotImage: UIImage(named: "\u{732B}")
        )
    }

    private var keyboardBackground: UIColor {
        isDark ? UIColor(red: 0.13, green: 0.14, blue: 0.14, alpha: 0.72) : UIColor(red: 0.73, green: 0.75, blue: 0.78, alpha: 0.72)
    }

    private var quickFillPanelBackground: UIColor {
        isDark ? UIColor(red: 0.13, green: 0.14, blue: 0.14, alpha: 1) : UIColor(red: 223 / 255, green: 224 / 255, blue: 228 / 255, alpha: 1)
    }

    private var candidatePageBackground: UIColor {
        quickFillPanelBackground
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

    private var proxySpacerBackground: UIColor {
        .clear
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

    private func clearCompositionFromBar() {
        associationContext = nil
        setCandidatePageVisible(false, animated: false)
        resetCompositionState()
        refreshCompositionDisplay()
        updateCandidates(resetScroll: true)
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
        let prefix = selectedCompositionText
        let current = segmentedPinyin(compositionBuffer)
        let text = prefix + current
        let rawOffsets = compositionDisplayRawOffsets(currentDisplayText: current)
        let rawCursor = selectedCompositionPinyin.count + compositionCursorOffset
        return (text, displayOffset(forRawOffset: rawCursor, rawOffsets: rawOffsets, displayTextCount: text.count), rawOffsets)
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

    private func compositionDisplayRawOffsets(currentDisplayText: String) -> [Int] {
        var offsets: [Int] = [0]
        var rawOffset = 0

        for segment in selectedCompositionSegments {
            let characters = Array(segment.text)
            guard !characters.isEmpty else {
                rawOffset += segment.pinyin.count
                continue
            }
            for index in characters.indices {
                if index == characters.index(before: characters.endIndex) {
                    offsets.append(rawOffset + segment.pinyin.count)
                } else {
                    offsets.append(rawOffset)
                }
            }
            rawOffset += segment.pinyin.count
        }

        for character in currentDisplayText {
            if character != "'" {
                rawOffset += 1
            }
            offsets.append(rawOffset)
        }

        return offsets
    }

    private func displayOffset(forRawOffset rawOffset: Int, rawOffsets: [Int], displayTextCount: Int) -> Int {
        if let exactOffset = rawOffsets.lastIndex(of: rawOffset) {
            return exactOffset
        }
        if let nextOffset = rawOffsets.firstIndex(where: { $0 > rawOffset }) {
            return nextOffset
        }
        return min(rawOffset, displayTextCount)
    }

    private func commitCompositionAsText() {
        finalizeComposition()
    }

    private func handleUtilityFillButtonTap() {
        hideKeyPreview(animated: false)
        reloadQuickFillItems()
        if isQuickFillPanelVisible {
            setQuickFillPanelVisible(false)
        } else {
            selectedQuickFillPanelTab = .commonPhrases
            setCandidatePageVisible(false)
            setQuickFillPanelVisible(true)
        }
    }

    private func reloadQuickFillItems() {
        let sharedDefaults = UserDefaults(suiteName: "group.com.local.fitnex")
        quickFillItems = sharedDefaults?.stringArray(forKey: "quickFill.items") ?? []
    }

    private func setQuickFillPanelVisible(_ visible: Bool, animated: Bool = true) {
        let shouldShow = visible
        guard isQuickFillPanelVisible != shouldShow else { return }
        isQuickFillPanelVisible = shouldShow

        if shouldShow {
            selectedQuickFillPanelTab = .commonPhrases
            applyQuickFillPanelChrome(true)
            renderQuickFillPanel()
            candidatePageView.backgroundColor = quickFillPanelBackground
            candidatePageView.isHidden = false
            candidatePageView.alpha = 1
            view.bringSubviewToFront(trackpadBlurView)
            view.bringSubviewToFront(keyPreviewView)
            view.bringSubviewToFront(candidatePageView)
            candidatePageCollapseButton.isHidden = false
            // Keep the back button above the full-height quick fill scroll view so it can receive taps.
            candidatePageView.bringSubviewToFront(candidatePageCollapseButton)

            let keyboardOffset = keyboardRowsDismissOffset
            let animations = {
                self.candidatePageView.transform = .identity
                self.keyboardRowsStack.transform = CGAffineTransform(translationX: 0, y: keyboardOffset)
            }
            if animated {
                candidatePageView.transform = CGAffineTransform(translationX: 0, y: candidatePageDismissOffset)
                keyboardRowsStack.transform = .identity
                UIView.animate(
                    withDuration: Self.candidatePanelAnimationDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState],
                    animations: animations
                )
            } else {
                animations()
            }
        } else {
            let animations = {
                self.candidatePageView.transform = CGAffineTransform(translationX: 0, y: self.candidatePageDismissOffset)
                self.keyboardRowsStack.transform = .identity
            }
            let complete: (Bool) -> Void = { _ in
                guard !self.isQuickFillPanelVisible else { return }
                self.candidatePageView.isHidden = true
                self.candidatePageView.transform = .identity
                self.clearCandidatePage()
                self.applyQuickFillPanelChrome(false)
            }
            if animated && !candidatePageView.isHidden {
                UIView.animate(
                    withDuration: Self.candidatePanelAnimationDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState],
                    animations: animations,
                    completion: complete
                )
            } else {
                animations()
                complete(true)
            }
        }
    }

    private func renderQuickFillPanel() {
        clearCandidatePage()
        candidatePageRenderedWidth = candidatePageView.bounds.width
        candidatePageStack.spacing = 8
        candidatePageScrollView.setContentOffset(.zero, animated: false)
        candidatePageCollapseButton.isHidden = false

        candidatePageStack.addArrangedSubview(makeQuickFillHeader())

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        contentStack.isLayoutMarginsRelativeArrangement = true
        candidatePageStack.addArrangedSubview(contentStack)

        switch selectedQuickFillPanelTab {
        case .commonPhrases:
            if quickFillItems.isEmpty {
                contentStack.addArrangedSubview(makeQuickFillEmptyStateView())
            } else {
                quickFillItems.forEach { text in
                    contentStack.addArrangedSubview(makeQuickFillButton(text: text))
                }
            }
        case .clipboard:
            contentStack.addArrangedSubview(makeQuickFillEmptyStateView())
        }

        candidatePageView.bringSubviewToFront(candidatePageCollapseButton)
    }

    private func makeQuickFillHeader() -> UIStackView {
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .fill
        header.distribution = .fill
        header.spacing = 14
        header.layoutMargins = UIEdgeInsets(top: 0, left: 44, bottom: 0, right: 12)
        header.isLayoutMarginsRelativeArrangement = true
        header.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let tabStack = UIStackView()
        tabStack.axis = .horizontal
        tabStack.alignment = .fill
        tabStack.distribution = .fillEqually
        tabStack.spacing = 22
        tabStack.addArrangedSubview(makeQuickFillTabControl(tab: .commonPhrases, title: "常用语"))
        tabStack.addArrangedSubview(makeQuickFillTabControl(tab: .clipboard, title: "粘贴板"))
        header.addArrangedSubview(tabStack)

        let trailingSpacer = UIView()
        trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(trailingSpacer)
        trailingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return header
    }

    private func makeQuickFillTabControl(tab: QuickFillPanelTab, title: String) -> UIStackView {
        let isSelected = selectedQuickFillPanelTab == tab
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2

        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: isSelected ? .semibold : .regular)
        button.setTitleColor(isSelected ? primaryText : secondaryText.withAlphaComponent(0.62), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        button.addAction(UIAction { [weak self] _ in
            guard let self, self.selectedQuickFillPanelTab != tab else { return }
            self.selectedQuickFillPanelTab = tab
            self.renderQuickFillPanel()
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)

        let indicator = UIView()
        indicator.backgroundColor = isSelected ? UIColor.systemBlue : .clear
        indicator.layer.cornerRadius = 1.5
        indicator.heightAnchor.constraint(equalToConstant: 3).isActive = true
        indicator.widthAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(indicator)
        return stack
    }

    private func makeQuickFillEmptyStateView() -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: max(140, min(176, candidatePageView.bounds.height - 104))).isActive = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        container.addSubview(stack)

        if let image = quickFillEmptyImage() {
            let imageView = UIImageView(image: image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            stack.addArrangedSubview(imageView)
            imageView.widthAnchor.constraint(equalToConstant: 112).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 112).isActive = true
        }

        let label = UILabel()
        label.text = "暂无数据"
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = secondaryText
        label.textAlignment = .center
        label.numberOfLines = 1
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12)
        ])
        return container
    }

    private func quickFillEmptyImage() -> UIImage? {
        if let url = Bundle(for: Self.self).url(forResource: "暂无数据", withExtension: "png", subdirectory: "ios-icon") {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(named: "暂无数据")
    }

    private func makeQuickFillButton(text: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.contentHorizontalAlignment = .left
        button.setTitleColor(primaryText, for: .normal)
        button.backgroundColor = candidateBackground
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 0.5
        button.layer.borderColor = candidateBorder.cgColor
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.handleQuickFillSelection(text)
        }, for: .touchUpInside)
        return button
    }

    private func handleQuickFillSelection(_ text: String) {
        textDocumentProxy.insertText(text)
        hasInsertedTextInCurrentContext = true
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
    let proxyKind: KeyKind?

    init(_ kind: KeyKind, title: String? = nil, widthUnit: CGFloat = 1, proxyKind: KeyKind? = nil) {
        self.kind = kind
        self.title = title
        self.widthUnit = widthUnit
        self.proxyKind = proxyKind
    }
}

private final class KeyboardKeyButton: UIButton {
    var kind: KeyKind = .character("")
    var widthUnit: CGFloat = 1
    var touchOutset: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        CGSize(width: 32 * widthUnit, height: 42)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard touchOutset > 0 else {
            return super.point(inside: point, with: event)
        }
        return bounds.insetBy(dx: -touchOutset, dy: -touchOutset).contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let contentRect = bounds.inset(by: contentEdgeInsets)
        let horizontalPadding: CGFloat = 4
        let availableWidth = max(0, contentRect.width - horizontalPadding * 2)

        if let titleLabel,
           let title = titleLabel.text,
           !title.isEmpty {
            let titleHeight = ceil(titleLabel.font.lineHeight)
            let horizontalOffset = titleHorizontalOffset(for: title)
            let verticalOffset = lowercaseTitleVerticalOffset(for: title)
            titleLabel.frame = CGRect(
                x: contentRect.minX + horizontalPadding + horizontalOffset,
                y: contentRect.midY - titleHeight / 2 + verticalOffset,
                width: availableWidth,
                height: titleHeight
            )
            titleLabel.textAlignment = .center
        }

        if let imageView,
           imageView.image != nil {
            imageView.sizeToFit()
            imageView.center = CGPoint(x: contentRect.midX, y: contentRect.midY)
        }
    }

    private func titleHorizontalOffset(for title: String) -> CGFloat {
        guard case .character(let value) = kind,
              value == title else {
            return 0
        }

        switch value {
        case "。", "，", "？", "！":
            return 4
        case "：", "；":
            return 3
        default:
            return 0
        }
    }

    private func lowercaseTitleVerticalOffset(for title: String) -> CGFloat {
        guard case .character(let value) = kind,
              value == title,
              value.unicodeScalars.count == 1,
              value.rangeOfCharacter(from: .lowercaseLetters) != nil else {
            return 0
        }
        return -1
    }
}

private final class KeyboardRootStack: UIStackView {
    var touchTargetOutset: CGFloat = 0

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || nearestKeyboardRow(at: point) != nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha >= 0.01, isUserInteractionEnabled, self.point(inside: point, with: event) else {
            return nil
        }

        let hitView = super.hitTest(point, with: event)
        if let hitView, hitView !== self {
            return hitView
        }

        guard let row = nearestKeyboardRow(at: point) else { return nil }
        return row.hitTest(convert(point, to: row), with: event)
    }

    private func nearestKeyboardRow(at point: CGPoint) -> KeyboardRowStack? {
        collectKeyboardRows(from: self)
            .compactMap { row -> (row: KeyboardRowStack, frame: CGRect)? in
                guard !row.isHidden,
                      row.alpha >= 0.01,
                      row.isUserInteractionEnabled else {
                    return nil
                }

                let frame = convert(row.bounds, from: row)
                guard frame.insetBy(dx: -touchTargetOutset, dy: -touchTargetOutset).contains(point) else {
                    return nil
                }
                return (row, frame)
            }
            .min { left, right in
                squaredDistance(from: point, to: left.frame) < squaredDistance(from: point, to: right.frame)
            }?
            .row
    }

    private func collectKeyboardRows(from view: UIView) -> [KeyboardRowStack] {
        var rows: [KeyboardRowStack] = []
        for subview in view.subviews {
            if let row = subview as? KeyboardRowStack {
                rows.append(row)
            }
            rows.append(contentsOf: collectKeyboardRows(from: subview))
        }
        return rows
    }

    private func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }
}

private final class KeyboardRowStack: UIStackView {
    var touchTargetOutset: CGFloat = 0

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || nearestTouchTarget(at: point) != nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha >= 0.01, isUserInteractionEnabled, self.point(inside: point, with: event) else {
            return nil
        }

        let hitView = super.hitTest(point, with: event)
        if let hitView, hitView !== self {
            return hitView
        }

        return nearestTouchTarget(at: point)
    }

    private func nearestTouchTarget(at point: CGPoint) -> UIControl? {
        let targets = arrangedSubviews.compactMap { view -> UIControl? in
            guard let control = view as? UIControl,
                  !control.isHidden,
                  control.alpha >= 0.01,
                  control.isEnabled,
                  control.isUserInteractionEnabled else {
                return nil
            }
            return control
        }

        return targets
            .filter { $0.frame.insetBy(dx: -touchTargetOutset, dy: -touchTargetOutset).contains(point) }
            .min { left, right in
                squaredDistance(from: point, to: left.frame) < squaredDistance(from: point, to: right.frame)
            }
    }

    private func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }
}

private final class KeyPreviewView: UIView {
    private let label = UILabel()
    private var fillColor = UIColor.white
    private var tailHeight: CGFloat { 12 }
    var tailCenterX: CGFloat = 26 {
        didSet {
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

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
        CGSize(width: 52, height: 84)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bubbleRect = bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: tailHeight, right: 0))
        label.frame = bubbleRect.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: -5)
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
        let tailX = min(max(tailCenterX, tailWidth / 2), rect.width - tailWidth / 2)
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: tailX - tailWidth / 2, y: bubbleRect.maxY - 1))
        tail.addLine(to: CGPoint(x: tailX, y: rect.maxY))
        tail.addLine(to: CGPoint(x: tailX + tailWidth / 2, y: bubbleRect.maxY - 1))
        tail.close()
        path.append(tail)
        return path
    }
}

private final class KeyboardKeySpacer: UIView {
    var widthUnit: CGFloat = 1

    override var intrinsicContentSize: CGSize {
        CGSize(width: 32 * widthUnit, height: 42)
    }
}

private final class KeyboardProxySpacerButton: UIButton {
    var widthUnit: CGFloat = 1
    weak var previewSourceView: UIView?
    weak var forwardedKeyButton: KeyboardKeyButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.cornerRadius = 6
        layer.shadowOpacity = 0
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 32 * widthUnit, height: 42)
    }

    func applyAppearance(backgroundColor: UIColor, shadowColor: UIColor, showsShadow: Bool = true) {
        self.backgroundColor = backgroundColor
        layer.shadowColor = shadowColor.cgColor
        layer.shadowOpacity = showsShadow ? 0.22 : 0
    }
}

private final class CompositionBarView: UIView, UIGestureRecognizerDelegate {
    var onOffsetSelected: ((Int) -> Void)?
    var onClearRequested: (() -> Void)?

    private var text = ""
    private var cursorOffset = 0
    private var rawOffsets: [Int] = [0]
    private let mascotControl = UIControl()
    private let mascotImageView = UIImageView()
    private let heartBurstView = HeartBurstView()
    // private let clearButton = UIButton(type: .system)
    private let font = UIFont.systemFont(ofSize: 15, weight: .regular)
    private let textInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    private let mascotImageSize = CGSize(width: 32, height: 38)
    private let mascotHitSize = CGSize(width: 56, height: 42)
    private let mascotImageSpacing: CGFloat = 8
    // private let clearButtonSize = CGSize(width: 18, height: 18)
    // private let clearButtonSpacing: CGFloat = 6
    private var barTextColor = UIColor.black
    private var barCursorColor = UIColor.systemBlue
    private var isMascotAnimating = false
    // private var clearButtonBackgroundColor = UIColor(white: 0.96, alpha: 1)
    // private var clearButtonBorderColor = UIColor(white: 0, alpha: 0.08)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false

        mascotControl.isHidden = true
        mascotControl.accessibilityLabel = "Cat"
        mascotControl.clipsToBounds = false
        mascotControl.addTarget(self, action: #selector(handleMascotTap), for: .touchUpInside)
        addSubview(mascotControl)

        heartBurstView.isUserInteractionEnabled = false
        mascotControl.addSubview(heartBurstView)

        mascotImageView.contentMode = .scaleAspectFit
        mascotImageView.isUserInteractionEnabled = false
        mascotControl.addSubview(mascotImageView)

        // Clear button is intentionally disabled for now.
        // let deleteImage = UIImage(
        //     systemName: "xmark.circle",
        //     withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        // )
        // clearButton.setImage(deleteImage, for: .normal)
        // clearButton.contentHorizontalAlignment = .center
        // clearButton.contentVerticalAlignment = .center
        // clearButton.tintColor = barTextColor
        // clearButton.backgroundColor = clearButtonBackgroundColor
        // clearButton.layer.cornerRadius = clearButtonSize.height / 2
        // clearButton.layer.borderWidth = 0.5
        // clearButton.layer.borderColor = clearButtonBorderColor.cgColor
        // clearButton.clipsToBounds = true
        // clearButton.isHidden = true
        // clearButton.accessibilityLabel = "Delete pinyin"
        // clearButton.addAction(UIAction { [weak self] _ in
        //     self?.onClearRequested?()
        // }, for: .touchUpInside)
        // addSubview(clearButton)

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        textColor: UIColor,
        cursorColor: UIColor,
        mascotImage: UIImage?
    ) {
        barTextColor = textColor
        barCursorColor = cursorColor
        mascotImageView.image = mascotImage
        mascotControl.isHidden = mascotImage == nil
        mascotControl.isAccessibilityElement = mascotImage != nil
        // clearButton.tintColor = textColor
        // clearButton.backgroundColor = clearButtonBackgroundColor
        // clearButton.layer.borderColor = clearButtonBorderColor.cgColor
        setNeedsLayout()
        setNeedsDisplay()
    }

    func update(text: String, cursorOffset: Int, rawOffsets: [Int]? = nil) {
        self.text = text
        self.cursorOffset = max(0, min(text.count, cursorOffset))
        self.rawOffsets = rawOffsets ?? Array(0...text.count)
        // clearButton.isHidden = text.isEmpty
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mascotControl.frame = CGRect(
            x: bounds.maxX - textInsets.right - mascotHitSize.width,
            y: bounds.midY - mascotHitSize.height / 2,
            width: mascotHitSize.width,
            height: mascotHitSize.height
        )
        mascotImageView.frame = CGRect(
            x: mascotControl.bounds.maxX - mascotImageSize.width,
            y: mascotControl.bounds.midY - mascotImageSize.height / 2,
            width: mascotImageSize.width,
            height: mascotImageSize.height
        )
        heartBurstView.frame = mascotControl.bounds
    }

    override func draw(_ rect: CGRect) {
        guard !text.isEmpty else { return }

        let textRect = textDrawingRect
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: barTextColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textOrigin = CGPoint(x: textRect.minX, y: bounds.midY - textSize.height / 2)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(rect: textRect).addClip()
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)
        UIGraphicsGetCurrentContext()?.restoreGState()

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

        let textRect = textDrawingRect
        let point = recognizer.location(in: self)
        let x = max(0, min(point.x - textRect.minX, textRect.width))
        let displayOffset = nearestOffset(for: x)
        let safeOffset = max(0, min(displayOffset, rawOffsets.count - 1))
        onOffsetSelected?(rawOffsets[safeOffset])
    }

    @objc private func handleMascotTap() {
        guard !mascotControl.isHidden, !isMascotAnimating else { return }

        isMascotAnimating = true
        heartBurstView.play()
        mascotImageView.layer.removeAllAnimations()
        mascotImageView.transform = .identity

        UIView.animateKeyframes(
            withDuration: 0.68,
            delay: 0,
            options: [.calculationModeCubic],
            animations: {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.42) {
                    self.mascotImageView.transform = CGAffineTransform(translationX: -1, y: -5)
                        .rotated(by: -.pi / 52)
                        .scaledBy(x: 1.08, y: 1.08)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.56, relativeDuration: 0.44) {
                    self.mascotImageView.transform = .identity
                }
            },
            completion: { _ in
                self.mascotImageView.transform = .identity
                self.isMascotAnimating = false
            }
        )
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: self)
        if !mascotControl.isHidden, mascotControl.frame.contains(point) {
            return false
        }
        return true
    }

    private var textDrawingRect: CGRect {
        var rect = bounds.inset(by: textInsets)
        if !mascotControl.isHidden {
            rect.size.width = max(0, rect.width - mascotHitSize.width - mascotImageSpacing)
        }
        return rect
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

private final class HeartBurstView: UIView {
    private struct Particle {
        let x: CGFloat
        let y: CGFloat
        let rotation: CGFloat
        let delay: TimeInterval
        let scale: CGFloat
        let size: CGFloat
        let color: UIColor
    }

    private let particles: [Particle] = [
        Particle(x: -34, y: -32, rotation: 14, delay: 0, scale: 0.76, size: 13, color: UIColor(red: 1.00, green: 0.35, blue: 0.58, alpha: 1)),
        Particle(x: -22, y: -48, rotation: -8, delay: 0.03, scale: 0.88, size: 11, color: UIColor(red: 1.00, green: 0.48, blue: 0.66, alpha: 1)),
        Particle(x: -8, y: -58, rotation: 10, delay: 0.055, scale: 0.72, size: 9, color: UIColor(red: 1.00, green: 0.27, blue: 0.44, alpha: 1)),
        Particle(x: 8, y: -58, rotation: -12, delay: 0.075, scale: 0.80, size: 10, color: UIColor(red: 0.96, green: 0.25, blue: 0.52, alpha: 1)),
        Particle(x: 24, y: -46, rotation: 16, delay: 0.095, scale: 0.92, size: 12, color: UIColor(red: 1.00, green: 0.62, blue: 0.74, alpha: 1)),
        Particle(x: 36, y: -30, rotation: -10, delay: 0.12, scale: 0.78, size: 10, color: UIColor(red: 1.00, green: 0.35, blue: 0.58, alpha: 1)),
        Particle(x: -38, y: -14, rotation: -18, delay: 0.07, scale: 0.68, size: 8, color: UIColor(red: 1.00, green: 0.48, blue: 0.66, alpha: 1)),
        Particle(x: 40, y: -12, rotation: 20, delay: 0.14, scale: 0.70, size: 8, color: UIColor(red: 1.00, green: 0.27, blue: 0.44, alpha: 1)),
        Particle(x: -18, y: -26, rotation: 8, delay: 0.11, scale: 0.62, size: 7, color: UIColor(red: 0.96, green: 0.25, blue: 0.52, alpha: 1)),
        Particle(x: 18, y: -26, rotation: -8, delay: 0.155, scale: 0.66, size: 7, color: UIColor(red: 1.00, green: 0.62, blue: 0.74, alpha: 1)),
        Particle(x: -6, y: -42, rotation: 22, delay: 0.17, scale: 0.58, size: 8, color: UIColor(red: 1.00, green: 0.35, blue: 0.58, alpha: 1)),
        Particle(x: 6, y: -42, rotation: -22, delay: 0.195, scale: 0.58, size: 8, color: UIColor(red: 1.00, green: 0.48, blue: 0.66, alpha: 1))
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func play() {
        subviews.forEach { view in
            view.layer.removeAllAnimations()
            view.removeFromSuperview()
        }

        let origin = CGPoint(x: bounds.maxX - 16, y: bounds.midY + 1)
        particles.forEach { particle in
            let heart = HeartParticleView(color: particle.color)
            heart.bounds = CGRect(x: 0, y: 0, width: particle.size, height: particle.size)
            heart.center = origin
            heart.alpha = 0
            heart.transform = CGAffineTransform(rotationAngle: .pi / 4).scaledBy(x: 0.35, y: 0.35)
            addSubview(heart)

            UIView.animateKeyframes(
                withDuration: 0.76,
                delay: particle.delay,
                options: [.calculationModeCubic, .allowUserInteraction],
                animations: {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                        heart.alpha = 1
                        heart.transform = CGAffineTransform(rotationAngle: .pi / 4).scaledBy(x: 0.72, y: 0.72)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.16, relativeDuration: 0.84) {
                        heart.center = CGPoint(x: origin.x + particle.x, y: origin.y + particle.y)
                        heart.alpha = 0
                        heart.transform = CGAffineTransform(rotationAngle: .pi / 4 + particle.rotation * .pi / 180)
                            .scaledBy(x: particle.scale, y: particle.scale)
                    }
                },
                completion: { _ in
                    heart.removeFromSuperview()
                }
            )
        }
    }
}

private final class HeartParticleView: UIView {
    private let color: UIColor

    init(color: UIColor) {
        self.color = color
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.08),
            controlPoint1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.18),
            controlPoint2: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.24),
            controlPoint1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.12),
            controlPoint2: CGPoint(x: rect.midX - rect.width * 0.24, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.08),
            controlPoint1: CGPoint(x: rect.midX + rect.width * 0.24, y: rect.minY),
            controlPoint2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            controlPoint1: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.18),
            controlPoint2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.18)
        )
        path.close()

        color.setFill()
        path.fill()
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

    var isSpecialKey: Bool {
        switch self {
        case .shift, .backspace, .returnKey, .languageSwitch, .modeSwitch:
            return true
        default:
            return false
        }
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

private struct PinyinCorrection {
    let key: String
    let syllables: [String]
    let cost: Int
    let correctedSyllables: Int
}

private struct PinyinSegmenter {
    private struct InitialShorthandChunk {
        let key: String
        let isShorthand: Bool
    }

    private struct CorrectionPath {
        let key: String
        let syllables: [String]
        let cost: Int
        let correctedSyllables: Int
        let sortScore: Int
    }

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
        "h": ["hua", "huan", "han", "hao", "he", "hui", "huang", "hong", "huo", "hai", "hang", "heng", "hen", "ha", "hu"],
        "k": ["kan", "kao", "kai", "kuai", "ke", "kong", "kou", "ku", "kang", "ken", "keng", "ka", "kuan", "kuang", "kui", "kun", "kuo", "kua"],
        "s": ["shi", "shuo", "shang", "she", "shu", "shen", "sheng", "shou", "suo", "song", "si", "san", "sai", "su", "sa"],
        "x": ["xiang", "xin", "xing", "xian", "xiao", "xue", "xi", "xia", "xie", "xiu", "xu", "xuan", "xun", "xiong"]
    ]

    private static let orderedSyllables = syllables.sorted {
        if $0.count != $1.count {
            return $0.count < $1.count
        }
        return $0 < $1
    }
    private static let maxCorrectionCost = 2
    private static let maxCorrectedSyllables = 2
    private static let maxCorrectionInputLength = 18
    private static let maxCorrectionSpan = 7
    private static let maxCorrectionWidth = 24
    private static let keyboardNeighbors: [Character: String] = [
        "q": "wa", "w": "qase", "e": "wsdr", "r": "edft", "t": "rfgy", "y": "tghu", "u": "yhji", "i": "ujko", "o": "iklp", "p": "ol",
        "a": "qwsz", "s": "awedxz", "d": "serfcx", "f": "drtgvc", "g": "ftyhbv", "h": "gyujnb", "j": "huikmn", "k": "jiolm", "l": "kop",
        "z": "asx", "x": "zsdc", "c": "xdfv", "v": "cfgb", "b": "vghn", "n": "bhjm", "m": "njk"
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

    static func initialShorthandKeys(for key: String, limit: Int) -> [String] {
        guard limit > 0,
              let chunks = initialShorthandChunks(for: key),
              chunks.contains(where: \.isShorthand),
              chunks.contains(where: { !$0.isShorthand }) else {
            return []
        }

        let expansions = chunks.map { chunk in
            chunk.isShorthand ? completionSyllables(for: chunk.key) : [chunk.key]
        }
        guard expansions.allSatisfy({ !$0.isEmpty }) else { return [] }

        var results: [String] = []
        var seen: Set<String> = []

        func build(index: Int, key: String) {
            guard results.count < limit else { return }
            if index == expansions.count {
                guard key != "" && key != chunks.map(\.key).joined(separator: ""),
                      seen.insert(key).inserted else {
                    return
                }
                results.append(key)
                return
            }

            for syllable in expansions[index] {
                build(index: index + 1, key: key + syllable)
                if results.count >= limit {
                    break
                }
            }
        }

        build(index: 0, key: "")
        return results
    }

    static func acronymKeySequences(
        for key: String,
        syllablesPerLetterLimit: Int,
        sequenceLimit: Int
    ) -> [[String]] {
        guard key.count >= 2,
              key.count <= 6,
              syllablesPerLetterLimit > 0,
              sequenceLimit > 0,
              segment(key).joined(separator: "") != key else {
            return []
        }

        let letters = key.map { String($0) }
        guard letters.allSatisfy({ isInitialShorthand($0) }) else { return [] }

        let expansions = letters.map {
            Array(completionSyllables(for: $0).prefix(syllablesPerLetterLimit))
        }
        guard expansions.allSatisfy({ !$0.isEmpty }) else { return [] }

        var results: [[String]] = []

        func build(index: Int, sequence: [String]) {
            guard results.count < sequenceLimit else { return }
            if index == expansions.count {
                results.append(sequence)
                return
            }

            for syllable in expansions[index] {
                build(index: index + 1, sequence: sequence + [syllable])
                if results.count >= sequenceLimit {
                    break
                }
            }
        }

        build(index: 0, sequence: [])
        return results
    }

    static func correctionKeys(for key: String, limit: Int) -> [PinyinCorrection] {
        guard key.count >= 4, key.count <= maxCorrectionInputLength else { return [] }
        guard segment(key).joined(separator: "") != key else { return [] }

        let characters = Array(key)
        var paths = Array(repeating: [CorrectionPath](), count: characters.count + 1)
        paths[0] = [CorrectionPath(key: "", syllables: [], cost: 0, correctedSyllables: 0, sortScore: 0)]

        for start in 0..<characters.count {
            guard !paths[start].isEmpty else { continue }
            let maxEnd = min(characters.count, start + maxCorrectionSpan)

            for end in (start + 1)...maxEnd {
                let piece = String(characters[start..<end])
                let matches = correctionMatches(for: piece)
                guard !matches.isEmpty else { continue }

                for path in paths[start] {
                    for match in matches {
                        let correctedSyllables = path.correctedSyllables + (match.cost == 0 ? 0 : 1)
                        let cost = path.cost + match.cost
                        guard cost <= maxCorrectionCost,
                              correctedSyllables <= maxCorrectedSyllables else {
                            continue
                        }

                        paths[end].append(CorrectionPath(
                            key: path.key + match.syllable,
                            syllables: path.syllables + [match.syllable],
                            cost: cost,
                            correctedSyllables: correctedSyllables,
                            sortScore: path.sortScore + correctionSortRank(from: piece, to: match.syllable)
                        ))
                    }
                }

                paths[end] = pruneCorrectionPaths(paths[end])
            }
        }

        return pruneCorrectionPaths(paths[characters.count])
            .filter { $0.cost > 0 && $0.key != key }
            .prefix(limit)
            .map { path in
                PinyinCorrection(
                    key: path.key,
                    syllables: path.syllables,
                    cost: path.cost,
                    correctedSyllables: path.correctedSyllables
                )
            }
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

    private static func initialShorthandChunks(for key: String) -> [InitialShorthandChunk]? {
        guard key.count >= 4 else { return nil }

        let indices = Array(key.indices) + [key.endIndex]
        var index = 0
        var result: [InitialShorthandChunk] = []

        while index < key.count {
            var best: String?
            let maxEnd = min(key.count, index + 6)
            for end in stride(from: maxEnd, through: index + 1, by: -1) {
                let piece = String(key[indices[index]..<indices[end]])
                if syllables.contains(piece) {
                    best = piece
                    break
                }
            }

            if let best {
                result.append(InitialShorthandChunk(key: best, isShorthand: false))
                index += best.count
                continue
            }

            let piece = String(key[indices[index]..<indices[index + 1]])
            guard isInitialShorthand(piece) else { return nil }
            result.append(InitialShorthandChunk(key: piece, isShorthand: true))
            index += 1
        }

        return result
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

    private static func isInitialShorthand(_ key: String) -> Bool {
        key.count == 1 && !syllables.contains(key) && hasSyllable(withPrefix: key)
    }

    private static func correctionMatches(for piece: String) -> [(syllable: String, cost: Int)] {
        orderedSyllables.compactMap { syllable in
            correctionCost(from: piece, to: syllable).map { (syllable: syllable, cost: $0) }
        }
        .sorted {
            if $0.cost != $1.cost {
                return $0.cost < $1.cost
            }
            let firstPrefix = sharedPrefixLength($0.syllable, piece)
            let secondPrefix = sharedPrefixLength($1.syllable, piece)
            if firstPrefix != secondPrefix {
                return firstPrefix > secondPrefix
            }
            let firstRank = correctionSortRank(from: piece, to: $0.syllable)
            let secondRank = correctionSortRank(from: piece, to: $1.syllable)
            if firstRank != secondRank {
                return firstRank < secondRank
            }
            if $0.syllable.count != $1.syllable.count {
                return $0.syllable.count < $1.syllable.count
            }
            return $0.syllable < $1.syllable
        }
        .prefix(maxCorrectionWidth)
        .map { $0 }
    }

    private static func correctionCost(from input: String, to syllable: String) -> Int? {
        if input == syllable {
            return 0
        }

        let inputCharacters = Array(input)
        let syllableCharacters = Array(syllable)
        let lengthDelta = inputCharacters.count - syllableCharacters.count
        guard abs(lengthDelta) <= 1 else { return nil }

        if lengthDelta == 0 {
            if hasSingleAdjacentKeyboardSubstitution(inputCharacters, syllableCharacters)
                || hasAdjacentTransposition(inputCharacters, syllableCharacters) {
                return 1
            }
            return nil
        }

        let longer = lengthDelta > 0 ? inputCharacters : syllableCharacters
        let shorter = lengthDelta > 0 ? syllableCharacters : inputCharacters
        return canMatchBySkippingOneCharacter(longer: longer, shorter: shorter) ? 1 : nil
    }

    private static func correctionSortRank(from input: String, to syllable: String) -> Int {
        if input == syllable {
            return 0
        }

        let inputCharacters = Array(input)
        let syllableCharacters = Array(syllable)

        if inputCharacters.count == syllableCharacters.count {
            let mismatches = inputCharacters.indices.filter { inputCharacters[$0] != syllableCharacters[$0] }
            if mismatches.count == 1 {
                let typed = inputCharacters[mismatches[0]]
                let expected = syllableCharacters[mismatches[0]]
                if let neighbors = keyboardNeighbors[typed],
                   let index = neighbors.firstIndex(of: expected) {
                    return 10 + neighbors.distance(from: neighbors.startIndex, to: index)
                }
                if let neighbors = keyboardNeighbors[expected],
                   let index = neighbors.firstIndex(of: typed) {
                    return 10 + neighbors.distance(from: neighbors.startIndex, to: index)
                }
            }
            if mismatches.count == 2 {
                return 20
            }
        }

        return inputCharacters.count == syllableCharacters.count ? 30 : 14
    }

    private static func hasSingleAdjacentKeyboardSubstitution(_ input: [Character], _ syllable: [Character]) -> Bool {
        var mismatch: (Character, Character)?
        for index in input.indices {
            guard input[index] != syllable[index] else { continue }
            if mismatch != nil {
                return false
            }
            mismatch = (input[index], syllable[index])
        }

        guard let mismatch else { return false }
        return areKeyboardNeighbors(mismatch.0, mismatch.1)
    }

    private static func hasAdjacentTransposition(_ input: [Character], _ syllable: [Character]) -> Bool {
        var mismatches: [Int] = []
        for index in input.indices where input[index] != syllable[index] {
            mismatches.append(index)
        }

        guard mismatches.count == 2,
              mismatches[1] == mismatches[0] + 1 else {
            return false
        }

        return input[mismatches[0]] == syllable[mismatches[1]]
            && input[mismatches[1]] == syllable[mismatches[0]]
    }

    private static func canMatchBySkippingOneCharacter(longer: [Character], shorter: [Character]) -> Bool {
        var longerIndex = 0
        var shorterIndex = 0
        var skipped = false

        while longerIndex < longer.count && shorterIndex < shorter.count {
            if longer[longerIndex] == shorter[shorterIndex] {
                longerIndex += 1
                shorterIndex += 1
            } else if skipped {
                return false
            } else {
                skipped = true
                longerIndex += 1
            }
        }

        return true
    }

    private static func areKeyboardNeighbors(_ first: Character, _ second: Character) -> Bool {
        keyboardNeighbors[first]?.contains(second) == true
            || keyboardNeighbors[second]?.contains(first) == true
    }

    private static func sharedPrefixLength(_ first: String, _ second: String) -> Int {
        var length = 0
        for (left, right) in zip(first, second) {
            guard left == right else { break }
            length += 1
        }
        return length
    }

    private static func pruneCorrectionPaths(_ paths: [CorrectionPath]) -> [CorrectionPath] {
        var bestByKey: [String: CorrectionPath] = [:]
        for path in paths {
            if let current = bestByKey[path.key],
               current.cost < path.cost
                || (current.cost == path.cost && current.correctedSyllables < path.correctedSyllables)
                || (current.cost == path.cost
                    && current.correctedSyllables == path.correctedSyllables
                    && current.sortScore <= path.sortScore) {
                continue
            }
            bestByKey[path.key] = path
        }

        return bestByKey.values.sorted {
            if $0.cost != $1.cost {
                return $0.cost < $1.cost
            }
            if $0.key.count != $1.key.count {
                return $0.key.count < $1.key.count
            }
            if $0.sortScore != $1.sortScore {
                return $0.sortScore < $1.sortScore
            }
            if $0.correctedSyllables != $1.correctedSyllables {
                return $0.correctedSyllables < $1.correctedSyllables
            }
            if $0.syllables.count != $1.syllables.count {
                return $0.syllables.count < $1.syllables.count
            }
            return $0.key < $1.key
        }.prefix(maxCorrectionWidth).map { $0 }
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

    private struct LooseKeyAlias {
        let pinyinKeys: [String]
        let preferredText: String?
    }

    private enum MatchKind {
        case exact
        case completion
        case fuzzy
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
    private static let maxBundledCandidateCacheEntries = 512
    private static let recordSize = 20
    private static let fnvOffsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let fnvPrime: UInt64 = 1_099_511_628_211
    private static let maxBeamSyllables = 8
    private static let maxBeamSpan = 4
    private static let maxBeamWidth = 8
    private static let maxCompletionKeys = 32
    private static let completionRankPenalty = 120_000
    private static let initialShorthandPhraseBonus = 350_000
    private static let maxAcronymSyllablesPerLetter = 8
    private static let maxAcronymKeySequences = 512
    private static let maxAcronymFallbackSequences = 12
    private static let maxAcronymResults = 96
    private static let acronymPhraseBonus = 600_000
    private static let acronymFallbackBaseScore = 8_600_000
    private static let maxFuzzyCorrectionKeys = 24
    private static let fuzzyRankPenalty = 10_000
    private static let fuzzyCorrectionPenalty = 220_000
    private static let fuzzyDeletedCharacterBonus = 650_000
    private static let maxSegmentedPhraseInputLength = 18
    private static let maxSegmentedPhraseSpan = 6
    private static let maxSegmentedPhraseWidth = 10
    private static let looseKeyAliases: [String: [LooseKeyAlias]] = [
        "sj": [LooseKeyAlias(pinyinKeys: ["shouji"], preferredText: "手机")],
        "qwer": [LooseKeyAlias(pinyinKeys: ["chuqu", "waner"], preferredText: "出去玩儿")],
        "ty": [LooseKeyAlias(pinyinKeys: ["tianyu"], preferredText: "天宇")],
        "ii": [LooseKeyAlias(pinyinKeys: ["o"], preferredText: "哦")]
    ]

    private let lexiconURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "tsv")
    private let indexURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "idx")
    private let defaults = UserDefaults.standard
    private let bundledCandidateCacheLock = NSLock()
    private var bundledCandidateCache: [String: [PinyinCandidate]] = [:]
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
        let exactCandidates = scoredCandidates(for: key, match: .exact, consumeLength: key.count, cache: &lookupCache)
        candidates += exactCandidates
        let completionCandidates = completionCandidates(for: key, cache: &lookupCache)
        candidates += completionCandidates
        candidates += initialShorthandCandidates(for: key, cache: &lookupCache)
        candidates += acronymCandidates(for: key, cache: &lookupCache)
        if candidates.count < 16 {
            candidates += fuzzyCorrectionCandidates(for: key, cache: &lookupCache)
        }

        let segments = PinyinSegmenter.segment(key)
        if segments.count > 1 {
            candidates += beamCandidates(from: segments, fullKey: key, cache: &lookupCache)
        }

        if shouldUseSegmentedPhraseCandidates(
            for: key,
            segments: segments,
            hasExactCandidates: !exactCandidates.isEmpty,
            currentCandidateCount: candidates.count
        ) {
            candidates += segmentedPhraseCandidates(for: key, cache: &lookupCache)
        }

        if !completionCandidates.isEmpty || candidates.count < 16 {
            candidates += longestPrefixCandidates(for: key, cache: &lookupCache)
        }
        candidates += fallbackCandidates(for: key)

        return applyUserMemory(to: merge(candidates), key: key)
    }

    private func shouldUseSegmentedPhraseCandidates(
        for key: String,
        segments: [String],
        hasExactCandidates: Bool,
        currentCandidateCount: Int
    ) -> Bool {
        guard key.count >= 4, key.count <= Self.maxSegmentedPhraseInputLength else { return false }
        if segments.count > 1,
           segments.joined(separator: "") == key,
           (hasExactCandidates || currentCandidateCount >= 12) {
            return false
        }
        return true
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

    private func initialShorthandCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        PinyinSegmenter.initialShorthandKeys(for: key, limit: Self.maxCompletionKeys).flatMap { shorthandKey in
            scoredCandidates(for: shorthandKey, match: .completion, consumeLength: key.count, cache: &cache).prefix(4).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + Self.initialShorthandPhraseBonus,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
        }
    }

    private func acronymCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        let sequences = PinyinSegmenter.acronymKeySequences(
            for: key,
            syllablesPerLetterLimit: Self.maxAcronymSyllablesPerLetter,
            sequenceLimit: Self.maxAcronymKeySequences
        )
        guard !sequences.isEmpty else { return [] }

        var results: [PinyinCandidate] = []

        for sequence in sequences {
            let lookupKey = sequence.joined(separator: "")
            results += scoredCandidates(for: lookupKey, match: .completion, consumeLength: key.count, cache: &cache).prefix(3).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + Self.acronymPhraseBonus,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
            if results.count >= Self.maxAcronymResults {
                break
            }
        }

        for sequence in sequences.prefix(Self.maxAcronymFallbackSequences) {
            results += phraseCandidates(for: sequence, consumeLength: key.count, cache: &cache).prefix(2).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + Self.acronymFallbackBaseScore,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
        }

        return merge(results)
    }

    private func fuzzyCorrectionCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        PinyinSegmenter.correctionKeys(for: key, limit: Self.maxFuzzyCorrectionKeys).enumerated().flatMap { rank, correction in
            var results = scoredCandidates(for: correction.key, match: .fuzzy, consumeLength: key.count, cache: &cache).prefix(6).map { candidate in
                fuzzyCandidate(candidate, correction: correction, rank: rank, consumeLength: key.count)
            }

            if results.isEmpty {
                results += phraseCandidates(for: correction.syllables, consumeLength: key.count, cache: &cache).prefix(4).map { candidate in
                    fuzzyCandidate(candidate, correction: correction, rank: rank, consumeLength: key.count)
                }
            }

            return results
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

    private func segmentedPhraseCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        guard key.count >= 4, key.count <= Self.maxSegmentedPhraseInputLength else { return [] }

        let indices = Array(key.indices) + [key.endIndex]
        var paths = Array(repeating: [BeamPath](), count: key.count + 1)
        paths[0] = [BeamPath(text: "", score: 0, parts: 0)]

        for start in 0..<key.count {
            guard !paths[start].isEmpty else { continue }
            let matches = segmentedMatches(in: key, start: start, indices: indices, cache: &cache)
            guard !matches.isEmpty else { continue }

            for path in paths[start] {
                for match in matches {
                    let end = start + match.consumeLength
                    let text = path.text + match.text
                    guard text.count <= 24 else { continue }
                    let score = path.score + beamPartScore(match, span: max(1, match.syllableCount))
                    paths[end].append(BeamPath(text: text, score: score, parts: path.parts + 1))
                }
            }
            let maxEnd = min(key.count, start + Self.maxSegmentedPhraseSpan)
            for end in (start + 1)...maxEnd where !paths[end].isEmpty {
                paths[end] = pruneSegmentedPhrasePaths(paths[end])
            }
        }

        return pruneSegmentedPhrasePaths(paths[key.count])
            .filter { $0.parts > 1 }
            .map { path in
                let averageScore = path.score / max(1, path.parts)
                let score = 2_600_000 + averageScore - path.parts * 90_000
                return PinyinCandidate(
                    text: path.text,
                    weight: score,
                    tier: 4,
                    wordLength: path.text.count,
                    syllableCount: path.parts,
                    consumeLength: key.count
                )
            }
    }

    private func segmentedMatches(
        in key: String,
        start: Int,
        indices: [String.Index],
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        let maxEnd = min(key.count, start + Self.maxSegmentedPhraseSpan)
        guard maxEnd > start else { return [] }

        var results: [PinyinCandidate] = []
        for end in stride(from: maxEnd, through: start + 1, by: -1) {
            let piece = String(key[indices[start]..<indices[end]])
            let consumeLength = end - start

            let exact = scoredCandidates(for: piece, match: .exact, consumeLength: consumeLength, cache: &cache).prefix(4)
            results += exact

            let aliases = looseAliasCandidates(for: piece, consumeLength: consumeLength, cache: &cache).prefix(4)
            results += aliases

            let completions = segmentedCompletionCandidates(for: piece, consumeLength: consumeLength, cache: &cache).prefix(4)
            results += completions
        }

        return results.sorted {
            if $0.weight != $1.weight {
                return $0.weight > $1.weight
            }
            if $0.consumeLength != $1.consumeLength {
                return $0.consumeLength > $1.consumeLength
            }
            return $0.text < $1.text
        }.prefix(12).map { $0 }
    }

    private func looseAliasCandidates(
        for key: String,
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        guard let aliases = Self.looseKeyAliases[key] else { return [] }
        var candidates: [PinyinCandidate] = []

        for (aliasIndex, alias) in aliases.enumerated() {
            if let preferredText = alias.preferredText {
                candidates.append(PinyinCandidate(
                    text: preferredText,
                    weight: 1_800_000 - aliasIndex * 10_000,
                    tier: 4,
                    wordLength: preferredText.count,
                    syllableCount: alias.pinyinKeys.count,
                    consumeLength: consumeLength
                ))
            }
            candidates += phraseCandidates(for: alias.pinyinKeys, consumeLength: consumeLength, cache: &cache)
        }

        return merge(candidates)
    }

    private func phraseCandidates(
        for pinyinKeys: [String],
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        guard !pinyinKeys.isEmpty else { return [] }
        var paths = [BeamPath(text: "", score: 0, parts: 0)]

        for pinyinKey in pinyinKeys {
            let candidates = cachedBundledCandidates(for: pinyinKey, cache: &cache).prefix(3)
            guard !candidates.isEmpty else { return [] }

            var nextPaths: [BeamPath] = []
            for path in paths {
                for candidate in candidates {
                    let text = path.text + candidate.text
                    let score = path.score + beamPartScore(candidate, span: 1)
                    nextPaths.append(BeamPath(text: text, score: score, parts: path.parts + 1))
                }
            }
            paths = pruneSegmentedPhrasePaths(nextPaths)
        }

        return paths.map { path in
            PinyinCandidate(
                text: path.text,
                weight: path.score / max(1, path.parts),
                tier: 4,
                wordLength: path.text.count,
                syllableCount: pinyinKeys.count,
                consumeLength: consumeLength
            )
        }
    }

    private func segmentedCompletionCandidates(
        for key: String,
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        PinyinSegmenter.completionKeys(for: key, limit: 12).enumerated().flatMap { rank, completion in
            scoredCandidates(for: completion.key, match: .completion, consumeLength: consumeLength, cache: &cache).prefix(3).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight - rank * Self.completionRankPenalty,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: consumeLength
                )
            }
        }
    }

    private func pruneSegmentedPhrasePaths(_ paths: [BeamPath]) -> [BeamPath] {
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
        }.prefix(Self.maxSegmentedPhraseWidth).map { $0 }
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
        case .fuzzy:
            baseScore = 8_000_000
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

    private func fuzzyCandidate(
        _ candidate: PinyinCandidate,
        correction: PinyinCorrection,
        rank: Int,
        consumeLength: Int
    ) -> PinyinCandidate {
        PinyinCandidate(
            text: candidate.text,
            weight: candidate.weight
                - correction.cost * Self.fuzzyCorrectionPenalty
                - correction.correctedSyllables * 80_000
                - rank * Self.fuzzyRankPenalty
                + max(0, consumeLength - correction.key.count) * Self.fuzzyDeletedCharacterBonus,
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
        if let cached = memoryCachedBundledCandidates(for: key) {
            return cached.isEmpty ? nil : cached
        }

        guard let lexiconURL, let indexURL, recordCount > 0 else { return nil }
        let records = findRecords(for: key, in: indexURL)
        guard !records.isEmpty else {
            storeBundledCandidates([], for: key)
            return nil
        }
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
                let candidates = fields
                    .dropFirst()
                    .enumerated()
                    .map { index, field in
                        Self.parseCandidateField(String(field), fallbackWeight: 120 - index)
                    }
                storeBundledCandidates(candidates, for: key)
                return candidates
            } catch {
                continue
            }
        }

        storeBundledCandidates([], for: key)
        return nil
    }

    private func memoryCachedBundledCandidates(for key: String) -> [PinyinCandidate]? {
        bundledCandidateCacheLock.lock()
        defer { bundledCandidateCacheLock.unlock() }
        return bundledCandidateCache[key]
    }

    private func storeBundledCandidates(_ candidates: [PinyinCandidate], for key: String) {
        bundledCandidateCacheLock.lock()
        defer { bundledCandidateCacheLock.unlock() }
        if bundledCandidateCache[key] == nil,
           bundledCandidateCache.count >= Self.maxBundledCandidateCacheEntries {
            bundledCandidateCache.removeAll(keepingCapacity: true)
        }
        bundledCandidateCache[key] = candidates
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
