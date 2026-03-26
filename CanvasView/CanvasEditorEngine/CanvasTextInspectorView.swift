import UIKit

enum CanvasTextInspectorColorTarget {
    case foreground
    case background
    case shadow
    case outline
}

protocol CanvasTextInspectorViewDelegate: AnyObject {
    func textInspectorViewDidRequestTextEdit(_ textInspectorView: CanvasTextInspectorView)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectFontFamily fontFamily: String)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectAlignment alignment: CanvasTextAlignment)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectColor color: CanvasColor, for target: CanvasTextInspectorColorTarget)
    func textInspectorViewDidSelectClearBackground(_ textInspectorView: CanvasTextInspectorView)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didRequestColorPickerFor target: CanvasTextInspectorColorTarget)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetItalic isItalic: Bool)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetShadow isEnabled: Bool)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetOutline isEnabled: Bool)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeFontSize value: Double)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeLetterSpacing value: Double)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeLineSpacing value: Double)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeOpacity value: Double)
}

final class CanvasTextInspectorView: UIView {
    private enum Layout {
        static let horizontalInset: CGFloat = 18
        static let verticalInset: CGFloat = 14
    }

    weak var delegate: CanvasTextInspectorViewDelegate?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let editTextButton = UIButton(type: .system)
    private let fontFamilyStripView = InspectorFontFamilyStripView()
    private let alignmentControl = UISegmentedControl(items: ["L", "C", "R"])
    private let italicButton = UIButton(type: .system)
    private let shadowButton = UIButton(type: .system)
    private let outlineButton = UIButton(type: .system)
    private let textColorStripView = InspectorColorStripView(target: .foreground, showsClearChip: false)
    private let backgroundColorStripView = InspectorColorStripView(target: .background, showsClearChip: true)
    private let shadowColorStripView = InspectorColorStripView(target: .shadow, showsClearChip: false)
    private let outlineColorStripView = InspectorColorStripView(target: .outline, showsClearChip: false)

    private let fontSizeRow = InspectorSliderRow(title: "Font Size", range: 16...120)
    private let letterSpacingRow = InspectorSliderRow(title: "Letter Space", range: -4...24)
    private let lineSpacingRow = InspectorSliderRow(title: "Line Space", range: 0...32)
    private let opacityRow = InspectorSliderRow(title: "Opacity", range: 0.0...1.0)

    private lazy var fontSectionView = section(title: "Font", view: fontFamilyStripView)
    private lazy var alignmentSectionView = section(title: "Alignment", view: alignmentControl)
    private lazy var styleSectionView = section(title: "Style", view: toggleStack)
    private lazy var textColorSectionView = section(title: "Text Color", view: textColorStripView)
    private lazy var backgroundSectionView = section(title: "Background", view: backgroundColorStripView)
    private lazy var shadowColorSectionView = section(title: "Shadow Color", view: shadowColorStripView)
    private lazy var outlineColorSectionView = section(title: "Outline Color", view: outlineColorStripView)
    private lazy var toggleStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [italicButton, shadowButton, outlineButton])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        return stack
    }()

    private var fontFamilies: [String] = []
    private var palette: [CanvasColor] = []
    private var isApplyingState = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = CanvasEditorTheme.sheetSurface
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous

        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        titleLabel.text = "Text Inspector"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = CanvasEditorTheme.primaryText

        var editButtonConfiguration = UIButton.Configuration.filled()
        editButtonConfiguration.title = "Edit Content"
        editButtonConfiguration.baseBackgroundColor = CanvasEditorTheme.accent
        editButtonConfiguration.baseForegroundColor = .white
        editButtonConfiguration.cornerStyle = .capsule
        editButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        editTextButton.configuration = editButtonConfiguration
        editTextButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.textInspectorViewDidRequestTextEdit(self)
        }, for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, UIView(), editTextButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        contentStack.addArrangedSubview(headerStack)

        fontFamilyStripView.onSelectFontFamily = { [weak self] fontFamily in
            guard let self, !self.isApplyingState else { return }
            self.delegate?.textInspectorView(self, didSelectFontFamily: fontFamily)
        }
        contentStack.addArrangedSubview(fontSectionView)

        alignmentControl.selectedSegmentIndex = 1
        alignmentControl.selectedSegmentTintColor = CanvasEditorTheme.accent
        alignmentControl.backgroundColor = CanvasEditorTheme.canvasBackdrop
        alignmentControl.setTitleTextAttributes([.foregroundColor: CanvasEditorTheme.secondaryText], for: .normal)
        alignmentControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        alignmentControl.addAction(UIAction { [weak self] _ in
            self?.didChangeAlignment()
        }, for: .valueChanged)
        contentStack.addArrangedSubview(alignmentSectionView)

        configureToggleButton(italicButton, title: "Italic") { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didSetItalic: self.italicButton.isSelected)
        }
        configureToggleButton(shadowButton, title: "Shadow") { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didSetShadow: self.shadowButton.isSelected)
        }
        configureToggleButton(outlineButton, title: "Outline") { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didSetOutline: self.outlineButton.isSelected)
        }
        contentStack.addArrangedSubview(styleSectionView)

        textColorStripView.onSelectColor = { [weak self] color in
            guard let self, !self.isApplyingState else { return }
            self.delegate?.textInspectorView(self, didSelectColor: color, for: .foreground)
        }
        textColorStripView.onRequestPicker = { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didRequestColorPickerFor: .foreground)
        }
        contentStack.addArrangedSubview(textColorSectionView)

        backgroundColorStripView.onSelectColor = { [weak self] color in
            guard let self, !self.isApplyingState else { return }
            self.delegate?.textInspectorView(self, didSelectColor: color, for: .background)
        }
        backgroundColorStripView.onRequestPicker = { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didRequestColorPickerFor: .background)
        }
        backgroundColorStripView.onSelectClear = { [weak self] in
            guard let self, !self.isApplyingState else { return }
            self.delegate?.textInspectorViewDidSelectClearBackground(self)
        }
        contentStack.addArrangedSubview(backgroundSectionView)

        shadowColorStripView.onSelectColor = { [weak self] color in
            guard let self, !self.isApplyingState else { return }
            self.delegate?.textInspectorView(self, didSelectColor: color, for: .shadow)
        }
        shadowColorStripView.onRequestPicker = { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didRequestColorPickerFor: .shadow)
        }
        contentStack.addArrangedSubview(shadowColorSectionView)

        outlineColorStripView.onSelectColor = { [weak self] color in
            guard let self, !self.isApplyingState else { return }
            self.delegate?.textInspectorView(self, didSelectColor: color, for: .outline)
        }
        outlineColorStripView.onRequestPicker = { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didRequestColorPickerFor: .outline)
        }
        contentStack.addArrangedSubview(outlineColorSectionView)

        [fontSizeRow, letterSpacingRow, lineSpacingRow, opacityRow].forEach { row in
            row.onChange = { [weak self, weak row] value in
                guard let self, let row, !self.isApplyingState else { return }
                switch row {
                case self.fontSizeRow:
                    self.delegate?.textInspectorView(self, didChangeFontSize: value)
                case self.letterSpacingRow:
                    self.delegate?.textInspectorView(self, didChangeLetterSpacing: value)
                case self.lineSpacingRow:
                    self.delegate?.textInspectorView(self, didChangeLineSpacing: value)
                case self.opacityRow:
                    self.delegate?.textInspectorView(self, didChangeOpacity: value)
                default:
                    break
                }
            }
            contentStack.addArrangedSubview(row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func preferredHeight(for width: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        let contentWidth = max(width - (Layout.horizontalInset * 2), 1)
        invalidateContentLayout()
        layoutIfNeeded()
        let contentHeight = measuredContentHeight(for: contentWidth)
        return min(maximumHeight, contentHeight + (Layout.verticalInset * 2))
    }

    func configure(fontFamilies: [String], palette: [CanvasColor]) {
        self.fontFamilies = fontFamilies
        self.palette = palette
        fontFamilyStripView.configure(fontFamilies: fontFamilies)
        textColorStripView.configure(palette: palette)
        backgroundColorStripView.configure(palette: palette)
        shadowColorStripView.configure(palette: palette)
        outlineColorStripView.configure(palette: palette)
    }

    func apply(node: CanvasNode) {
        let style = node.style ?? (node.kind == .emoji ? .defaultEmoji : .defaultText)

        isHidden = false
        isApplyingState = true
        defer { isApplyingState = false }

        if !fontFamilies.contains(style.fontFamily) {
            fontFamilyStripView.configure(fontFamilies: fontFamilies + [style.fontFamily])
        } else {
            fontFamilyStripView.configure(fontFamilies: fontFamilies)
        }
        fontFamilyStripView.setSelectedFontFamily(style.fontFamily)
        alignmentControl.selectedSegmentIndex = index(for: style.alignment)
        italicButton.isSelected = style.isItalic
        shadowButton.isSelected = style.shadow != nil
        outlineButton.isSelected = style.outline != nil

        [italicButton, shadowButton, outlineButton].forEach(updateToggleButtonAppearance)

        fontSizeRow.value = style.fontSize
        letterSpacingRow.value = style.letterSpacing
        lineSpacingRow.value = style.lineSpacing
        opacityRow.value = style.opacity
        textColorStripView.applySelection(color: style.foregroundColor)
        backgroundColorStripView.applySelection(color: style.backgroundFill?.color)
        shadowColorStripView.applySelection(color: style.shadow?.color)
        outlineColorStripView.applySelection(color: style.outline?.color)
        shadowColorSectionView.isHidden = style.shadow == nil
        outlineColorSectionView.isHidden = style.outline == nil

        let isEmoji = node.kind == .emoji
        fontSectionView.isHidden = isEmoji
        alignmentSectionView.isHidden = isEmoji
        invalidateContentLayout()
    }

    private func section(title: String, view: UIView) -> UIView {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = CanvasEditorTheme.secondaryText

        let stack = UIStackView(arrangedSubviews: [label, view])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.applyCanvasEditorCardStyle(
            backgroundColor: CanvasEditorTheme.cardSurface,
            cornerRadius: 18,
            borderColor: CanvasEditorTheme.separator,
            shadowColor: CanvasEditorTheme.controlShadow,
            shadowOpacity: 1,
            shadowRadius: 14,
            shadowOffset: CGSize(width: 0, height: 8)
        )
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func measuredContentHeight(for width: CGFloat) -> CGFloat {
        contentStack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func invalidateContentLayout() {
        setNeedsLayout()
        scrollView.setNeedsLayout()
        contentStack.setNeedsLayout()
    }

    private func configureToggleButton(_ button: UIButton, title: String, action: @escaping () -> Void) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .large
        button.configuration = configuration
        button.addAction(UIAction { _ in
            button.isSelected.toggle()
            self.updateToggleButtonAppearance(button)
            action()
        }, for: .touchUpInside)
        updateToggleButtonAppearance(button)
    }

    private func updateToggleButtonAppearance(_ button: UIButton) {
        button.configuration?.baseForegroundColor = button.isSelected ? CanvasEditorTheme.accent : CanvasEditorTheme.primaryText
        button.configuration?.baseBackgroundColor = button.isSelected ? CanvasEditorTheme.accentMuted : CanvasEditorTheme.canvasBackdrop
        button.configuration?.background.strokeColor = button.isSelected
            ? CanvasEditorTheme.accent.withAlphaComponent(0.28)
            : CanvasEditorTheme.separator
    }

    private func didChangeAlignment() {
        guard !isApplyingState else {
            return
        }
        let alignment: CanvasTextAlignment
        switch alignmentControl.selectedSegmentIndex {
        case 0:
            alignment = .leading
        case 2:
            alignment = .trailing
        default:
            alignment = .center
        }
        delegate?.textInspectorView(self, didSelectAlignment: alignment)
    }

    private func index(for alignment: CanvasTextAlignment) -> Int {
        switch alignment {
        case .leading: 0
        case .center: 1
        case .trailing: 2
        }
    }
}

private final class InspectorFontFamilyStripView: UIView {
    var onSelectFontFamily: ((String) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var buttons: [String: UIButton] = [:]
    private var displayedFontFamilies: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(fontFamilies: [String]) {
        guard displayedFontFamilies != fontFamilies else {
            return
        }
        displayedFontFamilies = fontFamilies
        rebuildButtons()
    }

    func setSelectedFontFamily(_ fontFamily: String) {
        buttons.forEach { family, button in
            let isSelected = family == fontFamily
            button.backgroundColor = isSelected ? CanvasEditorTheme.accentMuted : CanvasEditorTheme.canvasBackdrop
            button.layer.borderColor = isSelected
                ? CanvasEditorTheme.accent.withAlphaComponent(0.26).cgColor
                : CanvasEditorTheme.separator.cgColor
            button.setTitleColor(isSelected ? CanvasEditorTheme.accent : CanvasEditorTheme.primaryText, for: .normal)
        }
    }

    private func rebuildButtons() {
        buttons.removeAll()
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        displayedFontFamilies.forEach { fontFamily in
            let button = UIButton(type: .custom)
            let font = UIFont(name: fontFamily, size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .medium)
            let titleWidth = ceil((fontFamily as NSString).size(withAttributes: [.font: font]).width) + 32
            button.setTitle(fontFamily, for: .normal)
            button.setTitleColor(CanvasEditorTheme.primaryText, for: .normal)
            button.titleLabel?.font = font
            button.backgroundColor = CanvasEditorTheme.canvasBackdrop
            button.layer.cornerRadius = 18
            button.layer.borderWidth = 1
            button.layer.borderColor = CanvasEditorTheme.separator.cgColor
            button.heightAnchor.constraint(equalToConstant: 38).isActive = true
            button.widthAnchor.constraint(equalToConstant: titleWidth).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.setSelectedFontFamily(fontFamily)
                self?.onSelectFontFamily?(fontFamily)
            }, for: .touchUpInside)
            buttons[fontFamily] = button
            stackView.addArrangedSubview(button)
        }
    }
}

private final class InspectorColorStripView: UIView {
    var onSelectColor: ((CanvasColor) -> Void)?
    var onSelectClear: (() -> Void)?
    var onRequestPicker: (() -> Void)?

    private let target: CanvasTextInspectorColorTarget
    private let showsClearChip: Bool
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let pickerButton = InspectorColorChipButton()
    private let clearButton = InspectorColorChipButton()
    private var paletteButtons: [CanvasColor: InspectorColorChipButton] = [:]
    private var palette: [CanvasColor] = []
    private var customColor: CanvasColor?
    private var selectedColor: CanvasColor?

    init(target: CanvasTextInspectorColorTarget, showsClearChip: Bool) {
        self.target = target
        self.showsClearChip = showsClearChip
        super.init(frame: .zero)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        pickerButton.configure(kind: .picker)
        pickerButton.accessibilityLabel = target.pickerAccessibilityLabel
        pickerButton.addAction(UIAction { [weak self] _ in
            self?.onRequestPicker?()
        }, for: .touchUpInside)

        clearButton.configure(kind: .clear)
        clearButton.accessibilityLabel = target.clearAccessibilityLabel
        clearButton.addAction(UIAction { [weak self] _ in
            self?.applySelection(color: nil)
            self?.onSelectClear?()
        }, for: .touchUpInside)

        rebuildButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(palette: [CanvasColor]) {
        guard self.palette != palette else {
            return
        }
        self.palette = palette
        rebuildButtons()
    }

    func applySelection(color: CanvasColor?) {
        selectedColor = color
        customColor = nil

        if let color {
            if !palette.contains(color) {
                customColor = color
            }
            pickerButton.setDisplayedColor(customColor?.uiColor)
        } else {
            pickerButton.setDisplayedColor(nil)
        }

        if showsClearChip {
            clearButton.isSelected = color == nil
        }
        pickerButton.isSelected = color != nil && customColor != nil

        for (paletteColor, button) in paletteButtons {
            button.isSelected = paletteColor == color
        }
    }

    private func rebuildButtons() {
        paletteButtons.removeAll()
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if showsClearChip {
            stackView.addArrangedSubview(clearButton)
        }
        stackView.addArrangedSubview(pickerButton)

        palette.forEach { color in
            let button = InspectorColorChipButton()
            button.configure(kind: .color(color.uiColor))
            button.accessibilityLabel = target.paletteAccessibilityLabel
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }

                if self.showsClearChip, self.selectedColor == color {
                    self.applySelection(color: nil)
                    self.onSelectClear?()
                    return
                }

                self.applySelection(color: color)
                self.onSelectColor?(color)
            }, for: .touchUpInside)
            paletteButtons[color] = button
            stackView.addArrangedSubview(button)
        }
    }
}

private extension CanvasTextInspectorColorTarget {
    var pickerAccessibilityLabel: String {
        switch self {
        case .foreground:
            "Pick text color"
        case .background:
            "Pick background color"
        case .shadow:
            "Pick shadow color"
        case .outline:
            "Pick outline color"
        }
    }

    var paletteAccessibilityLabel: String {
        switch self {
        case .foreground:
            "Text color"
        case .background:
            "Background color"
        case .shadow:
            "Shadow color"
        case .outline:
            "Outline color"
        }
    }

    var clearAccessibilityLabel: String {
        switch self {
        case .background:
            "Clear background"
        case .foreground, .shadow, .outline:
            "Clear color"
        }
    }
}

private final class InspectorColorChipButton: UIButton {
    enum Kind {
        case color(UIColor)
        case clear
        case picker
    }

    private let ringView = UIView()
    private let swatchView = UIView()
    private let iconView = UIImageView()
    private var kind: Kind = .picker
    private var displayedColor: UIColor?

    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        ringView.translatesAutoresizingMaskIntoConstraints = false
        ringView.isUserInteractionEnabled = false
        ringView.layer.cornerRadius = 22
        ringView.layer.borderWidth = 1.5
        addSubview(ringView)

        swatchView.translatesAutoresizingMaskIntoConstraints = false
        swatchView.isUserInteractionEnabled = false
        swatchView.layer.cornerRadius = 17
        addSubview(swatchView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 44),

            ringView.leadingAnchor.constraint(equalTo: leadingAnchor),
            ringView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ringView.topAnchor.constraint(equalTo: topAnchor),
            ringView.bottomAnchor.constraint(equalTo: bottomAnchor),

            swatchView.centerXAnchor.constraint(equalTo: centerXAnchor),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 34),
            swatchView.heightAnchor.constraint(equalToConstant: 34),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(kind: Kind) {
        self.kind = kind
        updateAppearance()
    }

    func setDisplayedColor(_ color: UIColor?) {
        displayedColor = color
        updateAppearance()
    }

    private func updateAppearance() {
        switch kind {
        case .color(let color):
            swatchView.backgroundColor = color
            ringView.backgroundColor = .clear
            ringView.layer.borderColor = isSelected ? CanvasEditorTheme.accent.cgColor : UIColor.clear.cgColor
            iconView.image = isSelected ? UIImage(systemName: "checkmark") : nil
            iconView.tintColor = color.isLightColor ? .black : .white

        case .clear:
            swatchView.backgroundColor = CanvasEditorTheme.cardSurface
            ringView.backgroundColor = isSelected ? CanvasEditorTheme.accentMuted : CanvasEditorTheme.canvasBackdrop
            ringView.layer.borderColor = isSelected ? CanvasEditorTheme.accent.cgColor : CanvasEditorTheme.separator.cgColor
            iconView.image = isSelected ? UIImage(systemName: "checkmark.circle.fill") : UIImage(systemName: "circle")
            iconView.tintColor = isSelected ? CanvasEditorTheme.accent : CanvasEditorTheme.secondaryText

        case .picker:
            let resolvedColor = displayedColor ?? CanvasEditorTheme.canvasBackdrop
            swatchView.backgroundColor = resolvedColor
            ringView.backgroundColor = isSelected ? CanvasEditorTheme.accentMuted : CanvasEditorTheme.cardSurface
            ringView.layer.borderColor = isSelected ? CanvasEditorTheme.accent.cgColor : CanvasEditorTheme.separator.cgColor
            iconView.image = UIImage(systemName: displayedColor == nil ? "eyedropper.halffull" : "eyedropper.full")
            iconView.tintColor = displayedColor?.isLightColor == true ? .black : CanvasEditorTheme.primaryText
        }
    }
}

private extension UIColor {
    var isLightColor: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            return luminance > 0.68
        }

        let fallback = CIColor(color: self)
        let luminance = (0.299 * fallback.red) + (0.587 * fallback.green) + (0.114 * fallback.blue)
        return luminance > 0.68
    }
}

private final class InspectorSliderRow: UIView {
    var onChange: ((Double) -> Void)?

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let range: ClosedRange<Double>

    init(title: String, range: ClosedRange<Double>) {
        self.range = range
        super.init(frame: .zero)

        applyCanvasEditorCardStyle(
            backgroundColor: CanvasEditorTheme.cardSurface,
            cornerRadius: 18,
            borderColor: CanvasEditorTheme.separator,
            shadowColor: CanvasEditorTheme.controlShadow,
            shadowOpacity: 1,
            shadowRadius: 14,
            shadowOffset: CGSize(width: 0, height: 8)
        )

        titleLabel.text = title.uppercased()
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = CanvasEditorTheme.secondaryText

        valueLabel.textColor = CanvasEditorTheme.primaryText
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textAlignment = .right

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), valueLabel])
        header.axis = .horizontal

        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.minimumTrackTintColor = CanvasEditorTheme.accent
        slider.maximumTrackTintColor = CanvasEditorTheme.separator
        slider.thumbTintColor = CanvasEditorTheme.accent
        slider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            valueLabel.text = String(format: "%.1f", self.value)
            onChange?(self.value)
        }, for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [header, slider])
        stack.axis = .vertical
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
        value = (range.lowerBound + range.upperBound) / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var value: Double {
        get { Double(slider.value) }
        set {
            slider.value = Float(min(max(newValue, range.lowerBound), range.upperBound))
            valueLabel.text = String(format: "%.1f", Double(slider.value))
        }
    }
}

protocol CanvasBrushInspectorViewDelegate: AnyObject {
    func canvasBrushInspectorViewDidCancel(_ brushInspectorView: CanvasBrushInspectorView)
    func canvasBrushInspectorView(_ brushInspectorView: CanvasBrushInspectorView, didChange configuration: CanvasBrushConfiguration)
    func canvasBrushInspectorView(_ brushInspectorView: CanvasBrushInspectorView, didConfirm configuration: CanvasBrushConfiguration)
}

final class CanvasBrushInspectorView: UIView {
    private enum Layout {
        static let horizontalInset: CGFloat = 18
        static let verticalInset: CGFloat = 14
    }

    weak var delegate: CanvasBrushInspectorViewDelegate?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let cancelButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let confirmButton = UIButton(type: .system)
    private let shapeStack = UIStackView()
    private let colorStack = UIStackView()
    private let sizeRow = InspectorSliderRow(title: "Size", range: 4...48)
    private let opacityRow = InspectorSliderRow(title: "Opacity", range: 0.1...1.0)
    private lazy var shapeSectionView = section(title: "Shape", contentView: shapeStack)
    private lazy var colorSectionView = section(title: "Color", contentView: colorStack)

    private var palette: [CanvasColor] = []
    private var isApplyingState = false
    private var shapeButtons: [CanvasShapeType: UIButton] = [:]
    private var currentConfiguration = CanvasBrushConfiguration.defaultValue

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = CanvasEditorTheme.sheetSurface
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous

        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        configureHeader()
        configureShapeSection()

        sizeRow.onChange = { [weak self] value in
            guard let self, !self.isApplyingState else { return }
            self.currentConfiguration.strokeWidth = value
            self.notifyConfigurationDidChange()
        }
        opacityRow.onChange = { [weak self] value in
            guard let self, !self.isApplyingState else { return }
            self.currentConfiguration.opacity = value
            self.notifyConfigurationDidChange()
        }

        contentStack.addArrangedSubview(shapeSectionView)
        contentStack.addArrangedSubview(sizeRow)
        contentStack.addArrangedSubview(opacityRow)

        colorStack.axis = .horizontal
        colorStack.spacing = 10
        colorStack.distribution = .fillEqually
        contentStack.addArrangedSubview(colorSectionView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(palette: [CanvasColor]) {
        self.palette = palette
        rebuildPalette()
        apply(configuration: currentConfiguration)
        invalidateContentLayout()
    }

    func apply(configuration: CanvasBrushConfiguration) {
        currentConfiguration = configuration
        isApplyingState = true
        sizeRow.value = configuration.strokeWidth
        opacityRow.value = configuration.opacity
        updateShapeSelection(selectedType: configuration.type)
        updatePaletteSelection(selectedColor: configuration.color)
        isApplyingState = false
        invalidateContentLayout()
    }

    func preferredHeight(for width: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        let contentWidth = max(width - (Layout.horizontalInset * 2), 1)
        invalidateContentLayout()
        layoutIfNeeded()
        let contentHeight = measuredContentHeight(for: contentWidth)
        return min(maximumHeight, contentHeight + (Layout.verticalInset * 2))
    }

    private func configureHeader() {
        cancelButton.configuration = .plain()
        cancelButton.configuration?.image = UIImage(systemName: "xmark")
        cancelButton.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        cancelButton.configuration?.baseForegroundColor = CanvasEditorTheme.destructive
        cancelButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        cancelButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.canvasBrushInspectorViewDidCancel(self)
        }, for: .touchUpInside)
        cancelButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        cancelButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        titleLabel.text = "Brush"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = CanvasEditorTheme.primaryText
        titleLabel.textAlignment = .center

        confirmButton.configuration = .plain()
        confirmButton.configuration?.image = UIImage(systemName: "checkmark")
        confirmButton.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        confirmButton.configuration?.baseForegroundColor = CanvasEditorTheme.success
        confirmButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        confirmButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.canvasBrushInspectorView(self, didConfirm: self.currentConfiguration)
        }, for: .touchUpInside)
        confirmButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        confirmButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let leadingSpacer = UIView()
        let trailingSpacer = UIView()

        let headerStack = UIStackView(arrangedSubviews: [cancelButton, leadingSpacer, titleLabel, trailingSpacer, confirmButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 4
        leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor).isActive = true
        contentStack.addArrangedSubview(headerStack)
    }

    private func configureShapeSection() {
        shapeStack.axis = .horizontal
        shapeStack.spacing = 10
        shapeStack.distribution = .fillEqually

        CanvasShapeType.allCases.forEach { shapeType in
            let button = UIButton(type: .system)
            button.configuration = .filled()
            button.configuration?.image = UIImage(systemName: shapeType.systemImageName)
            button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            button.configuration?.baseForegroundColor = CanvasEditorTheme.primaryText
            button.configuration?.baseBackgroundColor = CanvasEditorTheme.canvasBackdrop
            button.configuration?.background.cornerRadius = 16
            button.layer.cornerRadius = 16
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.currentConfiguration.type = shapeType
                self.updateShapeSelection(selectedType: shapeType)
                self.notifyConfigurationDidChange()
            }, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            shapeButtons[shapeType] = button
            shapeStack.addArrangedSubview(button)
        }
    }

    private func rebuildPalette() {
        colorStack.arrangedSubviews.forEach {
            colorStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        palette.forEach { color in
            let button = UIButton(type: .system)
            button.backgroundColor = color.uiColor
            button.layer.cornerRadius = 18
            button.layer.borderWidth = 2
            button.layer.borderColor = CanvasEditorTheme.separator.cgColor
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.currentConfiguration.color = color
                self.updatePaletteSelection(selectedColor: color)
                self.notifyConfigurationDidChange()
            }, for: .touchUpInside)
            colorStack.addArrangedSubview(button)
        }
    }

    private func updateShapeSelection(selectedType: CanvasShapeType) {
        shapeButtons.forEach { type, button in
            let isSelected = type == selectedType
            button.configuration?.baseForegroundColor = isSelected ? CanvasEditorTheme.accent : CanvasEditorTheme.primaryText
            button.configuration?.baseBackgroundColor = isSelected ? CanvasEditorTheme.accentMuted : CanvasEditorTheme.canvasBackdrop
            button.configuration?.background.strokeColor = isSelected
                ? CanvasEditorTheme.accent.withAlphaComponent(0.28)
                : CanvasEditorTheme.separator
        }
    }

    private func updatePaletteSelection(selectedColor: CanvasColor) {
        for (index, subview) in colorStack.arrangedSubviews.enumerated() {
            guard let button = subview as? UIButton, palette.indices.contains(index) else {
                continue
            }
            button.layer.borderColor = palette[index] == selectedColor
                ? CanvasEditorTheme.accent.cgColor
                : CanvasEditorTheme.separator.cgColor
        }
    }

    private func section(title: String, contentView: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title.uppercased()
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = CanvasEditorTheme.secondaryText

        let stack = UIStackView(arrangedSubviews: [titleLabel, contentView])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.applyCanvasEditorCardStyle(
            backgroundColor: CanvasEditorTheme.cardSurface,
            cornerRadius: 18,
            borderColor: CanvasEditorTheme.separator,
            shadowColor: CanvasEditorTheme.controlShadow,
            shadowOpacity: 1,
            shadowRadius: 14,
            shadowOffset: CGSize(width: 0, height: 8)
        )
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func measuredContentHeight(for width: CGFloat) -> CGFloat {
        contentStack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func invalidateContentLayout() {
        setNeedsLayout()
        scrollView.setNeedsLayout()
        contentStack.setNeedsLayout()
    }

    private func notifyConfigurationDidChange() {
        delegate?.canvasBrushInspectorView(self, didChange: currentConfiguration)
    }
}
