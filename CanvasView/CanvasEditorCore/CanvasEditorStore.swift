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
        project.nodes.first(where: { $0.id == selectedNodeID })
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
        guard id == nil || project.nodes.contains(where: { $0.id == id }) else {
            return
        }
        selectedNodeID = id
    }

    public func addTextNode(text: String = "") {
        let node = CanvasNode(
            kind: .text,
            name: "Text",
            transform: CanvasTransform(position: defaultNodePosition()),
            size: CanvasSize(width: 260, height: 140),
            zIndex: nextZIndex(),
            text: text,
            style: .defaultText
        )
        addNode(node)
    }

    public func addEmojiNode(text: String = "✨") {
        let node = CanvasNode(
            kind: .emoji,
            name: "Emoji",
            transform: CanvasTransform(position: defaultNodePosition()),
            size: CanvasSize(width: 160, height: 160),
            zIndex: nextZIndex(),
            text: text,
            style: .defaultEmoji
        )
        addNode(node)
    }

    public func addStickerNode(source: CanvasAssetSource? = nil) {
        let node = CanvasNode(
            kind: .sticker,
            name: "Sticker",
            transform: CanvasTransform(position: defaultNodePosition()),
            size: CanvasSize(width: 180, height: 180),
            zIndex: nextZIndex(),
            source: source ?? configuration.stickerCatalog.first?.source,
            style: CanvasTextStyle.defaultText
        )
        addNode(node)
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
        guard var node = selectedNode else {
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
        guard let selectedNodeID else {
            return
        }
        commitSelectionMutation(selectedNodeID: nil) { project in
            let previousCount = project.nodes.count
            project.nodes.removeAll(where: { $0.id == selectedNodeID })
            return project.nodes.count != previousCount
        }
    }

    public func bringSelectedNodeToFront() {
        guard let selectedNodeID else {
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
        guard let selectedNodeID else {
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
        if let selectedNodeID, !project.nodes.contains(where: { $0.id == selectedNodeID }) {
            self.selectedNodeID = nil
        }
    }

    public func redo() {
        guard let next = history.redo(currentValue: project) else {
            return
        }
        project = next
        if let selectedNodeID, !project.nodes.contains(where: { $0.id == selectedNodeID }) {
            self.selectedNodeID = nil
        }
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
        commitSelectionMutation(selectedNodeID: node.id) { project in
            project.nodes.append(node)
            return true
        }
    }

    private func updateSelectedNode(_ mutation: (inout CanvasNode) -> Void) {
        guard let selectedNodeID else {
            return
        }

        commitMutation { project in
            guard let index = project.nodes.firstIndex(where: { $0.id == selectedNodeID }) else {
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
    private func nextZIndex() -> Int {
        (project.nodes.map(\.zIndex).max() ?? -1) + 1
    }

    private func defaultNodePosition() -> CanvasPoint {
        CanvasPoint(
            x: project.canvasSize.width / 2,
            y: project.canvasSize.height / 2
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
}
