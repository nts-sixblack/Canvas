import UIKit

enum CanvasEditorRenderer {
    static func render(project: CanvasProject, assetLoader: CanvasAssetLoader) -> UIImage {
        let renderSize = project.canvasSize.cgSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { context in
            let canvasRect = CGRect(origin: .zero, size: renderSize)
            let cgContext = context.cgContext
            cgContext.interpolationQuality = .high

            drawBackground(project.background, in: canvasRect, assetLoader: assetLoader)

            for node in project.sortedNodes {
                draw(node: node, assetLoader: assetLoader, in: cgContext)
            }

            CanvasEraserPathBuilder.applyClearStrokes(project.eraserStrokes, in: cgContext)
        }
    }

    private static func drawBackground(_ background: CanvasBackground, in rect: CGRect, assetLoader: CanvasAssetLoader) {
        background.color?.uiColor.setFill()
        UIRectFill(rect)

        guard background.kind == .image,
              let image = assetLoader.imageSynchronously(for: background.source) else {
            return
        }

        image.draw(in: aspectFillRect(for: image.size, in: rect))
    }

    private static func draw(node: CanvasNode, assetLoader: CanvasAssetLoader, in context: CGContext) {
        let nodeRect = CGRect(
            x: -node.size.width / 2,
            y: -node.size.height / 2,
            width: node.size.width,
            height: node.size.height
        )

        context.saveGState()
        context.translateBy(x: node.transform.position.x, y: node.transform.position.y)
        context.rotate(by: node.transform.rotation)
        context.scaleBy(x: node.transform.scale, y: node.transform.scale)
        context.setAlpha(node.opacity)

        switch node.kind {
        case .text, .emoji:
            drawTextNode(node, in: nodeRect)
        case .sticker, .image:
            drawImageNode(node, assetLoader: assetLoader, in: nodeRect)
        case .shape:
            drawShapeNode(node, in: context)
        }

        context.restoreGState()
    }

    private static func drawTextNode(_ node: CanvasNode, in rect: CGRect) {
        let style = node.style ?? (node.kind == .emoji ? .defaultEmoji : .defaultText)
        let textRect = rect.insetBy(dx: 8, dy: 8)

        if let backgroundColor = style.resolvedBackgroundUIColor {
            backgroundColor.setFill()
            UIBezierPath(roundedRect: textRect, cornerRadius: 16).fill()
        }

        let text = node.text ?? ""
        style.attributedString(text: text).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }

    private static func drawImageNode(_ node: CanvasNode, assetLoader: CanvasAssetLoader, in rect: CGRect) {
        guard let image = assetLoader.imageSynchronously(for: node.source) else {
            let placeholderRect = rect.insetBy(dx: 4, dy: 4)
            UIColor.white.withAlphaComponent(0.12).setFill()
            UIColor.white.withAlphaComponent(0.3).setStroke()
            let placeholderPath = UIBezierPath(roundedRect: placeholderRect, cornerRadius: 18)
            placeholderPath.lineWidth = 1
            placeholderPath.fill()
            placeholderPath.stroke()
            return
        }

        if node.source?.kind == .symbol {
            let symbolConfig = UIImage.SymbolConfiguration(
                pointSize: max(rect.width, rect.height) * 0.6,
                weight: .bold
            )
            let tintedSymbol = image
                .applyingSymbolConfiguration(symbolConfig)?
                .withTintColor(node.style?.foregroundColor.uiColor ?? .white, renderingMode: .alwaysOriginal)

            let renderedSymbol = tintedSymbol ?? image
            renderedSymbol.draw(in: aspectFitRect(for: renderedSymbol.size, in: rect))
            return
        }

        image.draw(in: aspectFitRect(for: image.size, in: rect))
    }

    private static func drawShapeNode(_ node: CanvasNode, in context: CGContext) {
        guard let payload = node.shape else {
            return
        }

        let path = payload.bezierPath()
        context.saveGState()
        context.translateBy(x: -node.size.width / 2, y: -node.size.height / 2)
        context.addPath(path.cgPath)
        context.setStrokeColor(payload.strokeColor.uiColor.cgColor)
        context.setLineWidth(payload.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func aspectFitRect(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let fittedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - (fittedSize.width / 2),
            y: bounds.midY - (fittedSize.height / 2),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private static func aspectFillRect(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = max(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let filledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - (filledSize.width / 2),
            y: bounds.midY - (filledSize.height / 2),
            width: filledSize.width,
            height: filledSize.height
        )
    }
}
