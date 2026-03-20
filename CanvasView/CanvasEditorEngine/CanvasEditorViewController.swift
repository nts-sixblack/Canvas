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

private enum CanvasEditorLoadingState {
    case none
    case importingImage
    case exportingImage

    var message: String {
        switch self {
        case .none:
            return ""
        case .importingImage:
            return "Importing image..."
        case .exportingImage:
            return "Exporting image..."
        }
    }
}

private enum CanvasEditorOperationError: Error {
    case pngEncodingFailed
}

final class CanvasEditorViewController: UIViewController, CanvasTextInspectorViewDelegate, PHPickerViewControllerDelegate, CanvasStageViewDelegate, CanvasLayerPanelViewDelegate {
    weak var delegate: CanvasEditorViewControllerDelegate?

    let store: CanvasEditorStore

    private let stageView = CanvasStageView()
    private let bottomPanel = UIView()
    private let toolbarScrollView = UIScrollView()
    private let toolbarStack = UIStackView()
    private let inspectorContainerView = UIView()
    private let textInspectorView = CanvasTextInspectorView()
    private let loadingOverlayView = CanvasLoadingOverlayView()
    private let layerPanelScrimView = UIControl()
    private let layerPanelView = CanvasLayerPanelView()

    private let toolbarHeight: CGFloat = 84
    private let inspectorExpandedHeight: CGFloat = 360
    private let inspectorFloatingOffset: CGFloat = -12
    private var inspectorBottomConstraint: NSLayoutConstraint?
    private var inspectorHeightConstraint: NSLayoutConstraint?
    private var layerPanelHeightConstraint: NSLayoutConstraint?
    private var isInspectorVisible = false
    private var isInspectorRequested = false
    private var isInlineEditingText = false
    private var isLayerPanelVisible = false
    private var lastSelectedNodeID: String?
    private var loadingState: CanvasEditorLoadingState = .none

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
    private lazy var exportBarButtonItem = UIBarButtonItem(
        title: "Export",
        style: .prominent,
        target: self,
        action: #selector(exportTapped)
    )
    private lazy var layersBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "square.stack.3d.up.fill"),
        style: .plain,
        target: self,
        action: #selector(layersTapped)
    )

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
        navigationItem.rightBarButtonItems = [exportBarButtonItem, layersBarButtonItem]

        stageView.store = store
        stageView.delegate = self
        textInspectorView.delegate = self
        textInspectorView.configure(fontFamilies: store.configuration.fontCatalog, palette: store.configuration.colorPalette)
        layerPanelView.delegate = self

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
        [stageView, bottomPanel, inspectorContainerView, layerPanelScrimView, layerPanelView, loadingOverlayView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        bottomPanel.backgroundColor = UIColor(red: 0.1, green: 0.11, blue: 0.15, alpha: 0.98)
        bottomPanel.layer.cornerRadius = 30
        bottomPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        inspectorContainerView.backgroundColor = .clear
        inspectorContainerView.alpha = 0

        layerPanelScrimView.backgroundColor = .clear
        layerPanelScrimView.alpha = 0
        layerPanelScrimView.isHidden = true
        layerPanelScrimView.addTarget(self, action: #selector(layerPanelBackdropTapped), for: .touchUpInside)

        layerPanelView.alpha = 0
        layerPanelView.isHidden = true
        layerPanelView.transform = layerPanelHiddenTransform
        layerPanelView.isUserInteractionEnabled = false

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
        layerPanelHeightConstraint = layerPanelView.heightAnchor.constraint(equalToConstant: 180)
        inspectorBottomConstraint?.isActive = true
        inspectorHeightConstraint?.isActive = true
        layerPanelHeightConstraint?.isActive = true

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
            textInspectorView.bottomAnchor.constraint(equalTo: inspectorContainerView.bottomAnchor),

            layerPanelScrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layerPanelScrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layerPanelScrimView.topAnchor.constraint(equalTo: view.topAnchor),
            layerPanelScrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            layerPanelView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            layerPanelView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            layerPanelView.widthAnchor.constraint(equalToConstant: 232),

            loadingOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
        layerPanelView.apply(nodes: store.layerPanelNodes, selectedNodeID: store.selectedNodeID)
        updateLayerPanelHeight()

        let hasSelection = store.selectedNode != nil
        frontButton.isEnabled = hasSelection
        backButton.isEnabled = hasSelection
        duplicateButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        undoButton.isEnabled = store.canUndo
        redoButton.isEnabled = store.canRedo
        updateLayerButtonAppearance()

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
        updateLayerPanelHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayerPanelHeight()
    }

    private func updateInspectorMetrics() {
        let totalHeight = inspectorExpandedHeight + view.safeAreaInsets.bottom
        inspectorHeightConstraint?.constant = totalHeight
        inspectorBottomConstraint?.constant = isInspectorVisible ? inspectorFloatingOffset : totalHeight + 20
    }

    private func setLoadingState(_ state: CanvasEditorLoadingState, animated: Bool = true) {
        loadingState = state
        let isBusy = state != .none
        stageView.isUserInteractionEnabled = !isBusy
        bottomPanel.isUserInteractionEnabled = !isBusy
        inspectorContainerView.isUserInteractionEnabled = !isBusy
        navigationItem.leftBarButtonItem?.isEnabled = !isBusy
        exportBarButtonItem.isEnabled = !isBusy
        layersBarButtonItem.isEnabled = !isBusy
        layerPanelView.isUserInteractionEnabled = !isBusy && isLayerPanelVisible

        if isBusy {
            setLayerPanelVisible(false, animated: animated)
        }

        if isBusy {
            loadingOverlayView.show(message: state.message, animated: animated)
        } else {
            loadingOverlayView.hide(animated: animated)
        }
    }

    private static func encodeProjectData(for project: CanvasProject, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(project)
    }

    @objc
    private func handleKeyboardWillShow(_ notification: Notification) {
        guard isInlineEditingText || isInspectorVisible else {
            return
        }
        isInspectorRequested = false
        setInspectorVisible(false, animated: true)
    }

    private func updateLayerPanelHeight() {
        let maximumHeight = min(max(view.bounds.height - view.safeAreaInsets.top - 44, 220), 420)
        layerPanelHeightConstraint?.constant = layerPanelView.preferredHeight(maximumHeight: maximumHeight)
    }

    private func updateLayerButtonAppearance() {
        layersBarButtonItem.tintColor = isLayerPanelVisible
            ? UIColor(red: 0.47, green: 0.85, blue: 1, alpha: 1)
            : .white
    }

    private func setLayerPanelVisible(_ visible: Bool, animated: Bool) {
        guard isLayerPanelVisible != visible || layerPanelView.isHidden != !visible else {
            return
        }

        isLayerPanelVisible = visible
        updateLayerButtonAppearance()

        if visible {
            layerPanelScrimView.isHidden = false
            layerPanelView.isHidden = false
            layerPanelView.isUserInteractionEnabled = loadingState == .none
            view.bringSubviewToFront(layerPanelScrimView)
            view.bringSubviewToFront(layerPanelView)
            view.bringSubviewToFront(loadingOverlayView)
        }

        let changes = {
            self.layerPanelScrimView.alpha = visible ? 1 : 0
            self.layerPanelScrimView.backgroundColor = UIColor.black.withAlphaComponent(visible ? 0.16 : 0)
            self.layerPanelView.alpha = visible ? 1 : 0
            self.layerPanelView.transform = visible ? .identity : self.layerPanelHiddenTransform
        }

        let completion: (Bool) -> Void = { _ in
            if !visible {
                self.layerPanelScrimView.isHidden = true
                self.layerPanelView.isHidden = true
                self.layerPanelView.isUserInteractionEnabled = false
            }
        }

        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut], animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    private var layerPanelHiddenTransform: CGAffineTransform {
        CGAffineTransform(translationX: 26, y: -8)
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

    func canvasLayerPanelView(_ layerPanelView: CanvasLayerPanelView, didSelectNodeID nodeID: String) {
        store.selectNode(nodeID)
    }

    func canvasLayerPanelView(_ layerPanelView: CanvasLayerPanelView, didToggleLockForNodeID nodeID: String) {
        store.toggleNodeLock(nodeID)
    }

    func canvasLayerPanelView(_ layerPanelView: CanvasLayerPanelView, moveNodeFrom sourceIndex: Int, to destinationIndex: Int) {
        store.moveNodeInLayerPanel(from: sourceIndex, to: destinationIndex)
    }

    private func importRemoteImage(from url: String) {
        setLoadingState(.importingImage)
        let source = CanvasAssetSource.remoteURL(url)
        stageView.assetLoader.image(for: source) { [weak self] image in
            guard let self else { return }
            self.setLoadingState(.none)
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
        setLoadingState(.importingImage)
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self else {
                return
            }

            guard let image = object as? UIImage,
                  let source = self.stageView.assetLoader.inlineSource(
                    from: image,
                    maxDimension: CGFloat(self.store.configuration.exportMaxDimension)
                  ) else {
                DispatchQueue.main.async {
                    self.setLoadingState(.none)
                    self.presentErrorAlert(message: "Unable to import the selected image.")
                }
                return
            }

            DispatchQueue.main.async {
                self.setLoadingState(.none)
                self.store.addImageNode(source: source, intrinsicSize: CanvasSize(image.size))
            }
        }
    }

    @objc
    private func closeTapped() {
        delegate?.canvasEditorViewControllerDidCancel(self)
    }

    @objc
    private func layersTapped() {
        setLayerPanelVisible(!isLayerPanelVisible, animated: true)
    }

    @objc
    private func layerPanelBackdropTapped() {
        setLayerPanelVisible(false, animated: true)
    }

    @objc
    private func exportTapped() {
        let project = store.project
        let assetLoader = stageView.assetLoader
        setLoadingState(.exportingImage)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let result: Result<(CanvasEditorResult, UIImage), Error> = autoreleasepool {
                let image = CanvasEditorRenderer.render(project: project, assetLoader: assetLoader)
                guard let imageData = image.pngData() else {
                    return .failure(CanvasEditorOperationError.pngEncodingFailed)
                }

                do {
                    let projectData = try Self.encodeProjectData(for: project, prettyPrinted: false)
                    return .success((CanvasEditorResult(imageData: imageData, projectData: projectData), image))
                } catch {
                    return .failure(error)
                }
            }

            DispatchQueue.main.async {
                self.setLoadingState(.none)

                switch result {
                case .success(let payload):
                    self.delegate?.canvasEditorViewController(
                        self,
                        didExport: payload.0,
                        previewImage: payload.1
                    )
                case .failure(let error):
                    let message = (error as? CanvasEditorOperationError) == .pngEncodingFailed
                        ? "Unable to encode PNG."
                        : "Unable to encode project JSON."
                    self.presentErrorAlert(message: message)
                }
            }
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

protocol CanvasLayerPanelViewDelegate: AnyObject {
    func canvasLayerPanelView(_ layerPanelView: CanvasLayerPanelView, didSelectNodeID nodeID: String)
    func canvasLayerPanelView(_ layerPanelView: CanvasLayerPanelView, didToggleLockForNodeID nodeID: String)
    func canvasLayerPanelView(_ layerPanelView: CanvasLayerPanelView, moveNodeFrom sourceIndex: Int, to destinationIndex: Int)
}

final class CanvasLayerPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
    weak var delegate: CanvasLayerPanelViewDelegate?

    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    private var nodes: [CanvasNode] = []
    private var selectedNodeID: String?

    private let headerHeight: CGFloat = 52
    private let rowHeight: CGFloat = 56
    private let bottomInset: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 0.98)
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 12)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Layers"
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        addSubview(titleLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = rowHeight
        tableView.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: bottomInset, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(CanvasLayerPanelCell.self, forCellReuseIdentifier: CanvasLayerPanelCell.reuseIdentifier)
        tableView.allowsSelection = true
        tableView.allowsSelectionDuringEditing = true
        tableView.setEditing(true, animated: false)
        addSubview(tableView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            tableView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(nodes: [CanvasNode], selectedNodeID: String?) {
        self.nodes = nodes
        self.selectedNodeID = selectedNodeID
        tableView.reloadData()

        if let selectedNodeID,
           let selectedIndex = nodes.firstIndex(where: { $0.id == selectedNodeID }) {
            tableView.selectRow(at: IndexPath(row: selectedIndex, section: 0), animated: false, scrollPosition: .none)
        } else if let selectedIndexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectedIndexPath, animated: false)
        }
    }

    func preferredHeight(maximumHeight: CGFloat) -> CGFloat {
        let contentHeight = headerHeight + (CGFloat(nodes.count) * rowHeight) + bottomInset + 8
        return min(maximumHeight, max(contentHeight, 124))
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        nodes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: CanvasLayerPanelCell.reuseIdentifier,
            for: indexPath
        ) as? CanvasLayerPanelCell else {
            return UITableViewCell()
        }

        let node = nodes[indexPath.row]
        cell.configure(node: node, isSelectedInPanel: node.id == selectedNodeID)
        cell.onToggleLock = { [weak self] in
            guard let self else { return }
            self.delegate?.canvasLayerPanelView(self, didToggleLockForNodeID: node.id)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        nodes[indexPath.row].isEditable
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        nodes[indexPath.row].isEditable ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.canvasLayerPanelView(self, didSelectNodeID: nodes[indexPath.row].id)
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        let safeRow = min(max(proposedDestinationIndexPath.row, 0), max(nodes.count - 1, 0))
        return IndexPath(row: safeRow, section: 0)
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let movingNode = nodes.remove(at: sourceIndexPath.row)
        nodes.insert(movingNode, at: destinationIndexPath.row)
        delegate?.canvasLayerPanelView(self, moveNodeFrom: sourceIndexPath.row, to: destinationIndexPath.row)
    }
}

final class CanvasLayerPanelCell: UITableViewCell {
    static let reuseIdentifier = "CanvasLayerPanelCell"

    var onToggleLock: (() -> Void)?

    private let rowBackgroundView = UIView()
    private let previewContainerView = UIView()
    private let previewLabel = UILabel()
    private let previewImageView = UIImageView()
    private let titleLabel = UILabel()
    private let lockButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        rowBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        rowBackgroundView.layer.cornerRadius = 16
        rowBackgroundView.layer.cornerCurve = .continuous
        contentView.addSubview(rowBackgroundView)

        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        previewContainerView.layer.cornerRadius = 10
        previewContainerView.layer.cornerCurve = .continuous
        previewContainerView.clipsToBounds = true
        rowBackgroundView.addSubview(previewContainerView)

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        previewLabel.textAlignment = .center
        previewContainerView.addSubview(previewLabel)

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFit
        previewContainerView.addSubview(previewImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        rowBackgroundView.addSubview(titleLabel)

        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.tintColor = .white
        lockButton.addAction(UIAction { [weak self] _ in
            self?.onToggleLock?()
        }, for: .touchUpInside)
        rowBackgroundView.addSubview(lockButton)

        NSLayoutConstraint.activate([
            rowBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            rowBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            rowBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            rowBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),

            previewContainerView.leadingAnchor.constraint(equalTo: rowBackgroundView.leadingAnchor, constant: 10),
            previewContainerView.centerYAnchor.constraint(equalTo: rowBackgroundView.centerYAnchor),
            previewContainerView.widthAnchor.constraint(equalToConstant: 30),
            previewContainerView.heightAnchor.constraint(equalToConstant: 30),

            previewLabel.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 4),
            previewLabel.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -4),
            previewLabel.topAnchor.constraint(equalTo: previewContainerView.topAnchor, constant: 2),
            previewLabel.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor, constant: -2),

            previewImageView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 6),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -6),
            previewImageView.topAnchor.constraint(equalTo: previewContainerView.topAnchor, constant: 6),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor, constant: -6),

            titleLabel.leadingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: rowBackgroundView.centerYAnchor),

            lockButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            lockButton.trailingAnchor.constraint(equalTo: rowBackgroundView.trailingAnchor, constant: -30),
            lockButton.centerYAnchor.constraint(equalTo: rowBackgroundView.centerYAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: 28),
            lockButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggleLock = nil
    }

    func configure(node: CanvasNode, isSelectedInPanel: Bool) {
        let isLocked = !node.isEditable
        rowBackgroundView.backgroundColor = UIColor.white.withAlphaComponent(isSelectedInPanel ? 0.18 : 0.08)
        rowBackgroundView.alpha = isLocked ? 0.58 : 1
        titleLabel.text = Self.displayTitle(for: node)
        titleLabel.textColor = .white
        lockButton.setImage(UIImage(systemName: isLocked ? "lock.fill" : "lock.open"), for: .normal)
        lockButton.tintColor = isLocked ? UIColor(red: 1, green: 0.8, blue: 0.82, alpha: 1) : UIColor.white.withAlphaComponent(0.78)

        previewContainerView.backgroundColor = Self.previewBackground(for: node)
        previewLabel.isHidden = false
        previewImageView.isHidden = true

        switch node.kind {
        case .text:
            previewLabel.text = "T"
            previewLabel.textColor = node.style?.foregroundColor.uiColor ?? .white
        case .emoji:
            previewLabel.text = String((node.text ?? "🙂").prefix(1))
            previewLabel.textColor = .white
        case .sticker:
            previewImageView.isHidden = false
            previewLabel.isHidden = true
            previewImageView.image = UIImage(systemName: node.source?.name ?? "sparkles")
            previewImageView.tintColor = node.style?.foregroundColor.uiColor ?? .white
        case .image:
            previewImageView.isHidden = false
            previewLabel.isHidden = true
            previewImageView.image = UIImage(systemName: "photo")
            previewImageView.tintColor = .white
        }
    }

    private static func displayTitle(for node: CanvasNode) -> String {
        if let name = node.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        if let text = node.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return String(text.prefix(18))
        }

        switch node.kind {
        case .text:
            return "Text"
        case .emoji:
            return "Emoji"
        case .sticker:
            return "Sticker"
        case .image:
            return "Image"
        }
    }

    private static func previewBackground(for node: CanvasNode) -> UIColor {
        switch node.kind {
        case .text:
            return UIColor(red: 0.99, green: 0.45, blue: 0.36, alpha: 0.28)
        case .emoji:
            return UIColor(red: 0.95, green: 0.73, blue: 0.24, alpha: 0.3)
        case .sticker:
            return UIColor(red: 0.49, green: 0.79, blue: 1, alpha: 0.28)
        case .image:
            return UIColor.white.withAlphaComponent(0.18)
        }
    }
}
