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
