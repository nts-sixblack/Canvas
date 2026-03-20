import CoreGraphics
import Foundation

public struct CanvasViewportLayout: Equatable, Sendable {
    public var canvasFrame: CGRect
    public var scale: CGFloat

    public init(canvasFrame: CGRect, scale: CGFloat) {
        self.canvasFrame = canvasFrame
        self.scale = scale
    }
}

public enum CanvasViewportMath {
    public static func fit(canvasSize: CGSize, in bounds: CGRect, padding: CGFloat) -> CanvasViewportLayout {
        guard bounds.width > 0, bounds.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return CanvasViewportLayout(canvasFrame: .zero, scale: 1)
        }

        let availableWidth = max(bounds.width - (padding * 2), 1)
        let availableHeight = max(bounds.height - (padding * 2), 1)
        let scale = min(availableWidth / canvasSize.width, availableHeight / canvasSize.height)
        let fittedSize = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        let origin = CGPoint(
            x: bounds.midX - (fittedSize.width / 2),
            y: bounds.midY - (fittedSize.height / 2)
        )
        return CanvasViewportLayout(canvasFrame: CGRect(origin: origin, size: fittedSize), scale: scale)
    }
}
