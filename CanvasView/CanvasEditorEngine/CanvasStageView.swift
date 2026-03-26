import UIKit

struct CanvasBrushConfiguration: Hashable {
    var type: CanvasShapeType
    var strokeWidth: Double
    var opacity: Double
    var color: CanvasColor

    static let defaultValue = CanvasBrushConfiguration(
        type: .brush,
        strokeWidth: 18,
        opacity: 1,
        color: .white
    )

    init(
        type: CanvasShapeType,
        strokeWidth: Double,
        opacity: Double,
        color: CanvasColor
    ) {
        self.type = type
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.color = color
    }

    init(shape: CanvasShapePayload, opacity: Double) {
        self.init(
            type: shape.type,
            strokeWidth: shape.strokeWidth,
            opacity: opacity,
            color: shape.strokeColor
        )
    }
}

private enum CanvasStageToolMode: Equatable {
    case drawing(CanvasBrushConfiguration)
    case erasing(strokeWidth: Double)
}

protocol CanvasStageViewDelegate: AnyObject {
    func canvasStageViewDidTapSelectedTextNode(_ stageView: CanvasStageView)
    func canvasStageViewDidTapSelectedShapeNode(_ stageView: CanvasStageView)
    func canvasStageViewDidBeginInlineEditing(_ stageView: CanvasStageView)
    func canvasStageViewDidEndInlineEditing(_ stageView: CanvasStageView)
    func canvasStageViewDidBeginNodeManipulation(_ stageView: CanvasStageView)
    func canvasStageView(_ stageView: CanvasStageView, didFinishDrawing draft: CanvasShapeDraft)
    func canvasStageView(_ stageView: CanvasStageView, didFinishErasing stroke: CanvasEraserStroke)
}

final class CanvasStageView: UIView, UIGestureRecognizerDelegate, UITextViewDelegate {
    weak var delegate: CanvasStageViewDelegate?

    var store: CanvasEditorStore? {
        didSet {
            rebindStore(oldValue: oldValue)
        }
    }

    let assetLoader = CanvasAssetLoader()

    private let canvasContainerView = UIView()
    private let contentContainerView = UIView()
    private let backgroundColorView = UIView()
    private let backgroundImageView = UIImageView()
    private let lowerNodeContainerView = UIView()
    private let selectedNodeHostView = UIView()
    private let upperNodeContainerView = UIView()
    private let drawingPreviewView = UIView()
    private let selectionOverlay = CanvasSelectionOverlayView()
    private let inlineTextView = UITextView()

    private let deleteHandle = OverlayHandleControl(systemImage: "xmark", tintColor: .systemRed)
    private let widthHandle = OverlayHandleControl(systemImage: "arrow.left.and.right")
    private let heightHandle = OverlayHandleControl(systemImage: "arrow.up.and.down")
    private let transformHandle = OverlayHandleControl(systemImage: "arrow.up.left.and.arrow.down.right")
    private let drawingPreviewLayer = CAShapeLayer()
    private let eraserMaskLayer = CALayer()

    private lazy var tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
    private lazy var panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var rotationGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
    private lazy var drawingPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleDrawingPan(_:)))

    private var projectObserverID: UUID?
    private var selectionObserverID: UUID?
    private var nodeViews: [String: CanvasNodeView] = [:]

    private var canvasSize: CGSize = .zero
    private var canvasScale: CGFloat = 1
    private var activePanTranslation: CGPoint = .zero
    private var activePanNodeID: String?
    private var activePinchNodeID: String?
    private var activeRotationNodeID: String?
    private var lastTransformVector: CGPoint?
    private var lastTextWidthTranslation: CGPoint = .zero
    private var lastTextHeightTranslation: CGPoint = .zero
    private var editingNodeID: String?
    private var activeEditingStyle: CanvasTextStyle?
    private var isApplyingInlineEditorState = false
    private var toolMode: CanvasStageToolMode?
    private var toolPoints: [CGPoint] = []
    private var toolStartPoint: CGPoint?

    private let viewportPadding: CGFloat = 28
    private let textContentInset: CGFloat = 8

    var isToolModeActive: Bool {
        toolMode != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)

        canvasContainerView.backgroundColor = .clear
        canvasContainerView.layer.shadowColor = UIColor.black.cgColor
        canvasContainerView.layer.shadowOpacity = 0.3
        canvasContainerView.layer.shadowRadius = 18
        canvasContainerView.layer.shadowOffset = CGSize(width: 0, height: 10)
        contentContainerView.clipsToBounds = true

        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true

        lowerNodeContainerView.clipsToBounds = true
        selectedNodeHostView.clipsToBounds = false
        upperNodeContainerView.clipsToBounds = true
        drawingPreviewView.clipsToBounds = true
        drawingPreviewView.isUserInteractionEnabled = false
        drawingPreviewView.isHidden = true

        selectionOverlay.isHidden = true

        inlineTextView.isOpaque = false
        inlineTextView.backgroundColor = .clear
        inlineTextView.textContainerInset = .zero
        inlineTextView.textContainer.lineFragmentPadding = 0
        inlineTextView.autocorrectionType = .no
        inlineTextView.autocapitalizationType = .sentences
        inlineTextView.smartQuotesType = .no
        inlineTextView.smartDashesType = .no
        inlineTextView.smartInsertDeleteType = .no
        inlineTextView.isScrollEnabled = false
        inlineTextView.isHidden = true
        inlineTextView.delegate = self

        drawingPreviewLayer.fillColor = UIColor.clear.cgColor
        drawingPreviewLayer.lineCap = .round
        drawingPreviewLayer.lineJoin = .round
        drawingPreviewLayer.isHidden = true
        drawingPreviewView.layer.addSublayer(drawingPreviewLayer)
        eraserMaskLayer.contentsGravity = .resize
        contentContainerView.layer.mask = eraserMaskLayer

        addSubview(canvasContainerView)
        canvasContainerView.addSubview(contentContainerView)
        contentContainerView.addSubview(backgroundColorView)
        contentContainerView.addSubview(backgroundImageView)
        contentContainerView.addSubview(lowerNodeContainerView)
        contentContainerView.addSubview(selectedNodeHostView)
        contentContainerView.addSubview(upperNodeContainerView)
        canvasContainerView.addSubview(drawingPreviewView)
        canvasContainerView.addSubview(selectionOverlay)
        canvasContainerView.addSubview(inlineTextView)

        [deleteHandle, widthHandle, heightHandle, transformHandle].forEach {
            $0.isHidden = true
            canvasContainerView.addSubview($0)
        }

        deleteHandle.addAction(UIAction { [weak self] _ in
            self?.handleDeleteTapped()
        }, for: .touchUpInside)

        let transformPan = UIPanGestureRecognizer(target: self, action: #selector(handleTransformHandlePan(_:)))
        let widthPan = UIPanGestureRecognizer(target: self, action: #selector(handleTextWidthHandlePan(_:)))
        let heightPan = UIPanGestureRecognizer(target: self, action: #selector(handleTextHeightHandlePan(_:)))
        transformHandle.addGestureRecognizer(transformPan)
        widthHandle.addGestureRecognizer(widthPan)
        heightHandle.addGestureRecognizer(heightPan)

        tapGestureRecognizer.cancelsTouchesInView = false
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        doubleTapGestureRecognizer.cancelsTouchesInView = false
        tapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
        drawingPanGestureRecognizer.maximumNumberOfTouches = 1
        drawingPanGestureRecognizer.isEnabled = false

        [tapGestureRecognizer, doubleTapGestureRecognizer, panGestureRecognizer, pinchGestureRecognizer, rotationGestureRecognizer, drawingPanGestureRecognizer].forEach {
            $0.delegate = self
            addGestureRecognizer($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let projectObserverID {
            store?.removeObserver(projectObserverID)
        }
        if let selectionObserverID {
            store?.removeObserver(selectionObserverID)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return
        }

        let layout = CanvasViewportMath.fit(canvasSize: canvasSize, in: bounds, padding: viewportPadding)
        canvasScale = layout.scale

        canvasContainerView.bounds = CGRect(origin: .zero, size: canvasSize)
        canvasContainerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        canvasContainerView.transform = CGAffineTransform(scaleX: canvasScale, y: canvasScale)

        contentContainerView.frame = CGRect(origin: .zero, size: canvasSize)
        backgroundColorView.frame = contentContainerView.bounds
        backgroundImageView.frame = contentContainerView.bounds
        [lowerNodeContainerView, selectedNodeHostView, upperNodeContainerView, drawingPreviewView].forEach {
            $0.frame = CGRect(origin: .zero, size: canvasSize)
        }
        drawingPreviewLayer.frame = drawingPreviewView.bounds
        eraserMaskLayer.frame = contentContainerView.bounds
        updateEraserMask()

        updateSelectionOverlay()
        updateInlineTextEditor()
    }

    func renderProject(_ project: CanvasProject) {
        canvasSize = project.canvasSize.cgSize

        backgroundColorView.backgroundColor = project.background.color?.uiColor ?? .clear
        backgroundImageView.image = nil
        if project.background.kind == .image {
            assetLoader.image(for: project.background.source) { [weak self] image in
                self?.backgroundImageView.image = image
            }
        }

        nodeViews.values.forEach { $0.removeFromSuperview() }
        nodeViews.removeAll()

        project.sortedNodes.forEach { node in
            let nodeView = CanvasNodeView()
            nodeView.apply(node: node, assetLoader: assetLoader)
            nodeViews[node.id] = nodeView
        }

        syncNodePresentation()
        canvasContainerView.bringSubviewToFront(drawingPreviewView)
        canvasContainerView.bringSubviewToFront(selectionOverlay)
        canvasContainerView.bringSubviewToFront(inlineTextView)
        [deleteHandle, widthHandle, heightHandle, transformHandle].forEach {
            canvasContainerView.bringSubviewToFront($0)
        }
        setNeedsLayout()
        layoutIfNeeded()
        updateEraserMask(strokes: project.eraserStrokes)
        updateSelectionOverlay()
        updateInlineTextEditor()
    }

    func beginInlineEditingForSelectedNode(placeCursorAtEnd: Bool = true) {
        guard let node = store?.selectedNode,
              node.isEditable,
              node.kind == .text || node.kind == .emoji else {
            return
        }
        editingNodeID = node.id
        activeEditingStyle = node.style
        delegate?.canvasStageViewDidBeginInlineEditing(self)
        syncNodePresentation()
        updateInlineTextEditor(forceTextRefresh: true)

        let targetOffset = placeCursorAtEnd ? (inlineTextView.text as NSString).length : 0
        inlineTextView.selectedRange = NSRange(location: targetOffset, length: 0)
        inlineTextView.becomeFirstResponder()
    }

    func beginDrawing(with configuration: CanvasBrushConfiguration) {
        endInlineEditing()
        toolMode = .drawing(configuration)
        toolPoints.removeAll()
        toolStartPoint = nil
        drawingPreviewLayer.path = nil
        drawingPreviewView.isHidden = false
        drawingPreviewLayer.isHidden = false
        setNodeGesturesEnabled(false)
        drawingPanGestureRecognizer.isEnabled = true
        selectionOverlay.isHidden = true
        [deleteHandle, widthHandle, heightHandle, transformHandle].forEach { $0.isHidden = true }
        canvasContainerView.bringSubviewToFront(drawingPreviewView)
    }

    func beginErasing(strokeWidth: Double) {
        endInlineEditing()
        toolMode = .erasing(strokeWidth: strokeWidth)
        toolPoints.removeAll()
        toolStartPoint = nil
        drawingPreviewLayer.path = nil
        drawingPreviewLayer.strokeColor = UIColor.white.withAlphaComponent(0.92).cgColor
        drawingPreviewLayer.lineWidth = strokeWidth
        drawingPreviewView.isHidden = false
        drawingPreviewLayer.isHidden = false
        setNodeGesturesEnabled(false)
        drawingPanGestureRecognizer.isEnabled = true
        selectionOverlay.isHidden = true
        [deleteHandle, widthHandle, heightHandle, transformHandle].forEach { $0.isHidden = true }
        canvasContainerView.bringSubviewToFront(drawingPreviewView)
    }

    func cancelDrawingMode() {
        toolMode = nil
        toolPoints.removeAll()
        toolStartPoint = nil
        drawingPreviewLayer.path = nil
        drawingPreviewLayer.isHidden = true
        drawingPreviewView.isHidden = true
        drawingPanGestureRecognizer.isEnabled = false
        setNodeGesturesEnabled(true)
        updateSelectionOverlay()
    }

    func endInlineEditing() {
        guard editingNodeID != nil else {
            return
        }
        if inlineTextView.isFirstResponder {
            inlineTextView.resignFirstResponder()
        } else {
            endInlineEditingWithoutResigning()
        }
    }

    func ensureSelectedTextFitsHeight() {
        guard let store, let node = store.selectedNode, node.kind == .text else {
            return
        }

        let style = node.style ?? .defaultText
        let contentWidth = max(node.size.width - (textContentInset * 2), 40)
        let requiredHeight = style.requiredTextHeight(
            text: node.text ?? "",
            constrainedWidth: contentWidth
        ) + (textContentInset * 2)

        guard abs(requiredHeight - node.size.height) > 0.5 else {
            return
        }

        store.updateSelectedTextHeight(requiredHeight)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === drawingPanGestureRecognizer {
            return isToolModeActive
        }

        guard let touchedView = touch.view else {
            return true
        }

        let blockedViews = [inlineTextView, deleteHandle, widthHandle, heightHandle, transformHandle]
        return !blockedViews.contains(where: { touchedView.isDescendant(of: $0) })
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let gestureTypes = [type(of: gestureRecognizer), type(of: otherGestureRecognizer)]
        return gestureTypes.contains(where: { $0 == UIPinchGestureRecognizer.self }) &&
            gestureTypes.contains(where: { $0 == UIRotationGestureRecognizer.self })
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingInlineEditorState else {
            return
        }
        store?.updateSelectedText(textView.text)
        ensureSelectedTextFitsHeight()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        endInlineEditingWithoutResigning()
    }

    @objc
    private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let location = gestureRecognizer.location(in: canvasContainerView)
        let tappedNode = hitTestNode(at: location)
        let tappedSelectedTextNode = tappedNode?.id == store?.selectedNodeID &&
            (tappedNode?.kind == .text || tappedNode?.kind == .emoji)
        let tappedSelectedShapeNode = tappedNode?.id == store?.selectedNodeID && tappedNode?.kind == .shape

        if editingNodeID != nil, tappedNode?.id != editingNodeID {
            endInlineEditing()
        }

        store?.selectNode(tappedNode?.id)
        if tappedSelectedTextNode, editingNodeID == nil {
            delegate?.canvasStageViewDidTapSelectedTextNode(self)
        } else if tappedSelectedShapeNode, editingNodeID == nil {
            delegate?.canvasStageViewDidTapSelectedShapeNode(self)
        }
    }

    @objc
    private func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let location = gestureRecognizer.location(in: canvasContainerView)
        guard let node = hitTestNode(at: location) else {
            return
        }
        store?.selectNode(node.id)
        if node.kind == .text || node.kind == .emoji {
            beginInlineEditingForSelectedNode()
        }
    }

    @objc
    private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let store else {
            return
        }

        switch gestureRecognizer.state {
        case .began:
            activePanTranslation = .zero
            activePanNodeID = nil
            let location = gestureRecognizer.location(in: canvasContainerView)
            if let node = hitTestNode(at: location) {
                if editingNodeID != nil, editingNodeID != node.id {
                    endInlineEditing()
                }
                delegate?.canvasStageViewDidBeginNodeManipulation(self)
                store.selectNode(node.id)
                activePanNodeID = node.id
            }

        case .changed:
            guard activePanNodeID == store.selectedNodeID,
                  store.selectedNode?.isEditable == true else {
                return
            }
            let translation = gestureRecognizer.translation(in: self)
            let delta = CGPoint(
                x: (translation.x - activePanTranslation.x) / max(canvasScale, 0.001),
                y: (translation.y - activePanTranslation.y) / max(canvasScale, 0.001)
            )
            activePanTranslation = translation
            store.moveSelectedNode(by: CanvasPoint(delta))

        default:
            activePanTranslation = .zero
            activePanNodeID = nil
        }
    }

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        guard let store else {
            return
        }

        if gestureRecognizer.state == .began {
            activePinchNodeID = nil
            let location = gestureRecognizer.location(in: canvasContainerView)
            if let node = hitTestNode(at: location) {
                if editingNodeID != nil, editingNodeID != node.id {
                    endInlineEditing()
                }
                delegate?.canvasStageViewDidBeginNodeManipulation(self)
                store.selectNode(node.id)
                activePinchNodeID = node.id
            }
        }

        switch gestureRecognizer.state {
        case .changed:
            guard activePinchNodeID == store.selectedNodeID,
                  store.selectedNode?.isEditable == true else {
                return
            }
            store.scaleSelectedNode(by: gestureRecognizer.scale)
            gestureRecognizer.scale = 1

        default:
            if gestureRecognizer.state == .ended || gestureRecognizer.state == .cancelled || gestureRecognizer.state == .failed {
                activePinchNodeID = nil
            }
        }
    }

    @objc
    private func handleRotation(_ gestureRecognizer: UIRotationGestureRecognizer) {
        guard let store else {
            return
        }

        if gestureRecognizer.state == .began {
            activeRotationNodeID = nil
            let location = gestureRecognizer.location(in: canvasContainerView)
            if let node = hitTestNode(at: location) {
                if editingNodeID != nil, editingNodeID != node.id {
                    endInlineEditing()
                }
                delegate?.canvasStageViewDidBeginNodeManipulation(self)
                store.selectNode(node.id)
                activeRotationNodeID = node.id
            }
        }

        switch gestureRecognizer.state {
        case .changed:
            guard activeRotationNodeID == store.selectedNodeID,
                  store.selectedNode?.isEditable == true else {
                return
            }
            store.rotateSelectedNode(by: gestureRecognizer.rotation)
            gestureRecognizer.rotation = 0

        default:
            if gestureRecognizer.state == .ended || gestureRecognizer.state == .cancelled || gestureRecognizer.state == .failed {
                activeRotationNodeID = nil
            }
        }
    }

    @objc
    private func handleTransformHandlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let store, let selectedNode = store.selectedNode else {
            return
        }

        if gestureRecognizer.state == .began {
            endInlineEditing()
            delegate?.canvasStageViewDidBeginNodeManipulation(self)
        }

        let location = gestureRecognizer.location(in: canvasContainerView)
        let center = selectedNode.transform.position.cgPoint
        let vector = CGPoint(x: location.x - center.x, y: location.y - center.y)

        switch gestureRecognizer.state {
        case .began:
            lastTransformVector = vector

        case .changed:
            guard let previousVector = lastTransformVector else {
                lastTransformVector = vector
                return
            }
            let previousLength = max(hypot(previousVector.x, previousVector.y), 1)
            let currentLength = max(hypot(vector.x, vector.y), 1)
            let scaleMultiplier = currentLength / previousLength
            let previousAngle = atan2(previousVector.y, previousVector.x)
            let currentAngle = atan2(vector.y, vector.x)
            store.transformSelectedNode(
                scaleMultiplier: scaleMultiplier,
                rotationDelta: currentAngle - previousAngle
            )
            lastTransformVector = vector

        default:
            lastTransformVector = nil
        }
    }

    @objc
    private func handleTextWidthHandlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let store, let selectedNode = store.selectedNode, selectedNode.kind == .text else {
            return
        }

        if gestureRecognizer.state == .began {
            endInlineEditing()
            lastTextWidthTranslation = .zero
            delegate?.canvasStageViewDidBeginNodeManipulation(self)
        }

        let translation = gestureRecognizer.translation(in: canvasContainerView)
        let delta = CGPoint(
            x: translation.x - lastTextWidthTranslation.x,
            y: translation.y - lastTextWidthTranslation.y
        )

        switch gestureRecognizer.state {
        case .changed:
            let cosValue = CGFloat(cos(-selectedNode.transform.rotation))
            let sinValue = CGFloat(sin(-selectedNode.transform.rotation))
            let localDeltaX = (delta.x * cosValue) - (delta.y * sinValue)
            let widthDelta = localDeltaX / max(selectedNode.transform.scale, 0.001)
            store.adjustSelectedTextWidth(by: widthDelta)
            ensureSelectedTextFitsHeight()
            lastTextWidthTranslation = translation

        default:
            lastTextWidthTranslation = .zero
        }
    }

    @objc
    private func handleTextHeightHandlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let store, let selectedNode = store.selectedNode, selectedNode.kind == .text else {
            return
        }

        if gestureRecognizer.state == .began {
            endInlineEditing()
            lastTextHeightTranslation = .zero
            delegate?.canvasStageViewDidBeginNodeManipulation(self)
        }

        let translation = gestureRecognizer.translation(in: canvasContainerView)
        let delta = CGPoint(
            x: translation.x - lastTextHeightTranslation.x,
            y: translation.y - lastTextHeightTranslation.y
        )

        switch gestureRecognizer.state {
        case .changed:
            let sinValue = CGFloat(sin(selectedNode.transform.rotation))
            let cosValue = CGFloat(cos(selectedNode.transform.rotation))
            let localDeltaY = (delta.x * sinValue) + (delta.y * cosValue)
            let heightDelta = localDeltaY / max(selectedNode.transform.scale, 0.001)
            let style = selectedNode.style ?? .defaultText
            let minimumHeight = style.requiredTextHeight(
                text: selectedNode.text ?? "",
                constrainedWidth: max(selectedNode.size.width - (textContentInset * 2), 40)
            ) + (textContentInset * 2)
            store.adjustSelectedTextHeight(by: heightDelta, minimumHeight: minimumHeight)
            lastTextHeightTranslation = translation

        default:
            lastTextHeightTranslation = .zero
        }
    }

    @objc
    private func handleDrawingPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let toolMode else {
            return
        }

        let location = clampedCanvasPoint(gestureRecognizer.location(in: canvasContainerView))

        switch gestureRecognizer.state {
        case .began:
            toolStartPoint = location
            toolPoints = [location]
            updateToolPreview()

        case .changed:
            guard let toolStartPoint else {
                return
            }

            switch toolMode {
            case .drawing(let configuration):
                switch configuration.type {
                case .brush:
                    appendFreehandPoint(location)
                case .line, .arrow, .oval, .rectangle:
                    toolPoints = [toolStartPoint, location]
                }
            case .erasing:
                appendFreehandPoint(location)
            }

            updateToolPreview()

        case .ended:
            switch toolMode {
            case .drawing(let configuration):
                if let draft = currentShapeDraft(using: configuration) {
                    delegate?.canvasStageView(self, didFinishDrawing: draft)
                }
            case .erasing(let strokeWidth):
                if let stroke = currentEraserStroke(strokeWidth: strokeWidth) {
                    delegate?.canvasStageView(self, didFinishErasing: stroke)
                }
            }
            cancelDrawingMode()

        default:
            cancelDrawingMode()
        }
    }

    private func handleDeleteTapped() {
        endInlineEditing()
        store?.deleteSelectedNode()
    }

    private func setNodeGesturesEnabled(_ enabled: Bool) {
        tapGestureRecognizer.isEnabled = enabled
        doubleTapGestureRecognizer.isEnabled = enabled
        panGestureRecognizer.isEnabled = enabled
        pinchGestureRecognizer.isEnabled = enabled
        rotationGestureRecognizer.isEnabled = enabled
    }

    private func clampedCanvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    private func appendFreehandPoint(_ point: CGPoint) {
        if let previousPoint = toolPoints.last {
            let distance = hypot(point.x - previousPoint.x, point.y - previousPoint.y)
            if distance >= 1.5 {
                toolPoints.append(point)
            } else {
                toolPoints[toolPoints.count - 1] = point
            }
        } else {
            toolPoints = [point]
        }
    }

    private func updateToolPreview() {
        guard let toolMode else {
            drawingPreviewLayer.path = nil
            drawingPreviewLayer.isHidden = true
            return
        }

        switch toolMode {
        case .drawing(let configuration):
            drawingPreviewLayer.path = CanvasShapePathBuilder.makePath(
                type: configuration.type,
                points: toolPoints
            ).cgPath
            drawingPreviewLayer.strokeColor = configuration.color.uiColor.withAlphaComponent(configuration.opacity).cgColor
            drawingPreviewLayer.lineWidth = configuration.strokeWidth
        case .erasing(let strokeWidth):
            drawingPreviewLayer.path = CanvasEraserPathBuilder.makePath(points: toolPoints)
            drawingPreviewLayer.strokeColor = UIColor.white.withAlphaComponent(0.92).cgColor
            drawingPreviewLayer.lineWidth = strokeWidth
        }

        drawingPreviewLayer.isHidden = toolPoints.isEmpty
    }

    private func currentShapeDraft(using configuration: CanvasBrushConfiguration) -> CanvasShapeDraft? {
        guard !toolPoints.isEmpty else {
            return nil
        }

        let minimumDistance = max(CGFloat(configuration.strokeWidth) * 0.5, 6)
        let pointDistance: CGFloat
        if let first = toolPoints.first, let last = toolPoints.last {
            pointDistance = hypot(last.x - first.x, last.y - first.y)
        } else {
            pointDistance = 0
        }

        if configuration.type != .brush, pointDistance < minimumDistance {
            return nil
        }

        return CanvasShapeDraft(
            type: configuration.type,
            points: toolPoints.map { point in
                CanvasPoint(x: point.x, y: point.y)
            },
            strokeColor: configuration.color,
            strokeWidth: configuration.strokeWidth,
            opacity: configuration.opacity
        )
    }

    private func currentEraserStroke(strokeWidth: Double) -> CanvasEraserStroke? {
        guard !toolPoints.isEmpty else {
            return nil
        }

        return CanvasEraserStroke(
            points: toolPoints.map { CanvasPoint(x: $0.x, y: $0.y) },
            strokeWidth: strokeWidth
        )
    }

    private func updateEraserMask(strokes: [CanvasEraserStroke]? = nil) {
        let currentStrokes = strokes ?? store?.project.eraserStrokes ?? []
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            eraserMaskLayer.contents = nil
            return
        }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let maskImage = UIGraphicsImageRenderer(size: canvasSize, format: format).image { rendererContext in
            UIColor.white.setFill()
            UIRectFill(canvasRect)
            CanvasEraserPathBuilder.applyClearStrokes(currentStrokes, in: rendererContext.cgContext)
        }

        eraserMaskLayer.contentsScale = maskImage.scale
        eraserMaskLayer.contents = maskImage.cgImage
    }

    private func rebindStore(oldValue: CanvasEditorStore?) {
        if let projectObserverID {
            oldValue?.removeObserver(projectObserverID)
        }
        if let selectionObserverID {
            oldValue?.removeObserver(selectionObserverID)
        }

        projectObserverID = store?.observeProject { [weak self] project in
            self?.renderProject(project)
        }
        selectionObserverID = store?.observeSelection { [weak self] selectedNodeID in
            guard let self else { return }
            if let editingNodeID = self.editingNodeID, editingNodeID != selectedNodeID {
                self.endInlineEditing()
            }
            self.syncNodePresentation()
            self.updateSelectionOverlay()
            self.updateInlineTextEditor()
        }
    }

    private func syncNodePresentation() {
        guard let store else {
            return
        }

        let sortedNodes = store.project.sortedNodes
        let selectedNodeIndex = store.selectedNodeID.flatMap { selectedNodeID in
            sortedNodes.firstIndex(where: { $0.id == selectedNodeID })
        }

        if let selectedNodeIndex {
            for node in sortedNodes[..<selectedNodeIndex] {
                guard let nodeView = nodeViews[node.id] else {
                    continue
                }
                lowerNodeContainerView.addSubview(nodeView)
            }

            if let selectedNodeView = nodeViews[sortedNodes[selectedNodeIndex].id] {
                selectedNodeHostView.addSubview(selectedNodeView)
            }

            for node in sortedNodes[(selectedNodeIndex + 1)...] {
                guard let nodeView = nodeViews[node.id] else {
                    continue
                }
                upperNodeContainerView.addSubview(nodeView)
            }
        } else {
            for node in sortedNodes {
                guard let nodeView = nodeViews[node.id] else {
                    continue
                }
                lowerNodeContainerView.addSubview(nodeView)
            }
        }

        updateInlineEditingVisibility()
    }

    private func updateSelectionOverlay() {
        guard let store,
              let selectedNodeID = store.selectedNodeID,
              let selectedView = nodeViews[selectedNodeID],
              let selectedNode = store.selectedNode else {
            selectionOverlay.isHidden = true
            [deleteHandle, widthHandle, heightHandle, transformHandle].forEach { $0.isHidden = true }
            return
        }

        selectionOverlay.apply(node: selectedNode)
        let overlayInset = selectionOverlay.contentInset
        let overlaySize = CGSize(
            width: selectedView.bounds.width + (overlayInset * 2),
            height: selectedView.bounds.height + (overlayInset * 2)
        )
        let selectedCenter = selectedView.superview?.convert(selectedView.center, to: canvasContainerView) ?? selectedView.center

        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectionOverlay.bounds = CGRect(origin: .zero, size: overlaySize)
            selectionOverlay.center = selectedCenter
            selectionOverlay.transform = selectedView.transform
            selectionOverlay.isHidden = false
            selectionOverlay.layer.removeAllAnimations()
            CATransaction.commit()
        }
        canvasContainerView.bringSubviewToFront(selectionOverlay)

        let selectionRect = selectionOverlay.selectionRect
        deleteHandle.center = selectionOverlay.convert(CGPoint(x: selectionRect.minX, y: selectionRect.minY), to: canvasContainerView)
        widthHandle.center = selectionOverlay.convert(CGPoint(x: selectionRect.maxX, y: selectionRect.minY), to: canvasContainerView)
        heightHandle.center = selectionOverlay.convert(CGPoint(x: selectionRect.minX, y: selectionRect.maxY), to: canvasContainerView)
        transformHandle.center = selectionOverlay.convert(CGPoint(x: selectionRect.maxX, y: selectionRect.maxY), to: canvasContainerView)

        deleteHandle.isHidden = false
        transformHandle.isHidden = false
        widthHandle.isHidden = selectedNode.kind != .text
        heightHandle.isHidden = selectedNode.kind != .text

        [deleteHandle, widthHandle, heightHandle, transformHandle].forEach {
            $0.transform = .identity
            canvasContainerView.bringSubviewToFront($0)
        }
    }

    private func updateInlineTextEditor(forceTextRefresh: Bool = false) {
        guard let editingNodeID,
              let store,
              let node = store.project.nodes.first(where: { $0.id == editingNodeID }),
              node.kind == .text || node.kind == .emoji else {
            inlineTextView.isHidden = true
            activeEditingStyle = nil
            return
        }

        let style = node.style ?? (node.kind == .emoji ? .defaultEmoji : .defaultText)
        let targetSize = CGSize(
            width: max(node.size.width - (textContentInset * 2), 40),
            height: max(node.size.height - (textContentInset * 2), 30)
        )

        inlineTextView.bounds = CGRect(origin: .zero, size: targetSize)
        inlineTextView.center = node.transform.position.cgPoint
        inlineTextView.transform = CGAffineTransform(rotationAngle: node.transform.rotation)
            .scaledBy(x: node.transform.scale, y: node.transform.scale)
        inlineTextView.backgroundColor = style.resolvedBackgroundUIColor ?? .clear
        inlineTextView.layer.cornerRadius = style.backgroundFill == nil ? 0 : 16
        inlineTextView.tintColor = style.foregroundColor.uiColor
        inlineTextView.textAlignment = style.alignment.nsTextAlignment

        let currentSelection = inlineTextView.selectedRange
        let requiresTextRefresh = forceTextRefresh ||
            inlineTextView.text != (node.text ?? "") ||
            activeEditingStyle != style
        if requiresTextRefresh {
            isApplyingInlineEditorState = true
            inlineTextView.attributedText = style.attributedString(text: node.text ?? "")
            inlineTextView.typingAttributes = style.textAttributes()
            let clampedLocation = min(currentSelection.location, (inlineTextView.text as NSString).length)
            inlineTextView.selectedRange = NSRange(location: clampedLocation, length: 0)
            isApplyingInlineEditorState = false
            activeEditingStyle = style
        }

        inlineTextView.isHidden = false
        canvasContainerView.bringSubviewToFront(inlineTextView)
    }

    private func updateInlineEditingVisibility() {
        nodeViews.values.forEach { $0.isHidden = false }
        guard let editingNodeID else {
            inlineTextView.isHidden = true
            return
        }
        nodeViews[editingNodeID]?.isHidden = true
    }

    private func endInlineEditingWithoutResigning() {
        guard editingNodeID != nil else {
            return
        }
        editingNodeID = nil
        activeEditingStyle = nil
        inlineTextView.isHidden = true
        syncNodePresentation()
        delegate?.canvasStageViewDidEndInlineEditing(self)
    }

    private func hitTestNode(at point: CGPoint) -> CanvasNode? {
        guard let store else {
            return nil
        }

        let canvasBounds = CGRect(origin: .zero, size: canvasSize)
        if !canvasBounds.contains(point) {
            guard let selectedNodeID = store.selectedNodeID,
                  let selectedNode = store.selectedNode,
                  selectedNode.id == selectedNodeID,
                  let selectedNodeView = nodeViews[selectedNodeID],
                  !selectedNodeView.isHidden else {
                return nil
            }

            let localPoint = selectedNodeView.convert(point, from: canvasContainerView)
            return selectedNodeView.point(inside: localPoint, with: nil) ? selectedNode : nil
        }

        for node in store.project.sortedNodes.reversed() {
            guard node.isEditable else {
                continue
            }
            guard let nodeView = nodeViews[node.id], !nodeView.isHidden else {
                continue
            }
            let localPoint = nodeView.convert(point, from: canvasContainerView)
            if nodeView.point(inside: localPoint, with: nil) {
                return node
            }
        }
        return nil
    }
}
