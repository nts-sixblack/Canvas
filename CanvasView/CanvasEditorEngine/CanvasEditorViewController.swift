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

private enum BrushInspectorMode {
    case create
    case edit
}

private enum VisibleInspectorKind {
    case none
    case text
    case brush
}

final class CanvasEditorViewController: UIViewController, CanvasTextInspectorViewDelegate, CanvasBrushInspectorViewDelegate, PHPickerViewControllerDelegate, UIColorPickerViewControllerDelegate, CanvasStageViewDelegate, CanvasLayerPanelViewDelegate {
    weak var delegate: CanvasEditorViewControllerDelegate?

    let store: CanvasEditorStore

    private let stageView = CanvasStageView()
    private let bottomPanel = UIView()
    private let historyActionsContainer = UIView()
    private let historyActionsStack = UIStackView()
    private let toolbarGridStack = UIStackView()
    private let panelScrimView = UIControl()
    private let inspectorContainerView = UIView()
    private let textInspectorView = CanvasTextInspectorView()
    private let brushInspectorView = CanvasBrushInspectorView()
    private let loadingOverlayView = CanvasLoadingOverlayView()
    private let layerPanelView = CanvasLayerPanelView()

    private let toolbarTileHeight: CGFloat = 82
    private let historyButtonSize: CGFloat = 58
    private let inspectorMaximumHeight: CGFloat = 360
    private let inspectorMinimumTopMargin: CGFloat = 44
    private let inspectorVisibleOffset: CGFloat = 0
    private var inspectorBottomConstraint: NSLayoutConstraint?
    private var inspectorHeightConstraint: NSLayoutConstraint?
    private var layerPanelHeightConstraint: NSLayoutConstraint?
    private var isInspectorVisible = false
    private var isInspectorRequested = false
    private var brushInspectorMode: BrushInspectorMode?
    private var isInlineEditingText = false
    private var isLayerPanelVisible = false
    private var lastSelectedNodeID: String?
    private var loadingState: CanvasEditorLoadingState = .none
    private var currentVisibleInspectorKind: VisibleInspectorKind = .none
    private var activeTextColorPickerTarget: CanvasTextInspectorColorTarget?
    private var committedBrushConfiguration = CanvasBrushConfiguration.defaultValue {
        didSet {
            guard isViewLoaded else {
                return
            }
            updateBrushButtonAppearance()
        }
    }
    private var brushDraftConfiguration: CanvasBrushConfiguration?
    private var eraserStrokeWidth: Double = 24
    private var isBrushModeEnabled = false
    private var isEraserModeEnabled = false

    private var projectObserverID: UUID?
    private var selectionObserverID: UUID?

    private lazy var addTextButton = makeGridToolButton(title: "Text", systemImage: "textformat")
    private lazy var addEmojiButton = makeGridToolButton(title: "Emoji", systemImage: "face.smiling")
    private lazy var addStickerButton = makeGridToolButton(title: "Sticker", systemImage: "sparkles")
    private lazy var addPhotoButton = makeGridToolButton(title: "Photo", systemImage: "photo.on.rectangle")
    private lazy var eraserButton = makeGridToolButton(title: "Eraser", systemImage: "eraser")
    private lazy var addBrushButton = makeGridToolButton(title: "Brush", systemImage: "paintbrush")
    private lazy var duplicateButton = makeGridToolButton(title: "Duplicate", systemImage: "plus.square.on.square")
    private lazy var deleteButton = makeGridToolButton(title: "Delete", systemImage: "trash")
    private lazy var undoButton = makeHistoryButton(title: "Undo", systemImage: "arrow.uturn.backward")
    private lazy var redoButton = makeHistoryButton(title: "Redo", systemImage: "arrow.uturn.forward")
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
        view.backgroundColor = CanvasEditorTheme.canvasBackdrop

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
        brushInspectorView.delegate = self
        brushInspectorView.configure(palette: store.configuration.colorPalette)
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
        updateBrushButtonAppearance()
        updateEraserButtonAppearance()
        updateInspectorMetrics()
        refreshChrome()
    }

    private func setupLayout() {
        [stageView, bottomPanel, historyActionsContainer, panelScrimView, inspectorContainerView, layerPanelView, loadingOverlayView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        bottomPanel.backgroundColor = CanvasEditorTheme.cardSurface
        bottomPanel.layer.cornerRadius = 30
        bottomPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        bottomPanel.layer.cornerCurve = .continuous
        bottomPanel.layer.shadowColor = CanvasEditorTheme.surfaceShadow.cgColor
        bottomPanel.layer.shadowOpacity = 1
        bottomPanel.layer.shadowRadius = 22
        bottomPanel.layer.shadowOffset = CGSize(width: 0, height: -10)

        historyActionsStack.translatesAutoresizingMaskIntoConstraints = false
        historyActionsStack.axis = .horizontal
        historyActionsStack.spacing = 12
        historyActionsContainer.addSubview(historyActionsStack)

        inspectorContainerView.backgroundColor = .clear
        inspectorContainerView.alpha = 0

        panelScrimView.backgroundColor = .clear
        panelScrimView.alpha = 0
        panelScrimView.isHidden = true
        panelScrimView.addTarget(self, action: #selector(panelScrimTapped), for: .touchUpInside)

        layerPanelView.alpha = 0
        layerPanelView.isHidden = true
        layerPanelView.transform = layerPanelHiddenTransform
        layerPanelView.isUserInteractionEnabled = false

        toolbarGridStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarGridStack.axis = .vertical
        toolbarGridStack.spacing = 10
        toolbarGridStack.distribution = .fillEqually
        bottomPanel.addSubview(toolbarGridStack)

        textInspectorView.translatesAutoresizingMaskIntoConstraints = false
        brushInspectorView.translatesAutoresizingMaskIntoConstraints = false
        brushInspectorView.isHidden = true
        inspectorContainerView.addSubview(textInspectorView)
        inspectorContainerView.addSubview(brushInspectorView)

        inspectorBottomConstraint = inspectorContainerView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: inspectorMaximumHeight + 40
        )
        inspectorHeightConstraint = inspectorContainerView.heightAnchor.constraint(equalToConstant: inspectorMaximumHeight + view.safeAreaInsets.bottom)
        layerPanelHeightConstraint = layerPanelView.heightAnchor.constraint(equalToConstant: 180)
        inspectorBottomConstraint?.isActive = true
        inspectorHeightConstraint?.isActive = true
        layerPanelHeightConstraint?.isActive = true

        inspectorContainerView.layer.shadowColor = CanvasEditorTheme.surfaceShadow.cgColor
        inspectorContainerView.layer.shadowOpacity = 1
        inspectorContainerView.layer.shadowRadius = 24
        inspectorContainerView.layer.shadowOffset = CGSize(width: 0, height: -10)

        NSLayoutConstraint.activate([
            stageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stageView.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor),

            bottomPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            historyActionsContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            historyActionsContainer.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: -18),

            historyActionsStack.leadingAnchor.constraint(equalTo: historyActionsContainer.leadingAnchor),
            historyActionsStack.trailingAnchor.constraint(equalTo: historyActionsContainer.trailingAnchor),
            historyActionsStack.topAnchor.constraint(equalTo: historyActionsContainer.topAnchor),
            historyActionsStack.bottomAnchor.constraint(equalTo: historyActionsContainer.bottomAnchor),

            toolbarGridStack.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: 18),
            toolbarGridStack.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: -18),
            toolbarGridStack.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 20),
            toolbarGridStack.bottomAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            inspectorContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inspectorContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            textInspectorView.leadingAnchor.constraint(equalTo: inspectorContainerView.leadingAnchor),
            textInspectorView.trailingAnchor.constraint(equalTo: inspectorContainerView.trailingAnchor),
            textInspectorView.topAnchor.constraint(equalTo: inspectorContainerView.topAnchor),
            textInspectorView.bottomAnchor.constraint(equalTo: inspectorContainerView.bottomAnchor),

            brushInspectorView.leadingAnchor.constraint(equalTo: inspectorContainerView.leadingAnchor),
            brushInspectorView.trailingAnchor.constraint(equalTo: inspectorContainerView.trailingAnchor),
            brushInspectorView.topAnchor.constraint(equalTo: inspectorContainerView.topAnchor),
            brushInspectorView.bottomAnchor.constraint(equalTo: inspectorContainerView.bottomAnchor),

            panelScrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panelScrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelScrimView.topAnchor.constraint(equalTo: view.topAnchor),
            panelScrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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
        let gridButtons: [(UIButton, Selector)] = [
            (addTextButton, #selector(addTextTapped)),
            (addEmojiButton, #selector(addEmojiTapped)),
            (addStickerButton, #selector(addStickerTapped)),
            (addPhotoButton, #selector(addPhotoTapped)),
            (eraserButton, #selector(eraserTapped)),
            (addBrushButton, #selector(addBrushTapped)),
            (duplicateButton, #selector(duplicateTapped)),
            (deleteButton, #selector(deleteTapped))
        ]

        gridButtons.forEach { button, action in
            button.addTarget(self, action: action, for: .touchUpInside)
        }

        let historyButtons: [(UIButton, Selector)] = [
            (undoButton, #selector(undoTapped)),
            (redoButton, #selector(redoTapped))
        ]

        historyButtons.forEach { button, action in
            button.addTarget(self, action: action, for: .touchUpInside)
            historyActionsStack.addArrangedSubview(button)
        }

        toolbarGridStack.addArrangedSubview(makeToolbarRow([
            addTextButton,
            addEmojiButton,
            addStickerButton,
            addPhotoButton
        ]))
        toolbarGridStack.addArrangedSubview(makeToolbarRow([
            eraserButton,
            duplicateButton,
            deleteButton,
            addBrushButton
        ]))
    }

    private func bindStore() {
        projectObserverID = store.observeProject { [weak self] _ in
            self?.refreshChrome()
        }
        selectionObserverID = store.observeSelection { [weak self] selectedNodeID in
            guard let self else { return }
            if selectedNodeID != self.lastSelectedNodeID {
                self.isInspectorRequested = false
                if self.brushInspectorMode == .edit {
                    self.brushInspectorMode = nil
                }
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
        duplicateButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        undoButton.isEnabled = store.canUndo
        redoButton.isEnabled = store.canRedo
        updateBrushButtonAppearance()
        updateLayerButtonAppearance()
        updateEraserButtonAppearance()
        updateVisibleInspector(animated: true)
    }

    private var shouldShowPanelScrim: Bool {
        isInspectorVisible || isLayerPanelVisible
    }

    private func prepareForPanelPresentation(_ overlayView: UIView) {
        panelScrimView.isHidden = false
        view.bringSubviewToFront(panelScrimView)
        view.bringSubviewToFront(overlayView)
        view.bringSubviewToFront(loadingOverlayView)
    }

    private func updatePanelScrimVisibility() {
        panelScrimView.alpha = shouldShowPanelScrim ? 1 : 0
        panelScrimView.backgroundColor = shouldShowPanelScrim ? CanvasEditorTheme.scrim : .clear
    }

    private func finalizePanelScrimIfNeeded() {
        panelScrimView.isHidden = !shouldShowPanelScrim
    }

    private func setInspectorVisible(_ visible: Bool, animated: Bool) {
        if visible {
            prepareForPanelPresentation(inspectorContainerView)
        }

        isInspectorVisible = visible
        updateInspectorMetrics()
        let changes = {
            self.inspectorContainerView.alpha = visible ? 1 : 0
            self.updatePanelScrimVisibility()
            self.view.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { _ in
            self.finalizePanelScrimIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.24, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateInspectorMetrics()
        updateLayerPanelHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateInspectorMetrics()
        updateLayerPanelHeight()
    }

    private func updateInspectorMetrics() {
        let totalHeight = currentInspectorHeight()
        inspectorHeightConstraint?.constant = totalHeight
        inspectorBottomConstraint?.constant = isInspectorVisible ? inspectorVisibleOffset : totalHeight + 20
    }

    private func currentInspectorHeight() -> CGFloat {
        let maximumContentHeight = min(
            inspectorMaximumHeight,
            max(view.bounds.height - view.safeAreaInsets.top - inspectorMinimumTopMargin - view.safeAreaInsets.bottom, 0)
        )

        let contentHeight: CGFloat
        switch currentVisibleInspectorKind {
        case .text:
            contentHeight = textInspectorView.preferredHeight(for: view.bounds.width, maximumHeight: maximumContentHeight)
        case .brush:
            contentHeight = brushInspectorView.preferredHeight(for: view.bounds.width, maximumHeight: maximumContentHeight)
        case .none:
            contentHeight = maximumContentHeight
        }

        return contentHeight + view.safeAreaInsets.bottom
    }

    private func setLoadingState(_ state: CanvasEditorLoadingState, animated: Bool = true) {
        loadingState = state
        let isBusy = state != .none
        stageView.isUserInteractionEnabled = !isBusy
        bottomPanel.isUserInteractionEnabled = !isBusy
        historyActionsContainer.isUserInteractionEnabled = !isBusy
        inspectorContainerView.isUserInteractionEnabled = !isBusy
        navigationItem.leftBarButtonItem?.isEnabled = !isBusy
        exportBarButtonItem.isEnabled = !isBusy
        layersBarButtonItem.isEnabled = !isBusy
        layerPanelView.isUserInteractionEnabled = !isBusy && isLayerPanelVisible

        if isBusy {
            setLayerPanelVisible(false, animated: animated)
            cancelActiveToolMode()
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
        brushInspectorMode = nil
        updateVisibleInspector(animated: true)
    }

    private func updateLayerPanelHeight() {
        let maximumHeight = min(max(view.bounds.height - view.safeAreaInsets.top - 44, 220), 420)
        layerPanelHeightConstraint?.constant = layerPanelView.preferredHeight(maximumHeight: maximumHeight)
    }

    private func resolvedVisibleInspectorKind() -> VisibleInspectorKind {
        guard !isInlineEditingText else {
            return .none
        }

        if let brushInspectorMode {
            switch brushInspectorMode {
            case .create:
                return .brush
            case .edit:
                guard let node = store.selectedNode,
                      node.kind == .shape,
                      node.shape != nil else {
                    self.brushInspectorMode = nil
                    return .none
                }
                return .brush
            }
        }

        guard let node = store.selectedNode, node.kind == .text || node.kind == .emoji else {
            isInspectorRequested = false
            return .none
        }

        textInspectorView.apply(node: node)
        return isInspectorRequested ? .text : .none
    }

    private func updateVisibleInspector(animated: Bool) {
        let visibleInspectorKind = resolvedVisibleInspectorKind()
        currentVisibleInspectorKind = visibleInspectorKind
        textInspectorView.isHidden = visibleInspectorKind != .text
        brushInspectorView.isHidden = visibleInspectorKind != .brush
        setInspectorVisible(visibleInspectorKind != .none, animated: animated)
    }

    private func updateLayerButtonAppearance() {
        layersBarButtonItem.tintColor = isLayerPanelVisible
            ? CanvasEditorTheme.accent
            : .white
    }

    private func setLayerPanelVisible(_ visible: Bool, animated: Bool) {
        guard isLayerPanelVisible != visible || layerPanelView.isHidden != !visible else {
            return
        }

        isLayerPanelVisible = visible
        updateLayerButtonAppearance()

        if visible {
            prepareForPanelPresentation(layerPanelView)
            layerPanelView.isHidden = false
            layerPanelView.isUserInteractionEnabled = loadingState == .none
        }

        let changes = {
            self.layerPanelView.alpha = visible ? 1 : 0
            self.layerPanelView.transform = visible ? .identity : self.layerPanelHiddenTransform
            self.updatePanelScrimVisibility()
        }

        let completion: (Bool) -> Void = { _ in
            if !visible {
                self.layerPanelView.isHidden = true
                self.layerPanelView.isUserInteractionEnabled = false
            }
            self.finalizePanelScrimIfNeeded()
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

    private func makeToolbarRow(_ arrangedSubviews: [UIView]) -> UIStackView {
        let rowStack = UIStackView(arrangedSubviews: arrangedSubviews)
        rowStack.axis = .horizontal
        rowStack.spacing = 10
        rowStack.alignment = .fill
        rowStack.distribution = .fillEqually
        return rowStack
    }

    private func makeToolbarSpacerView() -> UIView {
        let spacerView = UIView()
        spacerView.isUserInteractionEnabled = false
        return spacerView
    }

    private func makeGridToolButton(title: String, systemImage: String) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        var titleAttributes = AttributeContainer()
        titleAttributes.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        configuration.attributedTitle = AttributedString(title, attributes: titleAttributes)
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePlacement = .top
        configuration.imagePadding = 8
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8)
        configuration.background.cornerRadius = 20
        button.configuration = configuration
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.configurationUpdateHandler = { button in
            guard var updatedConfiguration = button.configuration else {
                return
            }
            let foregroundColor: UIColor
            if button.isEnabled {
                foregroundColor = button.isSelected ? CanvasEditorTheme.accent : CanvasEditorTheme.primaryText
            } else {
                foregroundColor = CanvasEditorTheme.secondaryText.withAlphaComponent(0.7)
            }
            updatedConfiguration.baseForegroundColor = foregroundColor
            updatedConfiguration.baseBackgroundColor = button.isSelected ? CanvasEditorTheme.accentMuted : .clear
            button.configuration = updatedConfiguration
            button.alpha = button.isEnabled ? 1 : 0.45
        }
        button.heightAnchor.constraint(equalToConstant: toolbarTileHeight).isActive = true
        return button
    }

    private func updateBrushButtonAppearance() {
        guard var configuration = addBrushButton.configuration else {
            return
        }

        configuration.image = UIImage(systemName: committedBrushConfiguration.type.systemImageName)
        addBrushButton.configuration = configuration
        addBrushButton.isSelected = isBrushModeEnabled
        addBrushButton.setNeedsUpdateConfiguration()
    }

    private func updateEraserButtonAppearance() {
        eraserButton.isSelected = isEraserModeEnabled
        eraserButton.setNeedsUpdateConfiguration()
    }

    private func makeHistoryButton(title: String, systemImage: String) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImage)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        configuration.background.backgroundColor = CanvasEditorTheme.cardSurface
        configuration.background.cornerRadius = 18
        button.configuration = configuration
        button.accessibilityLabel = title
        button.applyCanvasEditorCardStyle(
            backgroundColor: CanvasEditorTheme.cardSurface,
            cornerRadius: 18,
            borderColor: CanvasEditorTheme.separator,
            shadowColor: CanvasEditorTheme.controlShadow,
            shadowOpacity: 1,
            shadowRadius: 18,
            shadowOffset: CGSize(width: 0, height: 10)
        )
        button.configurationUpdateHandler = { button in
            guard var updatedConfiguration = button.configuration else {
                return
            }
            updatedConfiguration.baseForegroundColor = button.isEnabled
                ? CanvasEditorTheme.primaryText
                : CanvasEditorTheme.secondaryText
            updatedConfiguration.background.backgroundColor = CanvasEditorTheme.cardSurface
            button.configuration = updatedConfiguration
            button.alpha = button.isEnabled ? 1 : 0.5
        }
        button.widthAnchor.constraint(equalToConstant: historyButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: historyButtonSize).isActive = true
        return button
    }

    private func dismissInspector(animated: Bool, revertingBrushDraft: Bool = true) {
        if revertingBrushDraft {
            brushDraftConfiguration = nil
        }
        isInspectorRequested = false
        brushInspectorMode = nil
        updateVisibleInspector(animated: animated)
    }

    private func dismissEditingOverlays(animated: Bool) {
        dismissInspector(animated: animated)
        setLayerPanelVisible(false, animated: animated)
        cancelActiveToolMode()
    }

    private func presentBrushInspector(mode: BrushInspectorMode, configuration: CanvasBrushConfiguration) {
        setLayerPanelVisible(false, animated: true)
        isInspectorRequested = false
        brushInspectorMode = mode
        brushDraftConfiguration = configuration
        brushInspectorView.apply(configuration: configuration)
        updateVisibleInspector(animated: true)
    }

    private func setBrushModeEnabled(_ enabled: Bool, animated _: Bool, configuration: CanvasBrushConfiguration? = nil) {
        guard enabled != isBrushModeEnabled || (enabled && configuration != nil) else {
            return
        }

        if enabled {
            cancelActiveToolMode()
            let activeConfiguration = configuration ?? committedBrushConfiguration
            isBrushModeEnabled = true
            updateBrushButtonAppearance()
            store.selectNode(nil)
            stageView.beginDrawing(with: activeConfiguration)
        } else {
            stageView.cancelDrawingMode()
            isBrushModeEnabled = false
            updateBrushButtonAppearance()
        }
    }

    private func setEraserModeEnabled(_ enabled: Bool, animated: Bool) {
        guard enabled != isEraserModeEnabled else {
            return
        }

        if enabled {
            cancelActiveToolMode()
            dismissInspector(animated: animated)
            isEraserModeEnabled = true
            updateEraserButtonAppearance()
            store.selectNode(nil)
            stageView.beginErasing(strokeWidth: eraserStrokeWidth)
        } else {
            cancelActiveToolMode()
        }
    }

    private func cancelActiveToolMode() {
        stageView.cancelDrawingMode()

        if isBrushModeEnabled {
            isBrushModeEnabled = false
            updateBrushButtonAppearance()
        }

        if isEraserModeEnabled {
            isEraserModeEnabled = false
            updateEraserButtonAppearance()
        }
    }

    private func applyTextStyleMutation(_ mutation: (inout CanvasTextStyle) -> Void) {
        store.updateSelectedTextStyle(mutation)
        stageView.ensureSelectedTextFitsHeight()
    }

    private func presentTextColorPicker(for target: CanvasTextInspectorColorTarget) {
        guard let node = store.selectedNode, node.kind == .text || node.kind == .emoji else {
            return
        }

        let style = node.style ?? (node.kind == .emoji ? .defaultEmoji : .defaultText)
        let picker = UIColorPickerViewController()
        picker.delegate = self
        picker.supportsAlpha = true
        picker.selectedColor = selectedColor(for: target, in: style)

        activeTextColorPickerTarget = target
        present(picker, animated: true)
    }

    private func applySelectedPickerColor(_ color: UIColor, for target: CanvasTextInspectorColorTarget) {
        applyTextColorSelection(CanvasColor(uiColor: color), for: target)
    }

    private func selectedColor(for target: CanvasTextInspectorColorTarget, in style: CanvasTextStyle) -> UIColor {
        switch target {
        case .foreground:
            return style.foregroundColor.uiColor
        case .background:
            return style.backgroundFill?.color.uiColor ?? .clear
        case .shadow:
            return style.shadow?.color.uiColor ?? .black
        case .outline:
            return style.outline?.color.uiColor ?? .black
        }
    }

    private func applyTextColorSelection(_ color: CanvasColor, for target: CanvasTextInspectorColorTarget) {
        switch target {
        case .foreground:
            applyTextStyleMutation { $0.foregroundColor = color }
        case .background:
            applyTextStyleMutation {
                if color.alpha <= 0.001 {
                    $0.backgroundFill = nil
                    $0.shadow = nil
                } else {
                    $0.backgroundFill = CanvasFillStyle(color: color)
                }
            }
        case .shadow:
            applyTextStyleMutation {
                guard var shadow = $0.shadow else { return }
                shadow.color = color
                $0.shadow = shadow
            }
        case .outline:
            applyTextStyleMutation {
                guard var outline = $0.outline else { return }
                outline.color = color
                $0.outline = outline
            }
        }
    }

    private func presentEmojiPrompt() {
        let picker = CanvasInsertPickerSheetViewController(
            mode: .emoji,
            items: CanvasInsertPickerCatalog.emojiItems,
            assetLoader: stageView.assetLoader
        ) { [weak self] items in
            guard let self else { return }
            let selectedEmoji = items.compactMap { item -> String? in
                guard case .emoji(let emoji) = item.preview else {
                    return nil
                }
                return emoji
            }
            self.store.addEmojiNodes(texts: selectedEmoji)
        }
        presentInsertPicker(picker)
    }

    private func presentStickerPicker() {
        let picker = CanvasInsertPickerSheetViewController(
            mode: .sticker,
            items: CanvasInsertPickerCatalog.stickerItems(from: store.configuration.stickerCatalog),
            assetLoader: stageView.assetLoader
        ) { [weak self] items in
            guard let self else { return }
            let selectedSources = items.compactMap { item -> CanvasAssetSource? in
                guard case .asset(let source) = item.preview else {
                    return nil
                }
                return source
            }
            self.store.addStickerNodes(sources: selectedSources)
        }
        presentInsertPicker(picker)
    }

    private func presentInsertPicker(_ picker: UIViewController) {
        setLayerPanelVisible(false, animated: true)
        picker.modalPresentationStyle = .overFullScreen
        present(picker, animated: true)
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

    func textInspectorViewDidRequestTextEdit(_ textInspectorView: CanvasTextInspectorView) {
        stageView.beginInlineEditingForSelectedNode()
    }

    func canvasBrushInspectorViewDidCancel(_ brushInspectorView: CanvasBrushInspectorView) {
        dismissInspector(animated: true)
    }

    func canvasBrushInspectorView(_ brushInspectorView: CanvasBrushInspectorView, didChange configuration: CanvasBrushConfiguration) {
        brushDraftConfiguration = configuration
    }

    func canvasBrushInspectorView(_ brushInspectorView: CanvasBrushInspectorView, didConfirm configuration: CanvasBrushConfiguration) {
        let resolvedConfiguration = brushDraftConfiguration ?? configuration

        switch brushInspectorMode {
        case .create:
            committedBrushConfiguration = resolvedConfiguration
            brushDraftConfiguration = nil
            dismissInspector(animated: true, revertingBrushDraft: false)
            setBrushModeEnabled(true, animated: true, configuration: resolvedConfiguration)

        case .edit:
            brushDraftConfiguration = nil
            store.updateSelectedShapeStyle(
                type: resolvedConfiguration.type,
                strokeColor: resolvedConfiguration.color,
                strokeWidth: resolvedConfiguration.strokeWidth,
                opacity: resolvedConfiguration.opacity
            )
            dismissInspector(animated: true, revertingBrushDraft: false)

        case .none:
            dismissInspector(animated: true)
        }
    }

    func canvasStageViewDidTapSelectedTextNode(_ stageView: CanvasStageView) {
        guard let node = store.selectedNode, node.kind == .text || node.kind == .emoji, !isInlineEditingText else {
            return
        }
        cancelActiveToolMode()
        setLayerPanelVisible(false, animated: true)
        brushInspectorMode = nil
        isInspectorRequested.toggle()
        refreshChrome()
    }

    func canvasStageViewDidTapSelectedShapeNode(_ stageView: CanvasStageView) {
        guard let node = store.selectedNode,
              node.kind == .shape,
              let shape = node.shape,
              !isInlineEditingText else {
            return
        }

        if brushInspectorMode == .edit, !brushInspectorView.isHidden {
            dismissInspector(animated: true)
            return
        }

        presentBrushInspector(
            mode: .edit,
            configuration: CanvasBrushConfiguration(shape: shape, opacity: node.opacity)
        )
    }

    func canvasStageViewDidBeginInlineEditing(_ stageView: CanvasStageView) {
        isInlineEditingText = true
        isInspectorRequested = false
        brushInspectorMode = nil
        updateVisibleInspector(animated: true)
    }

    func canvasStageViewDidEndInlineEditing(_ stageView: CanvasStageView) {
        isInlineEditingText = false
        refreshChrome()
    }

    func canvasStageViewDidBeginNodeManipulation(_ stageView: CanvasStageView) {
        guard isInspectorRequested || brushInspectorMode != nil || isInspectorVisible else {
            return
        }
        isInspectorRequested = false
        brushInspectorMode = nil
        updateVisibleInspector(animated: true)
    }

    func canvasStageView(_ stageView: CanvasStageView, didFinishDrawing draft: CanvasShapeDraft) {
        committedBrushConfiguration = CanvasBrushConfiguration(
            type: draft.type,
            strokeWidth: draft.strokeWidth,
            opacity: draft.opacity,
            color: draft.strokeColor
        )
        store.addShapeNode(from: draft)
        if isBrushModeEnabled {
            store.selectNode(nil)
        }
    }

    func canvasStageView(_ stageView: CanvasStageView, didFinishErasing stroke: CanvasEraserStroke) {
        eraserStrokeWidth = stroke.strokeWidth
        store.addEraserStroke(stroke)
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectFontFamily fontFamily: String) {
        applyTextStyleMutation { $0.fontFamily = fontFamily }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectAlignment alignment: CanvasTextAlignment) {
        applyTextStyleMutation { $0.alignment = alignment }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didSelectColor color: CanvasColor, for target: CanvasTextInspectorColorTarget) {
        applyTextColorSelection(color, for: target)
    }

    func textInspectorViewDidSelectClearBackground(_ textInspectorView: CanvasTextInspectorView) {
        applyTextStyleMutation {
            $0.backgroundFill = nil
            $0.shadow = nil
        }
    }

    func textInspectorView(_ textInspectorView: CanvasTextInspectorView, didRequestColorPickerFor target: CanvasTextInspectorColorTarget) {
        presentTextColorPicker(for: target)
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

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        guard let activeTextColorPickerTarget else {
            return
        }
        applySelectedPickerColor(viewController.selectedColor, for: activeTextColorPickerTarget)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        activeTextColorPickerTarget = nil
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
        dismissEditingOverlays(animated: true)
        setLayerPanelVisible(!isLayerPanelVisible, animated: true)
    }

    @objc
    private func panelScrimTapped() {
        if isLayerPanelVisible {
            setLayerPanelVisible(false, animated: true)
        } else if isInspectorVisible {
            dismissInspector(animated: true)
        }
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
        dismissEditingOverlays(animated: true)
        store.addTextNode()
        stageView.beginInlineEditingForSelectedNode(placeCursorAtEnd: false)
    }

    @objc
    private func addEmojiTapped() {
        dismissEditingOverlays(animated: true)
        presentEmojiPrompt()
    }

    @objc
    private func addStickerTapped() {
        dismissEditingOverlays(animated: true)
        presentStickerPicker()
    }

    @objc
    private func addPhotoTapped() {
        dismissEditingOverlays(animated: true)
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc
    private func eraserTapped() {
        setEraserModeEnabled(!isEraserModeEnabled, animated: true)
    }

    @objc
    private func addBrushTapped() {
        if isBrushModeEnabled {
            setBrushModeEnabled(false, animated: true)
            return
        }

        cancelActiveToolMode()
        presentBrushInspector(mode: .create, configuration: committedBrushConfiguration)
    }

    @objc
    private func duplicateTapped() {
        dismissEditingOverlays(animated: true)
        store.duplicateSelectedNode()
    }

    @objc
    private func deleteTapped() {
        dismissEditingOverlays(animated: true)
        store.deleteSelectedNode()
    }

    @objc
    private func undoTapped() {
        cancelActiveToolMode()
        store.undo()
    }

    @objc
    private func redoTapped() {
        cancelActiveToolMode()
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

        applyCanvasEditorCardStyle(
            backgroundColor: CanvasEditorTheme.sheetSurface,
            cornerRadius: 24,
            borderColor: CanvasEditorTheme.separator,
            shadowColor: CanvasEditorTheme.surfaceShadow,
            shadowOpacity: 1,
            shadowRadius: 24,
            shadowOffset: CGSize(width: 0, height: 12)
        )

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Layers"
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = CanvasEditorTheme.primaryText
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
    private static let previewAssetLoader = CanvasAssetLoader()

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
        rowBackgroundView.applyCanvasEditorCardStyle(
            backgroundColor: CanvasEditorTheme.cardSurface,
            cornerRadius: 16,
            borderColor: CanvasEditorTheme.separator,
            shadowColor: CanvasEditorTheme.controlShadow,
            shadowOpacity: 1,
            shadowRadius: 12,
            shadowOffset: CGSize(width: 0, height: 6)
        )
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
        titleLabel.textColor = CanvasEditorTheme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        rowBackgroundView.addSubview(titleLabel)

        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.tintColor = CanvasEditorTheme.secondaryText
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
        rowBackgroundView.backgroundColor = isSelectedInPanel ? CanvasEditorTheme.accentMuted : CanvasEditorTheme.cardSurface
        rowBackgroundView.layer.borderColor = (isSelectedInPanel
            ? CanvasEditorTheme.accent.withAlphaComponent(0.22)
            : CanvasEditorTheme.separator).cgColor
        rowBackgroundView.alpha = isLocked ? 0.58 : 1
        titleLabel.text = Self.displayTitle(for: node)
        titleLabel.textColor = CanvasEditorTheme.primaryText
        lockButton.setImage(UIImage(systemName: isLocked ? "lock.fill" : "lock.open"), for: .normal)
        lockButton.tintColor = isLocked ? CanvasEditorTheme.destructive : CanvasEditorTheme.secondaryText

        previewContainerView.backgroundColor = Self.previewBackground(for: node)
        previewLabel.isHidden = false
        previewImageView.isHidden = true

        switch node.kind {
        case .text:
            previewLabel.text = "T"
            previewLabel.textColor = node.style?.foregroundColor.uiColor ?? CanvasEditorTheme.primaryText
        case .emoji:
            previewLabel.text = String((node.text ?? "🙂").prefix(1))
            previewLabel.textColor = CanvasEditorTheme.primaryText
        case .sticker:
            previewImageView.isHidden = false
            previewLabel.isHidden = true
            let stickerImage = Self.previewAssetLoader.imageSynchronously(for: node.source)
            previewImageView.image = stickerImage ?? UIImage(systemName: node.source?.name ?? "sparkles")
            previewImageView.tintColor = stickerImage == nil ? (node.style?.foregroundColor.uiColor ?? CanvasEditorTheme.primaryText) : nil
        case .image:
            previewImageView.isHidden = false
            previewLabel.isHidden = true
            previewImageView.image = UIImage(systemName: "photo")
            previewImageView.tintColor = CanvasEditorTheme.primaryText
        case .shape:
            previewImageView.isHidden = false
            previewLabel.isHidden = true
            previewImageView.image = UIImage(systemName: node.shape?.type.systemImageName ?? "paintbrush")
            previewImageView.tintColor = node.shape?.strokeColor.uiColor ?? CanvasEditorTheme.primaryText
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
        case .shape:
            return node.shape?.type.displayTitle ?? "Shape"
        }
    }

    private static func previewBackground(for node: CanvasNode) -> UIColor {
        switch node.kind {
        case .text:
            return UIColor(red: 0.99, green: 0.77, blue: 0.71, alpha: 1)
        case .emoji:
            return UIColor(red: 1, green: 0.94, blue: 0.7, alpha: 1)
        case .sticker:
            return UIColor(red: 0.82, green: 0.92, blue: 1, alpha: 1)
        case .image:
            return CanvasEditorTheme.canvasBackdrop
        case .shape:
            return UIColor(red: 0.84, green: 0.96, blue: 0.88, alpha: 1)
        }
    }
}
