import PhotosUI
import UIKit

protocol CanvasEditorViewControllerDelegate: AnyObject {
    func canvasEditorViewControllerDidCancel(_ viewController: CanvasEditorViewController)
    func canvasEditorViewController(
        _ viewController: CanvasEditorViewController,
        didExport result: CanvasEditorResult,
        previewImage: UIImage
    )
}

enum CanvasEditorInput {
    case template(CanvasTemplate)
    case project(CanvasProject)
}

final class CanvasEditorViewController: UIViewController, CanvasTextInspectorViewDelegate, PHPickerViewControllerDelegate, CanvasStageViewDelegate {
    weak var delegate: CanvasEditorViewControllerDelegate?

    let store: CanvasEditorStore

    private let stageView = CanvasStageView()
    private let bottomPanel = UIView()
    private let toolbarScrollView = UIScrollView()
    private let toolbarStack = UIStackView()
    private let inspectorContainerView = UIView()
    private let textInspectorView = CanvasTextInspectorView()

    private let toolbarHeight: CGFloat = 84
    private let inspectorExpandedHeight: CGFloat = 360
    private let inspectorFloatingOffset: CGFloat = -12
    private var inspectorBottomConstraint: NSLayoutConstraint?
    private var inspectorHeightConstraint: NSLayoutConstraint?
    private var isInspectorVisible = false
    private var isInspectorRequested = false
    private var isInlineEditingText = false
    private var lastSelectedNodeID: String?

    private var projectObserverID: UUID?
    private var selectionObserverID: UUID?

    private lazy var addTextButton = makeToolButton(title: "Text", systemImage: "textformat")
    private lazy var addEmojiButton = makeToolButton(title: "Emoji", systemImage: "face.smiling")
    private lazy var addStickerButton = makeToolButton(title: "Sticker", systemImage: "sparkles")
    private lazy var addPhotoButton = makeToolButton(title: "Photo", systemImage: "photo.on.rectangle")
    private lazy var addRemoteButton = makeToolButton(title: "URL", systemImage: "link")
    private lazy var frontButton = makeToolButton(title: "Front", systemImage: "square.3.layers.3d.top.filled")
    private lazy var backButton = makeToolButton(title: "Back", systemImage: "square.3.layers.3d.bottom.filled")
    private lazy var duplicateButton = makeToolButton(title: "Duplicate", systemImage: "plus.square.on.square")
    private lazy var deleteButton = makeToolButton(title: "Delete", systemImage: "trash")
    private lazy var undoButton = makeToolButton(title: "Undo", systemImage: "arrow.uturn.backward")
    private lazy var redoButton = makeToolButton(title: "Redo", systemImage: "arrow.uturn.forward")

    init(input: CanvasEditorInput, configuration: CanvasEditorConfiguration = .demo) {
        switch input {
        case .template(let template):
            self.store = CanvasEditorStore(template: template, configuration: configuration)
            super.init(nibName: nil, bundle: nil)
            title = template.name
        case .project(let project):
            self.store = CanvasEditorStore(project: project, configuration: configuration)
            super.init(nibName: nil, bundle: nil)
            title = "Resume Project"
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let projectObserverID {
            store.removeObserver(projectObserverID)
        }
        if let selectionObserverID {
            store.removeObserver(selectionObserverID)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1)

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Close",
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Export",
            style: .prominent,
            target: self,
            action: #selector(exportTapped)
        )

        stageView.store = store
        stageView.delegate = self
        textInspectorView.delegate = self
        textInspectorView.configure(fontFamilies: store.configuration.fontCatalog, palette: store.configuration.colorPalette)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        setupLayout()
        setupToolbar()
        bindStore()
        updateInspectorMetrics()
    }

    private func setupLayout() {
        [stageView, bottomPanel, inspectorContainerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        bottomPanel.backgroundColor = UIColor(red: 0.1, green: 0.11, blue: 0.15, alpha: 0.98)
        bottomPanel.layer.cornerRadius = 30
        bottomPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        inspectorContainerView.backgroundColor = .clear
        inspectorContainerView.alpha = 0

        toolbarScrollView.translatesAutoresizingMaskIntoConstraints = false
        toolbarScrollView.showsHorizontalScrollIndicator = false
        bottomPanel.addSubview(toolbarScrollView)

        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarStack.axis = .horizontal
        toolbarStack.spacing = 10
        toolbarScrollView.addSubview(toolbarStack)

        textInspectorView.translatesAutoresizingMaskIntoConstraints = false
        inspectorContainerView.addSubview(textInspectorView)

        inspectorBottomConstraint = inspectorContainerView.bottomAnchor.constraint(
            equalTo: bottomPanel.topAnchor,
            constant: inspectorExpandedHeight + 40
        )
        inspectorHeightConstraint = inspectorContainerView.heightAnchor.constraint(equalToConstant: inspectorExpandedHeight + view.safeAreaInsets.bottom)
        inspectorBottomConstraint?.isActive = true
        inspectorHeightConstraint?.isActive = true

        inspectorContainerView.layer.shadowColor = UIColor.black.cgColor
        inspectorContainerView.layer.shadowOpacity = 0.24
        inspectorContainerView.layer.shadowRadius = 18
        inspectorContainerView.layer.shadowOffset = CGSize(width: 0, height: -8)

        NSLayoutConstraint.activate([
            stageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stageView.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor),

            bottomPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            toolbarScrollView.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: 16),
            toolbarScrollView.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: -16),
            toolbarScrollView.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 12),
            toolbarScrollView.heightAnchor.constraint(equalToConstant: toolbarHeight),
            toolbarScrollView.bottomAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            toolbarStack.leadingAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.leadingAnchor),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.trailingAnchor),
            toolbarStack.topAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.topAnchor),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.bottomAnchor),
            toolbarStack.heightAnchor.constraint(equalTo: toolbarScrollView.frameLayoutGuide.heightAnchor),

            inspectorContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inspectorContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            textInspectorView.leadingAnchor.constraint(equalTo: inspectorContainerView.leadingAnchor),
            textInspectorView.trailingAnchor.constraint(equalTo: inspectorContainerView.trailingAnchor),
            textInspectorView.topAnchor.constraint(equalTo: inspectorContainerView.topAnchor),
            textInspectorView.bottomAnchor.constraint(equalTo: inspectorContainerView.bottomAnchor)
        ])
    }

    private func setupToolbar() {
        let toolbarItems: [(UIButton, Selector)] = [
            (addTextButton, #selector(addTextTapped)),
            (addEmojiButton, #selector(addEmojiTapped)),
            (addStickerButton, #selector(addStickerTapped)),
            (addPhotoButton, #selector(addPhotoTapped)),
            (addRemoteButton, #selector(addRemoteTapped)),
            (frontButton, #selector(frontTapped)),
            (backButton, #selector(backTapped)),
            (duplicateButton, #selector(duplicateTapped)),
            (deleteButton, #selector(deleteTapped)),
            (undoButton, #selector(undoTapped)),
            (redoButton, #selector(redoTapped))
        ]

        toolbarItems.forEach { button, action in
            button.addTarget(self, action: action, for: .touchUpInside)
            toolbarStack.addArrangedSubview(button)
        }
    }

    private func bindStore() {
        projectObserverID = store.observeProject { [weak self] _ in
            self?.refreshChrome()
        }
        selectionObserverID = store.observeSelection { [weak self] selectedNodeID in
            guard let self else { return }
            if selectedNodeID != self.lastSelectedNodeID {
                self.isInspectorRequested = false
            }
            if selectedNodeID == nil {
                self.isInlineEditingText = false
            }
            self.lastSelectedNodeID = selectedNodeID
            self.refreshChrome()
        }
    }

    private func refreshChrome() {
        let hasSelection = store.selectedNode != nil
        frontButton.isEnabled = hasSelection
        backButton.isEnabled = hasSelection
        duplicateButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        undoButton.isEnabled = store.canUndo
        redoButton.isEnabled = store.canRedo

        if let node = store.selectedNode, node.kind == .text || node.kind == .emoji {
            textInspectorView.apply(node: node)
            let shouldShowInspector = isInspectorRequested && !isInlineEditingText
            setInspectorVisible(shouldShowInspector, animated: true)
        } else {
            isInspectorRequested = false
            setInspectorVisible(false, animated: true)
        }
    }

    private func setInspectorVisible(_ visible: Bool, animated: Bool) {
        isInspectorVisible = visible
        updateInspectorMetrics()
        let changes = {
            self.inspectorContainerView.alpha = visible ? 1 : 0
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.24, animations: changes)
        } else {
            changes()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateInspectorMetrics()
    }

    private func updateInspectorMetrics() {
        let totalHeight = inspectorExpandedHeight + view.safeAreaInsets.bottom
        inspectorHeightConstraint?.constant = totalHeight
        inspectorBottomConstraint?.constant = isInspectorVisible ? inspectorFloatingOffset : totalHeight + 20
    }

    @objc
    private func handleKeyboardWillShow(_ notification: Notification) {
        guard isInlineEditingText || isInspectorVisible else {
            return
        }
        isInspectorRequested = false
        setInspectorVisible(false, animated: true)
    }

    private func makeToolButton(title: String, systemImage: String) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .tinted()
        button.configuration?.title = title
        button.configuration?.image = UIImage(systemName: systemImage)
        button.configuration?.imagePlacement = .top
        button.configuration?.imagePadding = 8
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        button.configuration?.baseForegroundColor = .white
        button.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        button.layer.cornerRadius = 22
        return button
    }

    private func applyTextStyleMutation(_ mutation: (inout CanvasTextStyle) -> Void) {
        store.updateSelectedTextStyle(mutation)
        stageView.ensureSelectedTextFitsHeight()
    }

    private func presentRemoteImagePrompt() {
        let alert = UIAlertController(title: "Insert Remote Image", message: "Paste an image URL.", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "https://example.com/image.png"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Insert", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            guard let url = alert?.textFields?.first?.text, !url.isEmpty else {
                return
            }
            self.importRemoteImage(from: url)
        })
        present(alert, animated: true)
    }

    private func presentEmojiPrompt() {
        let alert = UIAlertController(title: "Add Emoji", message: "Insert one emoji or a short sequence.", preferredStyle: .alert)
        alert.addTextField {
            $0.text = "✨"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let emoji = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.store.addEmojiNode(text: emoji?.isEmpty == false ? emoji! : "✨")
        })
        present(alert, animated: true)
    }

    private func presentStickerPicker() {
        let alert = UIAlertController(title: "Pick Sticker", message: nil, preferredStyle: .actionSheet)
        store.configuration.stickerCatalog.forEach { sticker in
            alert.addAction(UIAlertAction(title: sticker.name, style: .default) { [weak self] _ in
                self?.store.addStickerNode(source: sticker.source)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = addStickerButton
            popover.sourceRect = addStickerButton.bounds
        }
        present(alert, animated: true)
    }

    private func presentErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func importRemoteImage(from url: String) {
        let source = CanvasAssetSource.remoteURL(url)
        stageView.assetLoader.image(for: source) { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.presentErrorAlert(message: "Unable to load image from URL.")
                return
            }
            self.store.addImageNode(source: source, intrinsicSize: CanvasSize(image.size))
        }
    }

    func textInspectorViewDidRequestTextEdit(_ textInspectorView: CanvasTextInspectorView) {
        stageView.beginInlineEditingForSelectedNode()
    }

    func canvasStageViewDidTapSelectedTextNode(_ stageView: CanvasStageView) {
        guard let node = store.selectedNode, node.kind == .text || node.kind == .emoji, !isInlineEditingText else {
            return
        }
        isInspectorRequested.toggle()
        refreshChrome()
    }

    func canvasStageViewDidBeginInlineEditing(_ stageView: CanvasStageView) {
        isInlineEditingText = true
        isInspectorRequested = false
        setInspectorVisible(false, animated: true)
    }

    func canvasStageViewDidEndInlineEditing(_ stageView: CanvasStageView) {
        isInlineEditingText = false
        refreshChrome()
    }

    func canvasStageViewDidBeginNodeManipulation(_ stageView: CanvasStageView) {
        guard isInspectorRequested || isInspectorVisible else {
            return
        }
        isInspectorRequested = false
        setInspectorVisible(false, animated: true)
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectFontFamily fontFamily: String) {
        applyTextStyleMutation { $0.fontFamily = fontFamily }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectWeight weight: CanvasFontWeight) {
        applyTextStyleMutation { $0.weight = weight }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectAlignment alignment: CanvasTextAlignment) {
        applyTextStyleMutation { $0.alignment = alignment }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectColor color: CanvasColor) {
        applyTextStyleMutation { $0.foregroundColor = color }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetItalic isItalic: Bool) {
        applyTextStyleMutation { $0.isItalic = isItalic }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetShadow isEnabled: Bool) {
        applyTextStyleMutation {
            $0.shadow = isEnabled ? CanvasShadowStyle(color: .black, radius: 12, offsetX: 0, offsetY: 8) : nil
        }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetOutline isEnabled: Bool) {
        applyTextStyleMutation {
            $0.outline = isEnabled ? CanvasOutlineStyle(color: .black, width: 6) : nil
        }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSetBackgroundFill isEnabled: Bool) {
        applyTextStyleMutation {
            $0.backgroundFill = isEnabled ? CanvasFillStyle(color: .black) : nil
        }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeFontSize value: Double) {
        applyTextStyleMutation { $0.fontSize = value }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeLetterSpacing value: Double) {
        applyTextStyleMutation { $0.letterSpacing = value }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeLineSpacing value: Double) {
        applyTextStyleMutation { $0.lineSpacing = value }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didChangeOpacity value: Double) {
        applyTextStyleMutation { $0.opacity = value }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let result = results.first else {
            return
        }
        guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
            return
        }
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self, let image = object as? UIImage,
                  let source = self.stageView.assetLoader.inlineSource(
                    from: image,
                    maxDimension: CGFloat(self.store.configuration.exportMaxDimension)
                  ) else {
                return
            }
            DispatchQueue.main.async {
                self.store.addImageNode(source: source, intrinsicSize: CanvasSize(image.size))
            }
        }
    }

    @objc
    private func closeTapped() {
        delegate?.canvasEditorViewControllerDidCancel(self)
    }

    @objc
    private func exportTapped() {
        let image = CanvasEditorRenderer.render(project: store.project, assetLoader: stageView.assetLoader)
        guard let imageData = image.pngData() else {
            presentErrorAlert(message: "Unable to encode PNG.")
            return
        }

        do {
            let projectData = try store.encodedProjectData(prettyPrinted: true)
            delegate?.canvasEditorViewController(
                self,
                didExport: CanvasEditorResult(imageData: imageData, projectData: projectData),
                previewImage: image
            )
        } catch {
            presentErrorAlert(message: "Unable to encode project JSON.")
        }
    }

    @objc
    private func addTextTapped() {
        store.addTextNode()
        stageView.beginInlineEditingForSelectedNode(placeCursorAtEnd: false)
    }

    @objc
    private func addEmojiTapped() {
        presentEmojiPrompt()
    }

    @objc
    private func addStickerTapped() {
        presentStickerPicker()
    }

    @objc
    private func addPhotoTapped() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc
    private func addRemoteTapped() {
        presentRemoteImagePrompt()
    }

    @objc
    private func frontTapped() {
        store.bringSelectedNodeToFront()
    }

    @objc
    private func backTapped() {
        store.sendSelectedNodeToBack()
    }

    @objc
    private func duplicateTapped() {
        store.duplicateSelectedNode()
    }

    @objc
    private func deleteTapped() {
        store.deleteSelectedNode()
    }

    @objc
    private func undoTapped() {
        store.undo()
    }

    @objc
    private func redoTapped() {
        store.redo()
    }
}
