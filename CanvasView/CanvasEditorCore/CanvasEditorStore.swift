import CoreGraphics
import Foundation

public final class CanvasEditorStore {
    public typealias ProjectChange = (CanvasProject) -> Void
    public typealias SelectionChange = (String?) -> Void

    private var projectObservers: [UUID: ProjectChange] = [:]
    private var selectionObservers: [UUID: SelectionChange] = [:]

    public private(set) var project: CanvasProject {
        didSet {
            projectObservers.values.forEach { $0(project) }
        }
    }

    public private(set) var selectedNodeID: String? {
        didSet {
            selectionObservers.values.forEach { $0(selectedNodeID) }
        }
    }

    public let configuration: CanvasEditorConfiguration

    private var history = CanvasHistory<CanvasProject>()

    public init(template: CanvasTemplate, configuration: CanvasEditorConfiguration = .demo) {
        self.project = CanvasProject(template: template)
        self.configuration = configuration
    }

    public init(project: CanvasProject, configuration: CanvasEditorConfiguration = .demo) {
        self.project = project
        self.configuration = configuration
    }

    public var selectedNode: CanvasNode? {
        project.nodes.first(where: { $0.id == selectedNodeID && $0.isEditable })
    }

    public var layerPanelNodes: [CanvasNode] {
        Array(project.sortedNodes.reversed())
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    @discardableResult
    public func observeProject(_ observer: @escaping ProjectChange) -> UUID {
        let id = UUID()
        projectObservers[id] = observer
        observer(project)
        return id
    }

    @discardableResult
    public func observeSelection(_ observer: @escaping SelectionChange) -> UUID {
        let id = UUID()
        selectionObservers[id] = observer
        observer(selectedNodeID)
        return id
    }

    public func removeObserver(_ id: UUID) {
        projectObservers[id] = nil
        selectionObservers[id] = nil
    }

    public func replaceProject(_ project: CanvasProject, resetHistory: Bool = true) {
        self.project = project
        selectedNodeID = nil
        if resetHistory {
            history.reset()
        }
    }

    public func selectNode(_ id: String?) {
        guard id == nil || project.nodes.contains(where: { $0.id == id && $0.isEditable }) else {
            return
        }
        selectedNodeID = id
    }

    public func toggleNodeLock(_ nodeID: String) {
        guard let node = project.nodes.first(where: { $0.id == nodeID }) else {
            return
        }

        let shouldClearSelection = selectedNodeID == nodeID && node.isEditable
        guard commitMutation({ project in
            guard let index = project.nodes.firstIndex(where: { $0.id == nodeID }) else {
                return false
            }
            project.nodes[index].isEditable.toggle()
            return true
        }) else {
            return
        }

        if shouldClearSelection {
            selectedNodeID = nil
        } else {
            clearSelectionIfNeeded()
        }
    }

    public func moveNodeInLayerPanel(from sourceIndex: Int, to destinationIndex: Int) {
        let nodes = layerPanelNodes
        guard nodes.indices.contains(sourceIndex),
              nodes.indices.contains(destinationIndex) else {
            return
        }

        guard destinationIndex != sourceIndex else {
            return
        }

        _ = commitMutation { project in
            var topToBottomNodes = Array(project.sortedNodes.reversed())
            let movingNode = topToBottomNodes.remove(at: sourceIndex)
            topToBottomNodes.insert(movingNode, at: destinationIndex)
            project.nodes = Array(topToBottomNodes.reversed().enumerated().map { index, node in
                var copy = node
                copy.zIndex = index
                return copy
            })
            return true
        }
        clearSelectionIfNeeded()
    }

    public func addTextNode(text: String = "") {
        addNode(
            CanvasNode(
                kind: .text,
                name: "Text",
                transform: CanvasTransform(position: defaultNodePosition()),
                size: CanvasSize(width: 260, height: 140),
                zIndex: nextZIndex(),
                text: text,
                style: .defaultText
            )
        )
    }

    public func addEmojiNode(text: String = "✨") {
        addEmojiNodes(texts: [text])
    }

    public func addEmojiNodes(texts: [String]) {
        let normalizedTexts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedTexts.isEmpty else {
            return
        }

        let baseZIndex = nextZIndex()
        let nodes = normalizedTexts.enumerated().map { index, text in
            CanvasNode(
                kind: .emoji,
                name: "Emoji",
                transform: CanvasTransform(position: defaultImportedNodePosition(for: index)),
                size: CanvasSize(width: 160, height: 160),
                zIndex: baseZIndex + index,
                text: text,
                style: .defaultEmoji
            )
        }
        addNodes(nodes)
    }

    public func addStickerNode(source: CanvasAssetSource? = nil) {
        let resolvedSource = source ?? configuration.stickerCatalog.first?.source
        let baseZIndex = nextZIndex()
        let node = CanvasNode(
            kind: .sticker,
            name: "Sticker",
            transform: CanvasTransform(position: defaultNodePosition()),
            size: CanvasSize(width: 180, height: 180),
            zIndex: baseZIndex,
            source: resolvedSource,
            style: CanvasTextStyle.defaultText
        )
        addNode(node)
    }

    public func addStickerNodes(sources: [CanvasAssetSource]) {
        guard !sources.isEmpty else {
            return
        }

        let baseZIndex = nextZIndex()
        let nodes = sources.enumerated().map { index, source in
            CanvasNode(
                kind: .sticker,
                name: "Sticker",
                transform: CanvasTransform(position: defaultImportedNodePosition(for: index)),
                size: CanvasSize(width: 180, height: 180),
                zIndex: baseZIndex + index,
                source: source,
                style: CanvasTextStyle.defaultText
            )
        }
        addNodes(nodes)
    }

    public func addImageNode(source: CanvasAssetSource, intrinsicSize: CanvasSize? = nil) {
        let node = CanvasNode(
            kind: .image,
            name: "Image",
            transform: CanvasTransform(position: defaultNodePosition()),
            size: defaultImageNodeSize(for: intrinsicSize),
            zIndex: nextZIndex(),
            source: source
        )
        addNode(node)
    }

    public func addShapeNode(from draft: CanvasShapeDraft) {
        guard let normalizedShape = normalizeShapeNode(from: draft) else {
            return
        }

        let node = CanvasNode(
            kind: .shape,
            name: draft.type.displayTitle,
            transform: CanvasTransform(position: normalizedShape.position),
            size: normalizedShape.size,
            zIndex: nextZIndex(),
            opacity: draft.opacity,
            shape: normalizedShape.payload
        )
        addNode(node)
    }

    public func addEraserStroke(_ stroke: CanvasEraserStroke) {
        guard !stroke.points.isEmpty else {
            return
        }

        _ = commitMutation { project in
            project.eraserStrokes.append(stroke)
            return true
        }
    }

    public func updateSelectedText(_ text: String) {
        updateSelectedNode { node in
            node.text = text
        }
    }

    public func updateSelectedTextStyle(_ mutate: (inout CanvasTextStyle) -> Void) {
        updateSelectedNode { node in
            var style = node.style ?? fallbackTextStyle(for: node.kind)
            mutate(&style)
            node.style = style
        }
    }

    public func updateSelectedSource(_ source: CanvasAssetSource) {
        updateSelectedNode { node in
            node.source = source
        }
    }

    public func updateSelectedShapeStyle(
        type: CanvasShapeType,
        strokeColor: CanvasColor,
        strokeWidth: Double,
        opacity: Double
    ) {
        guard let selectedNodeID else {
            return
        }

        _ = commitMutation { project in
            guard let index = project.nodes.firstIndex(where: { $0.id == selectedNodeID }),
                  project.nodes[index].isEditable,
                  project.nodes[index].kind == .shape,
                  let currentShape = project.nodes[index].shape else {
                return false
            }

            let centeredPoints = currentShape.points.map {
                CGPoint(
                    x: CGFloat($0.x - (project.nodes[index].size.width / 2)),
                    y: CGFloat($0.y - (project.nodes[index].size.height / 2))
                )
            }

            guard let normalizedShape = Self.normalizeShapePayload(
                centeredPoints: centeredPoints,
                type: type,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth
            ) else {
                return false
            }

            project.nodes[index].name = type.displayTitle
            project.nodes[index].size = normalizedShape.size
            project.nodes[index].opacity = opacity
            project.nodes[index].shape = normalizedShape.payload
            return true
        }
    }

    public func moveSelectedNode(by delta: CanvasPoint) {
        updateSelectedNode { node in
            node.transform.position.x += delta.x
            node.transform.position.y += delta.y
        }
    }

    public func scaleSelectedNode(by multiplier: Double) {
        updateSelectedNode { node in
            node.transform.scale = max(0.2, min(6.0, node.transform.scale * multiplier))
        }
    }

    public func rotateSelectedNode(by radians: Double) {
        updateSelectedNode { node in
            node.transform.rotation += radians
        }
    }

    public func transformSelectedNode(scaleMultiplier: Double, rotationDelta: Double) {
        updateSelectedNode { node in
            node.transform.scale = max(0.2, min(6.0, node.transform.scale * scaleMultiplier))
            node.transform.rotation += rotationDelta
        }
    }

    public func adjustSelectedTextWidth(by widthDelta: Double) {
        updateSelectedNode { node in
            guard node.kind == .text else {
                return
            }

            let minimumWidth = 120.0
            let maximumWidth = max(project.canvasSize.width * 1.4, minimumWidth)
            let newWidth = min(max(node.size.width + widthDelta, minimumWidth), maximumWidth)
            let appliedDelta = newWidth - node.size.width
            guard appliedDelta != 0 else {
                return
            }

            node.size.width = newWidth

            let positionShift = (appliedDelta * node.transform.scale) / 2.0
            node.transform.position.x += cos(node.transform.rotation) * positionShift
            node.transform.position.y += sin(node.transform.rotation) * positionShift
        }
    }

    public func updateSelectedTextHeight(_ height: Double) {
        updateSelectedNode { node in
            guard node.kind == .text else {
                return
            }
            node.size.height = max(44, height)
        }
    }

    public func adjustSelectedTextHeight(by heightDelta: Double, minimumHeight: Double) {
        updateSelectedNode { node in
            guard node.kind == .text else {
                return
            }

            let minimum = max(44.0, minimumHeight)
            let maximum = max(project.canvasSize.height * 1.4, minimum)
            let newHeight = min(max(node.size.height + heightDelta, minimum), maximum)
            let appliedDelta = newHeight - node.size.height
            guard appliedDelta != 0 else {
                return
            }

            node.size.height = newHeight

            let positionShift = (appliedDelta * node.transform.scale) / 2.0
            node.transform.position.x += -sin(node.transform.rotation) * positionShift
            node.transform.position.y += cos(node.transform.rotation) * positionShift
        }
    }

    public func duplicateSelectedNode() {
        guard var node = selectedNode, node.isEditable else {
            return
        }
        node.id = UUID().uuidString
        node.name = "\(node.name ?? node.kind.rawValue.capitalized) Copy"
        node.transform.position.x += 28
        node.transform.position.y += 28
        node.zIndex = nextZIndex()
        addNode(node)
    }

    public func deleteSelectedNode() {
        guard let selectedNodeID,
              project.nodes.contains(where: { $0.id == selectedNodeID && $0.isEditable }) else {
            return
        }
        commitSelectionMutation(selectedNodeID: nil) { project in
            let previousCount = project.nodes.count
            project.nodes.removeAll(where: { $0.id == selectedNodeID })
            return project.nodes.count != previousCount
        }
    }

    public func bringSelectedNodeToFront() {
        guard let selectedNodeID,
              project.nodes.contains(where: { $0.id == selectedNodeID && $0.isEditable }) else {
            return
        }
        _ = commitMutation { project in
            guard let index = project.nodes.firstIndex(where: { $0.id == selectedNodeID }) else {
                return false
            }
            let maxZIndex = (project.nodes.map(\.zIndex).max() ?? -1) + 1
            project.nodes[index].zIndex = maxZIndex
            return true
        }
        selectNode(selectedNodeID)
    }

    public func sendSelectedNodeToBack() {
        guard let selectedNodeID,
              project.nodes.contains(where: { $0.id == selectedNodeID && $0.isEditable }) else {
            return
        }
        _ = commitMutation { project in
            guard let index = project.nodes.firstIndex(where: { $0.id == selectedNodeID }) else {
                return false
            }
            let minZIndex = (project.nodes.map(\.zIndex).min() ?? 0) - 1
            project.nodes[index].zIndex = minZIndex
            return true
        }
        selectNode(selectedNodeID)
    }

    public func undo() {
        guard let previous = history.undo(currentValue: project) else {
            return
        }
        project = previous
        clearSelectionIfNeeded()
    }

    public func redo() {
        guard let next = history.redo(currentValue: project) else {
            return
        }
        project = next
        clearSelectionIfNeeded()
    }

    public func encodedProjectData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(project)
    }

    private func addNode(_ node: CanvasNode) {
        addNodes([node])
    }

    private func addNodes(_ nodes: [CanvasNode]) {
        guard let lastNode = nodes.last else {
            return
        }
        commitSelectionMutation(selectedNodeID: lastNode.id) { project in
            project.nodes.append(contentsOf: nodes)
            return true
        }
    }

    private func updateSelectedNode(_ mutation: (inout CanvasNode) -> Void) {
        guard let selectedNodeID else {
            return
        }

        commitMutation { project in
            guard let index = project.nodes.firstIndex(where: { $0.id == selectedNodeID }),
                  project.nodes[index].isEditable else {
                return false
            }
            mutation(&project.nodes[index])
            return true
        }
    }

    private func commitSelectionMutation(selectedNodeID nextSelection: String?, _ mutation: (inout CanvasProject) -> Bool) {
        if commitMutation(mutation) {
            selectedNodeID = nextSelection
        }
    }

    @discardableResult
    private func commitMutation(_ mutation: (inout CanvasProject) -> Bool) -> Bool {
        var workingCopy = project
        guard mutation(&workingCopy) else {
            return false
        }
        workingCopy.nodes = workingCopy.sortedNodes.enumerated().map { index, node in
            var copy = node
            copy.zIndex = index
            return copy
        }
        workingCopy.metadata.modifiedAt = Date()
        history.record(currentValue: project)
        project = workingCopy
        return true
    }

    private func clearSelectionIfNeeded() {
        if let selectedNodeID,
           !project.nodes.contains(where: { $0.id == selectedNodeID && $0.isEditable }) {
            self.selectedNodeID = nil
        }
    }

    private func nextZIndex() -> Int {
        (project.nodes.map(\.zIndex).max() ?? -1) + 1
    }

    private func defaultNodePosition() -> CanvasPoint {
        CanvasPoint(
            x: project.canvasSize.width / 2,
            y: project.canvasSize.height / 2
        )
    }

    private func defaultImportedNodePosition(for index: Int) -> CanvasPoint {
        let base = defaultNodePosition()
        let offset = Double(index % 6) * 28
        let rowOffset = Double(index / 6) * 20
        return CanvasPoint(
            x: base.x + offset,
            y: base.y + offset + rowOffset
        )
    }

    private func fallbackTextStyle(for kind: CanvasNodeKind) -> CanvasTextStyle {
        switch kind {
        case .emoji:
            return .defaultEmoji
        default:
            return .defaultText
        }
    }

    private func defaultImageNodeSize(for intrinsicSize: CanvasSize?) -> CanvasSize {
        guard let intrinsicSize,
              intrinsicSize.width > 0,
              intrinsicSize.height > 0 else {
            return CanvasSize(width: 220, height: 220)
        }

        let maxWidth = max(project.canvasSize.width * 0.42, 120)
        let maxHeight = max(project.canvasSize.height * 0.42, 120)
        let widthScale = maxWidth / intrinsicSize.width
        let heightScale = maxHeight / intrinsicSize.height
        let scale = min(widthScale, heightScale)

        return CanvasSize(
            width: max(intrinsicSize.width * scale, 48),
            height: max(intrinsicSize.height * scale, 48)
        )
    }

    private func normalizeShapeNode(from draft: CanvasShapeDraft) -> (position: CanvasPoint, size: CanvasSize, payload: CanvasShapePayload)? {
        let canvasPoints = draft.points.map(\.cgPoint)
        guard let geometry = Self.normalizeCanvasShapePoints(
            canvasPoints,
            type: draft.type,
            strokeColor: draft.strokeColor,
            strokeWidth: draft.strokeWidth
        ) else {
            return nil
        }

        return (
            position: CanvasPoint(x: geometry.bounds.midX, y: geometry.bounds.midY),
            size: CanvasSize(geometry.bounds.size),
            payload: geometry.payload
        )
    }

    private static func normalizeCanvasShapePoints(
        _ points: [CGPoint],
        type: CanvasShapeType,
        strokeColor: CanvasColor,
        strokeWidth: Double
    ) -> (bounds: CGRect, payload: CanvasShapePayload)? {
        guard let paddedBounds = paddedShapeBounds(for: points, type: type, strokeWidth: strokeWidth) else {
            return nil
        }

        let localPoints = points.map { point in
            CanvasPoint(
                x: point.x - paddedBounds.minX,
                y: point.y - paddedBounds.minY
            )
        }

        return (
            bounds: paddedBounds,
            payload: CanvasShapePayload(
                type: type,
                points: localPoints,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth
            )
        )
    }

    private static func normalizeShapePayload(
        centeredPoints: [CGPoint],
        type: CanvasShapeType,
        strokeColor: CanvasColor,
        strokeWidth: Double
    ) -> (size: CanvasSize, payload: CanvasShapePayload)? {
        guard !centeredPoints.isEmpty else {
            return nil
        }

        let semanticBounds = shapeBounds(for: centeredPoints, type: type)
        let centerOffset = CGPoint(x: semanticBounds.midX, y: semanticBounds.midY)
        let recenteredPoints = centeredPoints.map { point in
            CGPoint(x: point.x - centerOffset.x, y: point.y - centerOffset.y)
        }

        guard let paddedBounds = paddedShapeBounds(for: recenteredPoints, type: type, strokeWidth: strokeWidth) else {
            return nil
        }

        let localPoints = recenteredPoints.map { point in
            CanvasPoint(
                x: point.x - paddedBounds.minX,
                y: point.y - paddedBounds.minY
            )
        }

        return (
            size: CanvasSize(paddedBounds.size),
            payload: CanvasShapePayload(
                type: type,
                points: localPoints,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth
            )
        )
    }

    private static func paddedShapeBounds(for points: [CGPoint], type: CanvasShapeType, strokeWidth: Double) -> CGRect? {
        guard !points.isEmpty else {
            return nil
        }

        let semanticBounds = shapeBounds(for: points, type: type)
        let padding = max(CGFloat(strokeWidth) / 2, 2) + 2
        let paddedBounds = semanticBounds.insetBy(dx: -padding, dy: -padding)
        let minimumSize = max(CGFloat(strokeWidth) + 4, 8)

        let width = max(paddedBounds.width, minimumSize)
        let height = max(paddedBounds.height, minimumSize)

        return CGRect(
            x: paddedBounds.midX - (width / 2),
            y: paddedBounds.midY - (height / 2),
            width: width,
            height: height
        )
    }

    private static func shapeBounds(for points: [CGPoint], type: CanvasShapeType) -> CGRect {
        switch type {
        case .brush:
            return points.reduce(into: CGRect.null) { partialResult, point in
                partialResult = partialResult.union(CGRect(origin: point, size: .zero))
            }
        case .line, .arrow:
            guard let first = points.first, let last = points.last else {
                return .null
            }
            return CGRect(
                x: min(first.x, last.x),
                y: min(first.y, last.y),
                width: abs(last.x - first.x),
                height: abs(last.y - first.y)
            )
        case .oval, .rectangle:
            if points.count == 2, let first = points.first, let last = points.last {
                return CGRect(
                    x: min(first.x, last.x),
                    y: min(first.y, last.y),
                    width: abs(last.x - first.x),
                    height: abs(last.y - first.y)
                )
            }
            return points.reduce(into: CGRect.null) { partialResult, point in
                partialResult = partialResult.union(CGRect(origin: point, size: .zero))
            }
        }
    }
}
