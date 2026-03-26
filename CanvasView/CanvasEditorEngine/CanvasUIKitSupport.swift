import UIKit

extension CanvasColor {
    var uiColor: UIColor {
        UIColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    init(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
            )
            return
        }

        let fallback = CIColor(color: uiColor)
        self.init(
            red: fallback.red,
            green: fallback.green,
            blue: fallback.blue,
            alpha: fallback.alpha
        )
    }
}

extension CanvasShapeType {
    var systemImageName: String {
        switch self {
        case .brush:
            return "paintbrush"
        case .line:
            return "line.diagonal"
        case .arrow:
            return "arrow.up.right"
        case .oval:
            return "circle"
        case .rectangle:
            return "square"
        }
    }
}

enum CanvasShapePathBuilder {
    static func localPoints(for payload: CanvasShapePayload) -> [CGPoint] {
        payload.points.map(\.cgPoint)
    }

    static func makePath(type: CanvasShapeType, points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()

        switch type {
        case .brush:
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

        case .line:
            guard let first = points.first, let last = points.last else {
                return path
            }
            path.move(to: first)
            path.addLine(to: last)

        case .arrow:
            guard let first = points.first, let last = points.last else {
                return path
            }
            path.move(to: first)
            path.addLine(to: last)

            let deltaX = last.x - first.x
            let deltaY = last.y - first.y
            let length = max(hypot(deltaX, deltaY), 0.001)
            let baseAngle = atan2(deltaY, deltaX)
            let headLength = max(length * 0.16, 18)
            let arrowAngle = CGFloat.pi / 6
            let leftPoint = CGPoint(
                x: last.x - cos(baseAngle - arrowAngle) * headLength,
                y: last.y - sin(baseAngle - arrowAngle) * headLength
            )
            let rightPoint = CGPoint(
                x: last.x - cos(baseAngle + arrowAngle) * headLength,
                y: last.y - sin(baseAngle + arrowAngle) * headLength
            )

            path.move(to: last)
            path.addLine(to: leftPoint)
            path.move(to: last)
            path.addLine(to: rightPoint)

        case .oval:
            let rect = rect(for: points)
            if rect.isNull {
                return path
            }
            path.append(UIBezierPath(ovalIn: rect))

        case .rectangle:
            let rect = rect(for: points)
            if rect.isNull {
                return path
            }
            path.append(UIBezierPath(rect: rect))
        }

        return path
    }

    private static func rect(for points: [CGPoint]) -> CGRect {
        if points.count == 2, let first = points.first, let last = points.last {
            return CGRect(
                x: min(first.x, last.x),
                y: min(first.y, last.y),
                width: abs(last.x - first.x),
                height: abs(last.y - first.y)
            )
        }

        guard !points.isEmpty else {
            return .null
        }

        return points.reduce(into: CGRect.null) { partialResult, point in
            partialResult = partialResult.union(CGRect(origin: point, size: .zero))
        }
    }
}

extension CanvasShapePayload {
    func bezierPath() -> UIBezierPath {
        CanvasShapePathBuilder.makePath(
            type: type,
            points: CanvasShapePathBuilder.localPoints(for: self)
        )
    }
}

extension CanvasTextAlignment {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .leading:
            return .left
        case .center:
            return .center
        case .trailing:
            return .right
        }
    }
}

extension CanvasFontWeight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .heavy:
            return .heavy
        }
    }
}

extension CanvasTextStyle {
    var resolvedBackgroundUIColor: UIColor? {
        guard let backgroundFill else {
            return nil
        }

        let color = backgroundFill.color
        return CanvasColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha * opacity
        ).uiColor
    }

    func textAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment.nsTextAlignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing

        var attributes: [NSAttributedString.Key: Any] = [
            .font: makeFont(),
            .foregroundColor: foregroundColor.uiColor.withAlphaComponent(opacity),
            .paragraphStyle: paragraph,
            .kern: letterSpacing
        ]

        if let shadow {
            let nsShadow = NSShadow()
            nsShadow.shadowColor = shadow.color.uiColor
            nsShadow.shadowBlurRadius = shadow.radius
            nsShadow.shadowOffset = CGSize(width: shadow.offsetX, height: shadow.offsetY)
            attributes[.shadow] = nsShadow
        }

        if let outline {
            attributes[.strokeColor] = outline.color.uiColor
            attributes[.strokeWidth] = -outline.width
        }

        return attributes
    }

    func makeFont() -> UIFont {
        let pointSize = CGFloat(fontSize)
        let familyFonts = UIFont.fontNames(forFamilyName: fontFamily)
        let font: UIFont

        if let matchedFontName = bestMatchingFontName(in: familyFonts) ?? UIFont(name: fontFamily, size: pointSize)?.fontName,
           let resolvedFont = UIFont(name: matchedFontName, size: pointSize) {
            font = resolvedFont
        } else {
            font = UIFont.systemFont(ofSize: pointSize, weight: weight.uiFontWeight)
        }

        guard isItalic else {
            return font
        }

        if let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            return UIFont(descriptor: descriptor, size: pointSize)
        }
        return font
    }

    func attributedString(text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: textAttributes())
    }

    func requiredTextHeight(text: String, constrainedWidth: CGFloat) -> CGFloat {
        let measuredText = text.isEmpty ? " " : text
        let boundingRect = attributedString(text: measuredText).boundingRect(
            with: CGSize(width: max(constrainedWidth, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(boundingRect.height)
    }

    private func bestMatchingFontName(in fontNames: [String]) -> String? {
        guard !fontNames.isEmpty else {
            return nil
        }

        let italicTokens = ["italic", "oblique"]
        let weightTokens: [String]
        switch weight {
        case .regular:
            weightTokens = ["regular", "book"]
        case .medium:
            weightTokens = ["medium"]
        case .semibold:
            weightTokens = ["semibold", "demi"]
        case .bold:
            weightTokens = ["bold"]
        case .heavy:
            weightTokens = ["heavy", "black"]
        }

        return fontNames.max { lhs, rhs in
            fontMatchScore(lhs, italicTokens: italicTokens, weightTokens: weightTokens) <
                fontMatchScore(rhs, italicTokens: italicTokens, weightTokens: weightTokens)
        }
    }

    private func fontMatchScore(_ fontName: String, italicTokens: [String], weightTokens: [String]) -> Int {
        let lowercased = fontName.lowercased()
        let weightScore = weightTokens.contains(where: lowercased.contains) ? 4 : 0
        let italicScore = isItalic == italicTokens.contains(where: lowercased.contains) ? 3 : 0
        let familyScore = lowercased.contains(fontFamily.lowercased().replacingOccurrences(of: " ", with: "")) ? 2 : 0
        return weightScore + italicScore + familyScore
    }
}
