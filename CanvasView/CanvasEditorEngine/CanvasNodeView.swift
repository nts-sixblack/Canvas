import UIKit

final class CanvasNodeView: UIView {
    private let textLabel = UILabel()
    private let imageView = UIImageView()
    private let shapeLayer = CAShapeLayer()
    private let placeholderView = UIView()
    private let placeholderLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private(set) var nodeID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false

        textLabel.numberOfLines = 0
        textLabel.adjustsFontSizeToFitWidth = false

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        placeholderView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        placeholderView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        placeholderView.layer.borderWidth = 1
        placeholderView.layer.cornerRadius = 18

        placeholderLabel.text = "Image"
        placeholderLabel.textAlignment = .center
        placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        placeholderLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)

        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true

        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        layer.addSublayer(shapeLayer)

        addSubview(placeholderView)
        placeholderView.addSubview(placeholderLabel)
        placeholderView.addSubview(loadingIndicator)
        addSubview(imageView)
        addSubview(textLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insetBounds = bounds.insetBy(dx: 8, dy: 8)
        shapeLayer.frame = bounds
        textLabel.frame = insetBounds
        imageView.frame = bounds
        placeholderView.frame = bounds
        placeholderLabel.frame = placeholderView.bounds.insetBy(dx: 12, dy: 12)
        loadingIndicator.center = CGPoint(x: placeholderView.bounds.midX, y: placeholderView.bounds.midY - 10)
        placeholderView.layer.cornerRadius = max(18, min(bounds.width, bounds.height) * 0.12)
    }

    func apply(node: CanvasNode, assetLoader: CanvasAssetLoader) {
        nodeID = node.id
        accessibilityIdentifier = node.id
        bounds = CGRect(origin: .zero, size: node.size.cgSize)
        center = node.transform.position.cgPoint
        alpha = CGFloat(node.opacity)
        transform = CGAffineTransform(rotationAngle: node.transform.rotation)
            .scaledBy(x: node.transform.scale, y: node.transform.scale)

        switch node.kind {
        case .text, .emoji:
            applyText(node: node)
            shapeLayer.isHidden = true
            imageView.isHidden = true
            placeholderView.isHidden = true
            textLabel.isHidden = false

        case .sticker, .image:
            applyImage(node: node, assetLoader: assetLoader)
            shapeLayer.isHidden = true
            textLabel.isHidden = true
            imageView.isHidden = false

        case .shape:
            applyShape(node: node)
            textLabel.isHidden = true
            imageView.isHidden = true
        }
    }

    private func applyText(node: CanvasNode) {
        let style = node.style ?? (node.kind == .emoji ? .defaultEmoji : .defaultText)
        textLabel.attributedText = style.attributedString(text: node.text ?? "")
        textLabel.backgroundColor = style.backgroundFill?.color.uiColor.withAlphaComponent(style.opacity * 0.35)
        textLabel.layer.cornerRadius = style.backgroundFill == nil ? 0 : 16
        textLabel.clipsToBounds = style.backgroundFill != nil
    }

    private func applyImage(node: CanvasNode, assetLoader: CanvasAssetLoader) {
        placeholderView.isHidden = false
        imageView.image = nil
        imageView.tintColor = node.style?.foregroundColor.uiColor ?? .white
        placeholderLabel.text = "Loading..."
        loadingIndicator.startAnimating()

        if node.source?.kind == .symbol {
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: max(bounds.width, bounds.height) * 0.6,
                weight: .bold
            )
            imageView.contentMode = .scaleAspectFit
        } else {
            imageView.preferredSymbolConfiguration = nil
            imageView.contentMode = .scaleAspectFit
        }

        assetLoader.image(for: node.source) { [weak self] image in
            guard let self, self.nodeID == node.id else {
                return
            }
            self.imageView.image = image
            self.loadingIndicator.stopAnimating()
            self.placeholderLabel.text = image == nil ? "Image" : ""
            self.placeholderView.isHidden = image != nil
        }
    }

    private func applyShape(node: CanvasNode) {
        shapeLayer.isHidden = false
        imageView.isHidden = true
        placeholderView.isHidden = true
        textLabel.isHidden = true
        loadingIndicator.stopAnimating()

        guard let payload = node.shape else {
            shapeLayer.path = nil
            return
        }

        shapeLayer.strokeColor = payload.strokeColor.uiColor.cgColor
        shapeLayer.lineWidth = payload.strokeWidth
        shapeLayer.path = payload.bezierPath().cgPath
    }
}
