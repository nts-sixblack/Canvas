import Foundation

public struct CanvasColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: String, alpha: Double = 1.0) {
        let sanitized = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        switch sanitized.count {
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0,
                alpha: alpha
            )
        case 8:
            self.init(
                red: Double((value >> 24) & 0xFF) / 255.0,
                green: Double((value >> 16) & 0xFF) / 255.0,
                blue: Double((value >> 8) & 0xFF) / 255.0,
                alpha: Double(value & 0xFF) / 255.0
            )
        default:
            self.init(red: 1, green: 1, blue: 1, alpha: alpha)
        }
    }
}

public extension CanvasColor {
    static let white = CanvasColor(red: 1, green: 1, blue: 1)
    static let black = CanvasColor(red: 0, green: 0, blue: 0)
    static let clear = CanvasColor(red: 0, green: 0, blue: 0, alpha: 0)
    static let accent = CanvasColor(hex: "FF6A3D")
    static let sky = CanvasColor(hex: "41B6FF")
    static let mint = CanvasColor(hex: "2AC7A0")
    static let sunflower = CanvasColor(hex: "FFCC47")
    static let plum = CanvasColor(hex: "6B4CE6")
}
