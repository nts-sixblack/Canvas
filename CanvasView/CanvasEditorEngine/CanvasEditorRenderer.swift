import UIKit

enum CanvasEditorRenderer {
    static func render(project: CanvasProject, assetLoader: CanvasAssetLoader) -> UIImage {
        let renderSize = project.canvasSize.cgSize
        let canvasView = UIView(frame: CGRect(origin: .zero, size: renderSize))
        canvasView.backgroundColor = .clear

        let backgroundView = UIView(frame: canvasView.bounds)
        backgroundView.backgroundColor = project.background.color?.uiColor ?? .clear
        canvasView.addSubview(backgroundView)

        if project.background.kind == .image {
            let imageView = UIImageView(frame: canvasView.bounds)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.image = assetLoader.imageSynchronously(for: project.background.source)
            canvasView.addSubview(imageView)
        }

        project.sortedNodes.forEach { node in
            let nodeView = CanvasNodeView(frame: .zero)
            nodeView.apply(node: node, assetLoader: assetLoader)
            canvasView.addSubview(nodeView)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { _ in
            canvasView.drawHierarchy(in: canvasView.bounds, afterScreenUpdates: true)
        }
    }
}
