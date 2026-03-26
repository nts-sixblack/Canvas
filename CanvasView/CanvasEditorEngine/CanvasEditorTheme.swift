import UIKit

enum CanvasEditorTheme {
    static let canvasBackdrop = UIColor(hex: 0xF3F4F8)
    static let sheetSurface = UIColor(hex: 0xF3F4F8)
    static let cardSurface = UIColor.white
    static let primaryText = UIColor(red: 0.22, green: 0.24, blue: 0.31, alpha: 1)
    static let secondaryText = UIColor(red: 0.54, green: 0.58, blue: 0.68, alpha: 1)
    static let tertiaryText = UIColor(red: 0.68, green: 0.71, blue: 0.79, alpha: 1)
    static let separator = UIColor(red: 0.87, green: 0.89, blue: 0.94, alpha: 1)
    static let accent = UIColor(red: 0.33, green: 0.52, blue: 0.96, alpha: 1)
    static let accentMuted = UIColor(red: 0.33, green: 0.52, blue: 0.96, alpha: 0.12)
    static let destructive = UIColor(red: 0.98, green: 0.23, blue: 0.28, alpha: 1)
    static let success = UIColor(red: 0.2, green: 0.74, blue: 0.32, alpha: 1)
    static let scrim = UIColor.black.withAlphaComponent(0.6)
    static let controlShadow = UIColor.black.withAlphaComponent(0.08)
    static let surfaceShadow = UIColor.black.withAlphaComponent(0.12)
}

extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension UIView {
    func applyCanvasEditorCardStyle(
        backgroundColor: UIColor = CanvasEditorTheme.cardSurface,
        cornerRadius: CGFloat = 20,
        borderColor: UIColor = CanvasEditorTheme.separator,
        borderWidth: CGFloat = 1,
        shadowColor: UIColor = CanvasEditorTheme.controlShadow,
        shadowOpacity: Float = 1,
        shadowRadius: CGFloat = 14,
        shadowOffset: CGSize = CGSize(width: 0, height: 8)
    ) {
        self.backgroundColor = backgroundColor
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.borderColor = borderColor.cgColor
        layer.borderWidth = borderWidth
        layer.shadowColor = shadowColor.cgColor
        layer.shadowOpacity = shadowOpacity
        layer.shadowRadius = shadowRadius
        layer.shadowOffset = shadowOffset
    }
}
