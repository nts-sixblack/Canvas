import UIKit

protocol CanvasStageViewDelegate: AnyObject {
    func canvasStageViewDidTapSelectedTextNode(_ stageView: CanvasStageView)
    func canvasStageViewDidBeginInlineEditing(_ stageView: CanvasStageView)
    func canvasStageViewDidEndInlineEditing(_ stageView: CanvasStageView)
    func canvasStageViewDidBeginNodeManipulation(_ stageView: CanvasStageView)
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
    private let backgroundColorView = UIView()
    private let backgroundImageView = UIImageView()
    private let nodeContainerView = UIView()
    private let selectionOverlay = CanvasSelectionOverlayView()
    private let inlineTextView = UITextView()

    private let deleteHandle = OverlayHandleControl(systemImage: "xmark", tintColor: .systemRed)
    private let widthHandle = OverlayHandleControl(systemImage: "arrow.left.and.right")
    private let heightHandle = OverlayHandleControl(systemImage: "arrow.up.and.down")
    private let transformHandle = OverlayHandleControl(systemImage: "arrow.up.left.and.arrow.down.right")

    private var projectObserverID: UUID?
    private var selectionObserverID: UUID?
    private var nodeViews: [String: CanvasNodeView] = [:]

    private var canvasSize: CGSize = .zero
    private var canvasScale: CGFloat = 1
    private var activePanTranslation: CGPoint = .zero
    private var lastTransformVector: CGPoint?
    private var lastTextWidthTranslation: CGPoint = .zero
    private var lastTextHeightTranslation: CGPoint = .zero
    private var editingNodeID: String?
    private var activeEditingStyle: CanvasTextStyle?
    private var isApplyingInlineEditorState = false

    private let viewportPadding: CGFloat = 28
    private let textContentInset: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)

        canvasContainerView.backgroundColor = .clear
        canvasContainerView.layer.shadowColor = UIColor.black.cgColor
        canvasContainerView.layer.shadowOpacity = 0.3
        canvasContainerView.layer.shadowRadius = 18
        canvasContainerView.layer.shadowOffset = CGSize(width: 0, height: 10)

        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true

        selectionOverlay.isHidden = true

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

        addSubview(canvasContainerView)
        canvasContainerView.addSubview(backgroundColorView)
        canvasContainerView.addSubview(backgroundImageView)
        canvasContainerView.addSubview(nodeContainerView)
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        tap.require(toFail: doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))

        [tap, doubleTap, pan, pinch, rotation].forEach {
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

        backgroundColorView.frame = CGRect(origin: .zero, size: canvasSize)
        backgroundImageView.frame = CGRect(origin: .zero, size: canvasSize)
        nodeContainerView.frame = CGRect(origin: .zero, size: canvasSize)

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
            nodeContainerView.addSubview(nodeView)
            nodeViews[node.id] = nodeView
        }

        applyInlineEditingState()
        canvasContainerView.bringSubviewToFront(selectionOverlay)
        canvasContainerView.bringSubviewToFront(inlineTextView)
        [deleteHandle, widthHandle, heightHandle, transformHandle].forEach {
            canvasContainerView.bringSubviewToFront($0)
        }
        setNeedsLayout()
        layoutIfNeeded()
        updateSelectionOverlay()
        updateInlineTextEditor()
    }

    func beginInlineEditingForSelectedNode(placeCursorAtEnd: Bool = true) {
        guard let node = store?.selectedNode, node.kind == .text || node.kind == .emoji else {
            return
        }
        editingNodeID = node.id
        activeEditingStyle = node.style
        delegate?.canvasStageViewDidBeginInlineEditing(self)
        applyInlineEditingState()
        updateInlineTextEditor(forceTextRefresh: true)

        let targetOffset = placeCursorAtEnd ? (inlineTextView.text as NSString).length : 0
        inlineTextView.selectedRange = NSRange(location: targetOffset, length: 0)
        inlineTextView.becomeFirstResponder()
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

        if editingNodeID != nil, tappedNode?.id != editingNodeID {
            endInlineEditing()
        }

        store?.selectNode(tappedNode?.id)
        if tappedSelectedTextNode, editingNodeID == nil {
            delegate?.canvasStageViewDidTapSelectedTextNode(self)
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
            let location = gestureRecognizer.location(in: canvasContainerView)
            if let node = hitTestNode(at: location) {
                if editingNodeID != nil, editingNodeID != node.id {
                    endInlineEditing()
                }
                delegate?.canvasStageViewDidBeginNodeManipulation(self)
                store.selectNode(node.id)
            }

        case .changed:
            guard store.selectedNode != nil else {
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
        }
    }

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        guard let store else {
            return
        }

        if gestureRecognizer.state == .began {
            let location = gestureRecognizer.location(in: canvasContainerView)
            if let node = hitTestNode(at: location) {
                if editingNodeID != nil, editingNodeID != node.id {
                    endInlineEditing()
                }
                delegate?.canvasStageViewDidBeginNodeManipulation(self)
                store.selectNode(node.id)
            }
        }

        guard store.selectedNode != nil else {
            return
        }

        store.scaleSelectedNode(by: gestureRecognizer.scale)
        gestureRecognizer.scale = 1
    }

    @objc
    private func handleRotation(_ gestureRecognizer: UIRotationGestureRecognizer) {
        guard let store else {
            return
        }

        if gestureRecognizer.state == .began {
            let location = gestureRecognizer.location(in: canvasContainerView)
            if let node = hitTestNode(at: location) {
                if editingNodeID != nil, editingNodeID != node.id {
                    endInlineEditing()
                }
                delegate?.canvasStageViewDidBeginNodeManipulation(self)
                store.selectNode(node.id)
            }
        }

        guard store.selectedNode != nil else {
            return
        }

        store.rotateSelectedNode(by: gestureRecognizer.rotation)
        gestureRecognizer.rotation = 0
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

    private func handleDeleteTapped() {
        endInlineEditing()
        store?.deleteSelectedNode()
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
            self.updateSelectionOverlay()
            self.applyInlineEditingState()
            self.updateInlineTextEditor()
        }
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

        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectionOverlay.bounds = CGRect(origin: .zero, size: overlaySize)
            selectionOverlay.center = selectedView.center
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
        inlineTextView.backgroundColor = style.backgroundFill?.color.uiColor.withAlphaComponent(style.opacity * 0.35) ?? .clear
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

    private func applyInlineEditingState() {
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
        applyInlineEditingState()
        delegate?.canvasStageViewDidEndInlineEditing(self)
    }

    private func hitTestNode(at point: CGPoint) -> CanvasNode? {
        guard let store else {
            return nil
        }

        for node in store.project.sortedNodes.reversed() {
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
