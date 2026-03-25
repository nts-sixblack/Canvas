import UIKit

enum CanvasInsertPickerMode {
    case emoji
    case sticker

    var title: String {
        switch self {
        case .emoji:
            return "Emoji"
        case .sticker:
            return "Sticker"
        }
    }

    var gridColumnCount: Int {
        switch self {
        case .emoji:
            return 5
        case .sticker:
            return 3
        }
    }

    var previewFontSize: CGFloat {
        switch self {
        case .emoji:
            return 34
        case .sticker:
            return 24
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .emoji:
            return "No emoji available."
        case .sticker:
            return "No sticker available."
        }
    }
}

struct CanvasInsertPickerItem: Hashable, Identifiable {
    enum Preview: Hashable {
        case emoji(String)
        case asset(CanvasAssetSource)
    }

    let id: String
    let title: String
    let preview: Preview
}

final class CanvasInsertPickerSheetViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let mode: CanvasInsertPickerMode
    private let items: [CanvasInsertPickerItem]
    private let assetLoader: CanvasAssetLoader
    private let onConfirm: ([CanvasInsertPickerItem]) -> Void
    private let itemsByID: [String: CanvasInsertPickerItem]

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 14
        layout.minimumInteritemSpacing = 12

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        collectionView.register(CanvasInsertPickerCell.self, forCellWithReuseIdentifier: CanvasInsertPickerCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        return collectionView
    }()

    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let dividerView = UIView()
    private let footerContainer = UIView()
    private let selectedTitleLabel = UILabel()
    private let selectedScrollView = UIScrollView()
    private let selectedStackView = UIStackView()
    private let emptySelectionLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let emptyStateLabel = UILabel()

    private var selectedItemIDs: [String] = [] {
        didSet {
            updateSelectionUI()
        }
    }

    init(
        mode: CanvasInsertPickerMode,
        items: [CanvasInsertPickerItem],
        assetLoader: CanvasAssetLoader,
        onConfirm: @escaping ([CanvasInsertPickerItem]) -> Void
    ) {
        self.mode = mode
        self.items = items
        self.assetLoader = assetLoader
        self.onConfirm = onConfirm
        self.itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheetPresentation()
        setupLayout()
        updateSelectionUI()
    }

    private func configureSheetPresentation() {
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)

        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 28
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
    }

    private func setupLayout() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = .systemRed
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        titleLabel.textColor = UIColor(red: 0.29, green: 0.31, blue: 0.38, alpha: 1)
        titleLabel.text = mode.title

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.backgroundColor = UIColor.black.withAlphaComponent(0.08)

        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.backgroundColor = view.backgroundColor

        selectedTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        selectedTitleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        selectedTitleLabel.textColor = UIColor(red: 0.23, green: 0.25, blue: 0.31, alpha: 1)

        selectedScrollView.translatesAutoresizingMaskIntoConstraints = false
        selectedScrollView.showsHorizontalScrollIndicator = false

        selectedStackView.translatesAutoresizingMaskIntoConstraints = false
        selectedStackView.axis = .horizontal
        selectedStackView.spacing = 10
        selectedScrollView.addSubview(selectedStackView)

        emptySelectionLabel.translatesAutoresizingMaskIntoConstraints = false
        emptySelectionLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        emptySelectionLabel.textColor = UIColor(red: 0.48, green: 0.5, blue: 0.56, alpha: 1)
        emptySelectionLabel.text = "Tap to select."

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.configuration = {
            var configuration = UIButton.Configuration.filled()
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = UIColor(red: 0.97, green: 0.3, blue: 0.28, alpha: 1)
            configuration.baseForegroundColor = .white
            configuration.title = "Add"
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
            return configuration
        }()
        addButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        emptyStateLabel.textColor = UIColor(red: 0.48, green: 0.5, blue: 0.56, alpha: 1)
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.text = mode.emptyStateMessage
        emptyStateLabel.isHidden = !items.isEmpty

        [closeButton, titleLabel, collectionView, emptyStateLabel, dividerView, footerContainer].forEach(view.addSubview)
        [selectedTitleLabel, selectedScrollView, emptySelectionLabel, addButton].forEach(footerContainer.addSubview)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            collectionView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 18),
            collectionView.bottomAnchor.constraint(equalTo: dividerView.topAnchor, constant: -12),

            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            emptyStateLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            dividerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dividerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 1),
            dividerView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor),

            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            selectedTitleLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            selectedTitleLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            selectedTitleLabel.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 14),

            selectedScrollView.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            selectedScrollView.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            selectedScrollView.topAnchor.constraint(equalTo: selectedTitleLabel.bottomAnchor, constant: 10),
            selectedScrollView.heightAnchor.constraint(equalToConstant: 58),

            selectedStackView.leadingAnchor.constraint(equalTo: selectedScrollView.contentLayoutGuide.leadingAnchor),
            selectedStackView.trailingAnchor.constraint(equalTo: selectedScrollView.contentLayoutGuide.trailingAnchor),
            selectedStackView.topAnchor.constraint(equalTo: selectedScrollView.contentLayoutGuide.topAnchor),
            selectedStackView.bottomAnchor.constraint(equalTo: selectedScrollView.contentLayoutGuide.bottomAnchor),
            selectedStackView.heightAnchor.constraint(equalTo: selectedScrollView.frameLayoutGuide.heightAnchor),

            emptySelectionLabel.leadingAnchor.constraint(equalTo: selectedScrollView.leadingAnchor),
            emptySelectionLabel.centerYAnchor.constraint(equalTo: selectedScrollView.centerYAnchor),

            addButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            addButton.topAnchor.constraint(equalTo: selectedScrollView.bottomAnchor, constant: 14),
            addButton.heightAnchor.constraint(equalToConstant: 52),
            addButton.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor, constant: -16)
        ])
    }

    private func selectedItems() -> [CanvasInsertPickerItem] {
        selectedItemIDs.compactMap { itemsByID[$0] }
    }

    private func updateSelectionUI() {
        selectedTitleLabel.text = selectedItemIDs.isEmpty ? "Selected" : "Selected (\(selectedItemIDs.count))"
        emptySelectionLabel.isHidden = !selectedItemIDs.isEmpty

        var configuration = addButton.configuration
        configuration?.title = selectedItemIDs.isEmpty ? "Add" : "Add \(selectedItemIDs.count)"
        addButton.configuration = configuration
        addButton.isEnabled = !selectedItemIDs.isEmpty
        addButton.alpha = selectedItemIDs.isEmpty ? 0.55 : 1

        selectedStackView.arrangedSubviews.forEach { subview in
            selectedStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        selectedItems().forEach { item in
            selectedStackView.addArrangedSubview(makeSelectedItemButton(for: item))
        }

        emptyStateLabel.isHidden = !items.isEmpty
        collectionView.isHidden = items.isEmpty
    }

    private func makeSelectedItemButton(for item: CanvasInsertPickerItem) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 58).isActive = true
        button.heightAnchor.constraint(equalToConstant: 58).isActive = true
        button.backgroundColor = UIColor.white.withAlphaComponent(0.82)
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.18).cgColor
        button.layer.borderWidth = 1
        button.clipsToBounds = true
        button.tintColor = UIColor(red: 0.23, green: 0.25, blue: 0.31, alpha: 1)
        button.accessibilityIdentifier = item.id
        button.addAction(UIAction { [weak self] _ in
            self?.toggleSelection(for: item.id)
        }, for: .touchUpInside)

        switch item.preview {
        case .emoji(let emoji):
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 28)
            button.setTitleColor(.label, for: .normal)

        case .asset(let source):
            button.setImage(assetLoader.imageSynchronously(for: source), for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            assetLoader.image(for: source) { [weak button] image in
                guard button?.accessibilityIdentifier == item.id else {
                    return
                }
                button?.setImage(image, for: .normal)
            }
        }

        return button
    }

    private func toggleSelection(for itemID: String) {
        if let index = selectedItemIDs.firstIndex(of: itemID) {
            selectedItemIDs.remove(at: index)
        } else {
            selectedItemIDs.append(itemID)
        }

        if let itemIndex = items.firstIndex(where: { $0.id == itemID }) {
            collectionView.reloadItems(at: [IndexPath(item: itemIndex, section: 0)])
        }
    }

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }

    @objc
    private func addTapped() {
        let itemsToInsert = selectedItems()
        guard !itemsToInsert.isEmpty else {
            return
        }

        dismiss(animated: true) { [onConfirm] in
            onConfirm(itemsToInsert)
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CanvasInsertPickerCell.reuseIdentifier,
            for: indexPath
        ) as? CanvasInsertPickerCell else {
            return UICollectionViewCell()
        }

        let item = items[indexPath.item]
        cell.configure(
            with: item,
            mode: mode,
            assetLoader: assetLoader,
            isPicked: selectedItemIDs.contains(item.id)
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        toggleSelection(for: items[indexPath.item].id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let columns = CGFloat(mode.gridColumnCount)
        let spacing: CGFloat = 12
        let availableWidth = collectionView.bounds.width - (spacing * (columns - 1))
        let side = floor(availableWidth / columns)
        return CGSize(width: side, height: side)
    }
}

private final class CanvasInsertPickerCell: UICollectionViewCell {
    static let reuseIdentifier = "CanvasInsertPickerCell"

    private let tileView = UIView()
    private let emojiLabel = UILabel()
    private let imageView = UIImageView()
    private let pickedBadgeView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private var representedItemID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .clear

        tileView.translatesAutoresizingMaskIntoConstraints = false
        tileView.layer.cornerRadius = 20
        tileView.layer.cornerCurve = .continuous
        tileView.clipsToBounds = true
        contentView.addSubview(tileView)

        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.textAlignment = .center
        tileView.addSubview(emojiLabel)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        tileView.addSubview(imageView)

        pickedBadgeView.translatesAutoresizingMaskIntoConstraints = false
        pickedBadgeView.tintColor = .systemRed
        pickedBadgeView.isHidden = true
        contentView.addSubview(pickedBadgeView)

        NSLayoutConstraint.activate([
            tileView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tileView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tileView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tileView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            emojiLabel.leadingAnchor.constraint(equalTo: tileView.leadingAnchor, constant: 6),
            emojiLabel.trailingAnchor.constraint(equalTo: tileView.trailingAnchor, constant: -6),
            emojiLabel.centerYAnchor.constraint(equalTo: tileView.centerYAnchor),

            imageView.leadingAnchor.constraint(equalTo: tileView.leadingAnchor, constant: 10),
            imageView.trailingAnchor.constraint(equalTo: tileView.trailingAnchor, constant: -10),
            imageView.topAnchor.constraint(equalTo: tileView.topAnchor, constant: 10),
            imageView.bottomAnchor.constraint(equalTo: tileView.bottomAnchor, constant: -10),

            pickedBadgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            pickedBadgeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            pickedBadgeView.widthAnchor.constraint(equalToConstant: 22),
            pickedBadgeView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedItemID = nil
        emojiLabel.text = nil
        emojiLabel.isHidden = true
        imageView.image = nil
        imageView.isHidden = true
        pickedBadgeView.isHidden = true
    }

    func configure(
        with item: CanvasInsertPickerItem,
        mode: CanvasInsertPickerMode,
        assetLoader: CanvasAssetLoader,
        isPicked: Bool
    ) {
        representedItemID = item.id
        pickedBadgeView.isHidden = !isPicked
        tileView.backgroundColor = isPicked
            ? UIColor.systemRed.withAlphaComponent(0.1)
            : UIColor.white.withAlphaComponent(0.74)
        tileView.layer.borderColor = isPicked
            ? UIColor.systemRed.cgColor
            : UIColor.clear.cgColor
        tileView.layer.borderWidth = isPicked ? 2 : 0

        switch item.preview {
        case .emoji(let emoji):
            emojiLabel.isHidden = false
            imageView.isHidden = true
            emojiLabel.font = UIFont.systemFont(ofSize: mode.previewFontSize)
            emojiLabel.text = emoji

        case .asset(let source):
            emojiLabel.isHidden = true
            imageView.isHidden = false
            imageView.image = assetLoader.imageSynchronously(for: source)
            assetLoader.image(for: source) { [weak self] image in
                guard let self, self.representedItemID == item.id else {
                    return
                }
                self.imageView.image = image
            }
        }
    }
}

enum CanvasInsertPickerCatalog {
    static let emojiItems: [CanvasInsertPickerItem] = [
        "😁", "😀", "😄", "😊", "☺️",
        "😉", "😍", "😘", "😚", "😗",
        "😙", "😜", "😝", "😛", "😳",
        "😌", "😔", "😒", "😕", "😟",
        "😣", "😭", "😂", "😢", "😥",
        "😰", "😅", "😓", "😩", "😫",
        "😨", "😱", "😠", "😡", "😤",
        "😖", "😆", "😷", "😴", "😵",
        "😲", "😮", "😈", "👿", "😦"
    ].enumerated().map { index, emoji in
        CanvasInsertPickerItem(
            id: "emoji-\(index)",
            title: emoji,
            preview: .emoji(emoji)
        )
    }

    static func stickerItems(from descriptors: [CanvasStickerDescriptor]) -> [CanvasInsertPickerItem] {
        if descriptors.isEmpty {
            return fallbackStickerItems()
        }

        return descriptors.enumerated().map { index, descriptor in
            let displaySource = renderedStickerSource(from: descriptor.source, paletteIndex: index) ?? descriptor.source
            return CanvasInsertPickerItem(
                id: descriptor.id,
                title: descriptor.name,
                preview: .asset(displaySource)
            )
        }
    }

    private static func fallbackStickerItems() -> [CanvasInsertPickerItem] {
        [
            ("sticker-sparkles", "Sparkles", "sparkles"),
            ("sticker-star", "Star", "star.fill"),
            ("sticker-heart", "Heart", "heart.fill"),
            ("sticker-flash", "Flash", "bolt.fill"),
            ("sticker-moon", "Moon", "moon.stars.fill"),
            ("sticker-sun", "Sun", "sun.max.fill")
        ].enumerated().compactMap { index, item in
            guard let source = renderedSymbolStickerSource(
                named: item.2,
                tintColor: stickerPalette[index % stickerPalette.count]
            ) else {
                return nil
            }
            return CanvasInsertPickerItem(id: item.0, title: item.1, preview: .asset(source))
        }
    }

    private static func renderedStickerSource(from source: CanvasAssetSource, paletteIndex: Int) -> CanvasAssetSource? {
        guard source.kind == .symbol, let symbolName = source.name else {
            return nil
        }
        return renderedSymbolStickerSource(
            named: symbolName,
            tintColor: stickerPalette[paletteIndex % stickerPalette.count]
        )
    }

    private static func renderedSymbolStickerSource(named symbolName: String, tintColor: UIColor) -> CanvasAssetSource? {
        let size = CGSize(width: 220, height: 220)
        let configuration = UIImage.SymbolConfiguration(pointSize: 156, weight: .bold)
        guard let symbol = UIImage(systemName: symbolName, withConfiguration: configuration) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(x: 32, y: 32, width: 156, height: 156)
            let shadowImage = symbol.withTintColor(UIColor.black.withAlphaComponent(0.14), renderingMode: .alwaysOriginal)
            shadowImage.draw(in: rect.offsetBy(dx: 0, dy: 8))

            let tintedImage = symbol.withTintColor(tintColor, renderingMode: .alwaysOriginal)
            tintedImage.draw(in: rect)
        }

        guard let data = image.pngData() else {
            return nil
        }
        return .inlineImage(data: data)
    }
    private static let stickerPalette: [UIColor] = [
        UIColor(red: 0.95, green: 0.37, blue: 0.21, alpha: 1),
        UIColor(red: 0.96, green: 0.61, blue: 0.16, alpha: 1),
        UIColor(red: 0.2, green: 0.72, blue: 0.65, alpha: 1),
        UIColor(red: 0.31, green: 0.54, blue: 0.95, alpha: 1),
        UIColor(red: 0.83, green: 0.35, blue: 0.66, alpha: 1)
    ]
}
