import Foundation

public struct CanvasProjectSummary: Hashable, Sendable {
    public var nodeCount: Int
    public var canvasSize: CanvasSize
    public var containsInlineImages: Bool

    public init(project: CanvasProject) {
        self.nodeCount = project.nodes.count
        self.canvasSize = project.canvasSize
        self.containsInlineImages =
            project.background.source?.kind == .inlineImage ||
            project.nodes.contains(where: { $0.source?.kind == .inlineImage })
    }
}

public extension CanvasProject {
    var summary: CanvasProjectSummary {
        CanvasProjectSummary(project: self)
    }
}
