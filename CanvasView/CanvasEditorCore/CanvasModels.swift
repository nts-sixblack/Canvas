import CoreGraphics
import Foundation

public enum CanvasSchemaVersion {
    public static let current = 3
}

public struct CanvasSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    public var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

public struct CanvasPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct CanvasTransform: Codable, Hashable, Sendable {
    public var position: CanvasPoint
    public var rotation: Double
    public var scale: Double

    public init(position: CanvasPoint, rotation: Double = 0, scale: Double = 1) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

public enum CanvasNodeKind: String, Codable, CaseIterable, Sendable {
    case text
    case emoji
    case sticker
    case image
    case shape
}

public enum CanvasShapeType: String, Codable, CaseIterable, Sendable {
    case brush
    case line
    case arrow
    case oval
    case rectangle
}

public extension CanvasShapeType {
    var displayTitle: String {
        switch self {
        case .brush:
            return "Brush"
        case .line:
            return "Line"
        case .arrow:
            return "Arrow"
        case .oval:
            return "Oval"
        case .rectangle:
            return "Rectangle"
        }
    }
}

public struct CanvasShapePayload: Codable, Hashable, Sendable {
    public var type: CanvasShapeType
    public var points: [CanvasPoint]
    public var strokeColor: CanvasColor
    public var strokeWidth: Double

    public init(
        type: CanvasShapeType,
        points: [CanvasPoint],
        strokeColor: CanvasColor,
        strokeWidth: Double
    ) {
        self.type = type
        self.points = points
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }
}

public struct CanvasShapeDraft: Hashable, Sendable {
    public var type: CanvasShapeType
    public var points: [CanvasPoint]
    public var strokeColor: CanvasColor
    public var strokeWidth: Double
    public var opacity: Double

    public init(
        type: CanvasShapeType,
        points: [CanvasPoint],
        strokeColor: CanvasColor,
        strokeWidth: Double,
        opacity: Double = 1
    ) {
        self.type = type
        self.points = points
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.opacity = opacity
    }
}

public struct CanvasEraserStroke: Codable, Hashable, Sendable {
    public var points: [CanvasPoint]
    public var strokeWidth: Double

    public init(points: [CanvasPoint], strokeWidth: Double) {
        self.points = points
        self.strokeWidth = strokeWidth
    }
}

public enum CanvasEraserPathBuilder {
    public static func makePath(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
        } else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        return path
    }

    public static func makePath(for stroke: CanvasEraserStroke) -> CGPath {
        makePath(points: stroke.points.map(\.cgPoint))
    }

    public static func makeMaskPath(in rect: CGRect, strokes: [CanvasEraserStroke]) -> CGPath {
        let maskPath = CGMutablePath()
        maskPath.addRect(rect)

        for stroke in strokes where !stroke.points.isEmpty {
            let strokedPath = makePath(for: stroke).copy(
                strokingWithWidth: CGFloat(stroke.strokeWidth),
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            maskPath.addPath(strokedPath)
        }

        return maskPath
    }

    public static func applyClearStrokes(_ strokes: [CanvasEraserStroke], in context: CGContext) {
        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes where !stroke.points.isEmpty {
            context.addPath(makePath(for: stroke))
            context.setLineWidth(CGFloat(stroke.strokeWidth))
            context.strokePath()
        }

        context.restoreGState()
    }
}

public enum CanvasAssetKind: String, Codable, Sendable {
    case bundleImage
    case symbol
    case remoteURL
    case inlineImage
}

public struct CanvasAssetSource: Codable, Hashable, Sendable {
    public var kind: CanvasAssetKind
    public var name: String?
    public var url: String?
    public var dataBase64: String?
    public var mimeType: String?

    public init(
        kind: CanvasAssetKind,
        name: String? = nil,
        url: String? = nil,
        dataBase64: String? = nil,
        mimeType: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.url = url
        self.dataBase64 = dataBase64
        self.mimeType = mimeType
    }

    public static func bundleImage(named name: String) -> CanvasAssetSource {
        CanvasAssetSource(kind: .bundleImage, name: name)
    }

    public static func symbol(named name: String) -> CanvasAssetSource {
        CanvasAssetSource(kind: .symbol, name: name)
    }

    public static func remoteURL(_ url: String) -> CanvasAssetSource {
        CanvasAssetSource(kind: .remoteURL, url: url)
    }

    public static func inlineImage(data: Data, mimeType: String = "image/png") -> CanvasAssetSource {
        CanvasAssetSource(kind: .inlineImage, dataBase64: data.base64EncodedString(), mimeType: mimeType)
    }
}

public enum CanvasBackgroundKind: String, Codable, Sendable {
    case solidColor
    case image
}

public struct CanvasBackground: Codable, Hashable, Sendable {
    public var kind: CanvasBackgroundKind
    public var color: CanvasColor?
    public var source: CanvasAssetSource?

    public init(kind: CanvasBackgroundKind, color: CanvasColor? = nil, source: CanvasAssetSource? = nil) {
        self.kind = kind
        self.color = color
        self.source = source
    }

    public static func solid(_ color: CanvasColor) -> CanvasBackground {
        CanvasBackground(kind: .solidColor, color: color)
    }

    public static func image(_ source: CanvasAssetSource) -> CanvasBackground {
        CanvasBackground(kind: .image, source: source)
    }
}

public enum CanvasTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

public enum CanvasFontWeight: String, Codable, CaseIterable, Sendable {
    case regular
    case medium
    case semibold
    case bold
    case heavy
}

public struct CanvasShadowStyle: Codable, Hashable, Sendable {
    public var color: CanvasColor
    public var radius: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(color: CanvasColor, radius: Double, offsetX: Double, offsetY: Double) {
        self.color = color
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

public struct CanvasOutlineStyle: Codable, Hashable, Sendable {
    public var color: CanvasColor
    public var width: Double

    public init(color: CanvasColor, width: Double) {
        self.color = color
        self.width = width
    }
}

public struct CanvasFillStyle: Codable, Hashable, Sendable {
    public var color: CanvasColor

    public init(color: CanvasColor) {
        self.color = color
    }
}

public struct CanvasTextStyle: Codable, Hashable, Sendable {
    public var fontFamily: String
    public var weight: CanvasFontWeight
    public var isItalic: Bool
    public var fontSize: Double
    public var foregroundColor: CanvasColor
    public var alignment: CanvasTextAlignment
    public var letterSpacing: Double
    public var lineSpacing: Double
    public var shadow: CanvasShadowStyle?
    public var outline: CanvasOutlineStyle?
    public var backgroundFill: CanvasFillStyle?
    public var opacity: Double

    public init(
        fontFamily: String,
        weight: CanvasFontWeight = .regular,
        isItalic: Bool = false,
        fontSize: Double,
        foregroundColor: CanvasColor,
        alignment: CanvasTextAlignment = .center,
        letterSpacing: Double = 0,
        lineSpacing: Double = 0,
        shadow: CanvasShadowStyle? = nil,
        outline: CanvasOutlineStyle? = nil,
        backgroundFill: CanvasFillStyle? = nil,
        opacity: Double = 1.0
    ) {
        self.fontFamily = fontFamily
        self.weight = weight
        self.isItalic = isItalic
        self.fontSize = fontSize
        self.foregroundColor = foregroundColor
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.shadow = shadow
        self.outline = outline
        self.backgroundFill = backgroundFill
        self.opacity = opacity
    }
}

public extension CanvasTextStyle {
    static var defaultText: CanvasTextStyle {
        CanvasTextStyle(
            fontFamily: "Avenir Next",
            weight: .bold,
            fontSize: 42,
            foregroundColor: .white,
            alignment: .center,
            shadow: CanvasShadowStyle(color: .black, radius: 12, offsetX: 0, offsetY: 8),
            opacity: 1
        )
    }

    static var defaultEmoji: CanvasTextStyle {
        CanvasTextStyle(
            fontFamily: "Apple Color Emoji",
            weight: .regular,
            fontSize: 72,
            foregroundColor: .white,
            alignment: .center,
            opacity: 1
        )
    }
}

public struct CanvasNode: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: CanvasNodeKind
    public var name: String?
    public var transform: CanvasTransform
    public var size: CanvasSize
    public var zIndex: Int
    public var opacity: Double
    public var source: CanvasAssetSource?
    public var text: String?
    public var style: CanvasTextStyle?
    public var shape: CanvasShapePayload?
    public var isEditable: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case transform
        case size
        case zIndex
        case opacity
        case source
        case text
        case style
        case shape
        case isEditable
    }

    public init(
        id: String = UUID().uuidString,
        kind: CanvasNodeKind,
        name: String? = nil,
        transform: CanvasTransform,
        size: CanvasSize,
        zIndex: Int,
        opacity: Double = 1,
        source: CanvasAssetSource? = nil,
        text: String? = nil,
        style: CanvasTextStyle? = nil,
        shape: CanvasShapePayload? = nil,
        isEditable: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.transform = transform
        self.size = size
        self.zIndex = zIndex
        self.opacity = opacity
        self.source = source
        self.text = text
        self.style = style
        self.shape = shape
        self.isEditable = isEditable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decode(CanvasNodeKind.self, forKey: .kind)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        transform = try container.decode(CanvasTransform.self, forKey: .transform)
        size = try container.decode(CanvasSize.self, forKey: .size)
        zIndex = try container.decode(Int.self, forKey: .zIndex)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        source = try container.decodeIfPresent(CanvasAssetSource.self, forKey: .source)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        style = try container.decodeIfPresent(CanvasTextStyle.self, forKey: .style)
        shape = try container.decodeIfPresent(CanvasShapePayload.self, forKey: .shape)
        isEditable = try container.decodeIfPresent(Bool.self, forKey: .isEditable) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(transform, forKey: .transform)
        try container.encode(size, forKey: .size)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(opacity, forKey: .opacity)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(shape, forKey: .shape)
        try container.encode(isEditable, forKey: .isEditable)
    }
}

public struct CanvasTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: Int
    public var canvasSize: CanvasSize
    public var background: CanvasBackground
    public var nodes: [CanvasNode]

    public init(
        id: String,
        name: String,
        version: Int = CanvasSchemaVersion.current,
        canvasSize: CanvasSize,
        background: CanvasBackground,
        nodes: [CanvasNode]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.canvasSize = canvasSize
        self.background = background
        self.nodes = nodes
    }
}

public struct CanvasProjectMetadata: Codable, Hashable, Sendable {
    public var createdAt: Date?
    public var modifiedAt: Date?

    public init(createdAt: Date? = nil, modifiedAt: Date? = nil) {
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct CanvasProject: Codable, Hashable, Sendable {
    public var version: Int
    public var templateID: String
    public var canvasSize: CanvasSize
    public var background: CanvasBackground
    public var nodes: [CanvasNode]
    public var eraserStrokes: [CanvasEraserStroke]
    public var metadata: CanvasProjectMetadata

    private enum CodingKeys: String, CodingKey {
        case version
        case templateID
        case canvasSize
        case background
        case nodes
        case eraserStrokes
        case metadata
    }

    public init(
        version: Int = CanvasSchemaVersion.current,
        templateID: String,
        canvasSize: CanvasSize,
        background: CanvasBackground,
        nodes: [CanvasNode],
        eraserStrokes: [CanvasEraserStroke] = [],
        metadata: CanvasProjectMetadata = CanvasProjectMetadata()
    ) {
        self.version = version
        self.templateID = templateID
        self.canvasSize = canvasSize
        self.background = background
        self.nodes = nodes
        self.eraserStrokes = eraserStrokes
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? CanvasSchemaVersion.current
        templateID = try container.decode(String.self, forKey: .templateID)
        canvasSize = try container.decode(CanvasSize.self, forKey: .canvasSize)
        background = try container.decode(CanvasBackground.self, forKey: .background)
        nodes = try container.decode([CanvasNode].self, forKey: .nodes)
        eraserStrokes = try container.decodeIfPresent([CanvasEraserStroke].self, forKey: .eraserStrokes) ?? []
        metadata = try container.decodeIfPresent(CanvasProjectMetadata.self, forKey: .metadata) ?? CanvasProjectMetadata()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(templateID, forKey: .templateID)
        try container.encode(canvasSize, forKey: .canvasSize)
        try container.encode(background, forKey: .background)
        try container.encode(nodes, forKey: .nodes)
        try container.encode(eraserStrokes, forKey: .eraserStrokes)
        try container.encode(metadata, forKey: .metadata)
    }

    public init(template: CanvasTemplate) {
        let now = Date()
        self.init(
            version: CanvasSchemaVersion.current,
            templateID: template.id,
            canvasSize: template.canvasSize,
            background: template.background,
            nodes: template.nodes.sorted(by: { $0.zIndex < $1.zIndex }),
            eraserStrokes: [],
            metadata: CanvasProjectMetadata(createdAt: now, modifiedAt: now)
        )
    }
}

public extension CanvasProject {
    var sortedNodes: [CanvasNode] {
        nodes.sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id < rhs.id
            }
            return lhs.zIndex < rhs.zIndex
        }
    }
}

public struct CanvasStickerDescriptor: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var source: CanvasAssetSource

    public init(id: String, name: String, source: CanvasAssetSource) {
        self.id = id
        self.name = name
        self.source = source
    }
}

public enum CanvasEditorTool: String, CaseIterable, Sendable {
    case addBrush
    case addText
    case addEmoji
    case addSticker
    case addImage
    case addRemoteImage
    case duplicate
    case delete
    case bringToFront
    case sendToBack
    case undo
    case redo
    case export
}

public struct CanvasEditorConfiguration: Hashable, Sendable {
    public var fontCatalog: [String]
    public var stickerCatalog: [CanvasStickerDescriptor]
    public var colorPalette: [CanvasColor]
    public var exportMaxDimension: Double
    public var enabledTools: [CanvasEditorTool]

    public init(
        fontCatalog: [String],
        stickerCatalog: [CanvasStickerDescriptor],
        colorPalette: [CanvasColor],
        exportMaxDimension: Double = 2_048,
        enabledTools: [CanvasEditorTool] = CanvasEditorTool.allCases
    ) {
        self.fontCatalog = fontCatalog
        self.stickerCatalog = stickerCatalog
        self.colorPalette = colorPalette
        self.exportMaxDimension = exportMaxDimension
        self.enabledTools = enabledTools
    }
}

public extension CanvasEditorConfiguration {
    static var demo: CanvasEditorConfiguration {
        CanvasEditorConfiguration(
            fontCatalog: [
                "Avenir Next",
                "Helvetica Neue",
                "Georgia",
                "Marker Felt",
                "Futura"
            ],
            stickerCatalog: [
                CanvasStickerDescriptor(id: "sparkles", name: "Sparkles", source: .symbol(named: "sparkles")),
                CanvasStickerDescriptor(id: "star", name: "Star", source: .symbol(named: "star.fill")),
                CanvasStickerDescriptor(id: "heart", name: "Heart", source: .symbol(named: "heart.fill")),
                CanvasStickerDescriptor(id: "flash", name: "Flash", source: .symbol(named: "bolt.fill")),
                CanvasStickerDescriptor(id: "moon", name: "Moon", source: .symbol(named: "moon.stars.fill"))
            ],
            colorPalette: [
                .white,
                .black,
                .accent,
                .sky,
                .mint,
                .sunflower,
                .plum
            ]
        )
    }
}

public struct CanvasEditorResult: Sendable {
    public var imageData: Data
    public var projectData: Data

    public init(imageData: Data, projectData: Data) {
        self.imageData = imageData
        self.projectData = projectData
    }
}
