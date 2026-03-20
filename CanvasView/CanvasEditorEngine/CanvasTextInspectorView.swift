import UIKit

protocol CanvasTextInspectorViewDelegate: AnyObject {
    func textInspectorViewDidRequestTextEdit(_ textInspectorView: CanvasTextInspectorView)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectFontFamily fontFamily: String)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectWeight weight: CanvasFontWeight)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectAlignment alignment: CanvasTextAlignment)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectColor color: CanvasColor)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetItalic isItalic: Bool)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetShadow isEnabled: Bool)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetOutline isEnabled: Bool)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetBackgroundFill isEnabled: Bool)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeFontSize value: Double)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeLetterSpacing value: Double)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeLineSpacing value: Double)
    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeOpacity value: Double)
}

final class CanvasTextInspectorView: UIView {
    weak var delegate: CanvasTextInspectorViewDelegate?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let editTextButton = UIButton(type: .system)
    private let fontButton = UIButton(type: .system)
    private let weightControl = UISegmentedControl(items: ["R", "M", "SB", "B", "H"])
    private let alignmentControl = UISegmentedControl(items: ["L", "C", "R"])
    private let italicButton = UIButton(type: .system)
    private let shadowButton = UIButton(type: .system)
    private let outlineButton = UIButton(type: .system)
    private let backgroundButton = UIButton(type: .system)
    private let colorStack = UIStackView()

    private let fontSizeRow = InspectorSliderRow(title: "Font Size", range: 16...120)
    private let letterSpacingRow = InspectorSliderRow(title: "Letter Space", range: -4...24)
    private let lineSpacingRow = InspectorSliderRow(title: "Line Space", range: 0...32)
    private let opacityRow = InspectorSliderRow(title: "Opacity", range: 0.1...1.0)

    private var fontFamilies: [String] = []
    private var palette: [CanvasColor] = []
    private var isApplyingState = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 0.96)
        layer.cornerRadius = 28

        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        scrollView.addSubview(contentStack)

        titleLabel.text = "Text Inspector"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white

        editTextButton.configuration = .borderedTinted()
        editTextButton.configuration?.title = "Edit Content"
        editTextButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.textInspectorViewDidRequestTextEdit(self)
        }, for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, UIView(), editTextButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        contentStack.addArrangedSubview(headerStack)

        fontButton.configuration = .bordered()
        fontButton.configuration?.title = "Font"
        fontButton.showsMenuAsPrimaryAction = true
        contentStack.addArrangedSubview(section(title: "Font Family", view: fontButton))

        weightControl.selectedSegmentIndex = 3
        weightControl.addAction(UIAction { [weak self] _ in
            self?.didChangeWeight()
        }, for: .valueChanged)
        contentStack.addArrangedSubview(section(title: "Weight", view: weightControl))

        alignmentControl.selectedSegmentIndex = 1
        alignmentControl.addAction(UIAction { [weak self] _ in
            self?.didChangeAlignment()
        }, for: .valueChanged)
        contentStack.addArrangedSubview(section(title: "Alignment", view: alignmentControl))

        let toggleStack = UIStackView(arrangedSubviews: [italicButton, shadowButton, outlineButton, backgroundButton])
        toggleStack.axis = .horizontal
        toggleStack.spacing = 10
        toggleStack.distribution = .fillEqually

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
        configureToggleButton(backgroundButton, title: "Fill") { [weak self] in
            guard let self else { return }
            self.delegate?.textInspectorView(self, didSetBackgroundFill: self.backgroundButton.isSelected)
        }
        contentStack.addArrangedSubview(section(title: "Style", view: toggleStack))

        colorStack.axis = .horizontal
        colorStack.spacing = 10
        colorStack.distribution = .fillEqually
        contentStack.addArrangedSubview(section(title: "Color", view: colorStack))

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

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds.insetBy(dx: 18, dy: 14)
        contentStack.frame = CGRect(origin: .zero, size: CGSize(width: scrollView.bounds.width, height: contentStack.systemLayoutSizeFitting(
            CGSize(width: scrollView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height))
        scrollView.contentSize = contentStack.bounds.size
    }

    func configure(fontFamilies: [String], palette: [CanvasColor]) {
        self.fontFamilies = fontFamilies
        self.palette = palette
        rebuildFontMenu()
        rebuildPalette()
    }

    func apply(node: CanvasNode) {
        guard let style = node.style else {
            return
        }

        isHidden = false
        isApplyingState = true
        defer { isApplyingState = false }

        fontButton.configuration?.title = style.fontFamily
        weightControl.selectedSegmentIndex = index(for: style.weight)
        alignmentControl.selectedSegmentIndex = index(for: style.alignment)
        italicButton.isSelected = style.isItalic
        shadowButton.isSelected = style.shadow != nil
        outlineButton.isSelected = style.outline != nil
        backgroundButton.isSelected = style.backgroundFill != nil

        [italicButton, shadowButton, outlineButton, backgroundButton].forEach(updateToggleButtonAppearance)

        fontSizeRow.value = style.fontSize
        letterSpacingRow.value = style.letterSpacing
        lineSpacingRow.value = style.lineSpacing
        opacityRow.value = style.opacity
        updatePaletteSelection(selected: style.foregroundColor)

        let isEmoji = node.kind == .emoji
        fontButton.isHidden = isEmoji
        weightControl.isHidden = isEmoji
        alignmentControl.isHidden = isEmoji
    }

    private func rebuildFontMenu() {
        fontButton.menu = UIMenu(children: fontFamilies.map { fontName in
            UIAction(title: fontName) { [weak self] _ in
                guard let self else { return }
                self.fontButton.configuration?.title = fontName
                self.delegate?.textInspectorView(self, didSelectFontFamily: fontName)
            }
        })
    }

    private func rebuildPalette() {
        colorStack.arrangedSubviews.forEach {
            colorStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        palette.enumerated().forEach { index, color in
            let button = UIButton(type: .system)
            button.tag = index
            button.backgroundColor = color.uiColor
            button.layer.cornerRadius = 16
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.clear.cgColor
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.updatePaletteSelection(selected: color)
                self.delegate?.textInspectorView(self, didSelectColor: color)
            }, for: .touchUpInside)
            colorStack.addArrangedSubview(button)
        }
    }

    private func updatePaletteSelection(selected: CanvasColor) {
        for (index, subview) in colorStack.arrangedSubviews.enumerated() {
            guard let button = subview as? UIButton else {
                continue
            }
            button.layer.borderColor = palette[index] == selected ? UIColor.white.cgColor : UIColor.clear.cgColor
        }
    }

    private func section(title: String, view: UIView) -> UIView {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.7)

        let stack = UIStackView(arrangedSubviews: [label, view])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func configureToggleButton(_ button: UIButton, title: String, action: @escaping () -> Void) {
        button.configuration = .bordered()
        button.configuration?.title = title
        button.addAction(UIAction { _ in
            button.isSelected.toggle()
            self.updateToggleButtonAppearance(button)
            action()
        }, for: .touchUpInside)
        updateToggleButtonAppearance(button)
    }

    private func updateToggleButtonAppearance(_ button: UIButton) {
        button.configuration?.baseForegroundColor = button.isSelected ? .black : .white
        button.configuration?.baseBackgroundColor = button.isSelected ? .white : UIColor.white.withAlphaComponent(0.08)
        button.configuration?.background.strokeColor = button.isSelected ? .clear : UIColor.white.withAlphaComponent(0.2)
    }

    private func didChangeWeight() {
        guard !isApplyingState else {
            return
        }
        let weight: CanvasFontWeight
        switch weightControl.selectedSegmentIndex {
        case 0:
            weight = .regular
        case 1:
            weight = .medium
        case 2:
            weight = .semibold
        case 4:
            weight = .heavy
        default:
            weight = .bold
        }
        delegate?.textInspectorView(self, didSelectWeight: weight)
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

    private func index(for weight: CanvasFontWeight) -> Int {
        switch weight {
        case .regular: 0
        case .medium: 1
        case .semibold: 2
        case .bold: 3
        case .heavy: 4
        }
    }

    private func index(for alignment: CanvasTextAlignment) -> Int {
        switch alignment {
        case .leading: 0
        case .center: 1
        case .trailing: 2
        }
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

        titleLabel.text = title.uppercased()
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.7)

        valueLabel.textColor = .white
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textAlignment = .right

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), valueLabel])
        header.axis = .horizontal

        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.18)
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
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
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
