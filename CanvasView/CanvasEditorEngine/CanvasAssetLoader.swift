import UIKit

final class CanvasAssetLoader {
    private static let inlineJPEGCompressionQuality: CGFloat = 0.82
    fileprivate static let transparencySampleDimension: Int = 64

    private let cache = NSCache<NSString, UIImage>()
    private let decodeQueue = DispatchQueue(label: "CanvasAssetLoader.decode", qos: .userInitiated)

    func image(for source: CanvasAssetSource?, completion: @escaping (UIImage?) -> Void) {
        guard let source else {
            completion(nil)
            return
        }

        if let cached = cachedImage(for: source) {
            completion(cached)
            return
        }

        switch source.kind {
        case .bundleImage:
            let image = source.name.flatMap(UIImage.init(named:))
            store(image, for: source)
            completion(image)

        case .symbol:
            let image = source.name.flatMap { UIImage(systemName: $0) }
            store(image, for: source)
            completion(image)

        case .inlineImage:
            decodeQueue.async { [weak self] in
                guard let dataBase64 = source.dataBase64,
                      let data = Data(base64Encoded: dataBase64) else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                let image = UIImage(data: data)
                self?.store(image, for: source)
                DispatchQueue.main.async {
                    completion(image)
                }
            }

        case .remoteURL:
            guard let urlString = source.url, let url = URL(string: urlString) else {
                completion(nil)
                return
            }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let image = data.flatMap(UIImage.init(data:))
                self?.store(image, for: source)
                DispatchQueue.main.async {
                    completion(image)
                }
            }.resume()
        }
    }

    func cachedImage(for source: CanvasAssetSource?) -> UIImage? {
        guard let source else {
            return nil
        }
        return cache.object(forKey: cacheKey(for: source))
    }

    func imageSynchronously(for source: CanvasAssetSource?) -> UIImage? {
        guard let source else {
            return nil
        }

        if let cached = cachedImage(for: source) {
            return cached
        }

        switch source.kind {
        case .bundleImage:
            let image = source.name.flatMap(UIImage.init(named:))
            store(image, for: source)
            return image
        case .symbol:
            let image = source.name.flatMap { UIImage(systemName: $0) }
            store(image, for: source)
            return image
        case .inlineImage:
            guard let dataBase64 = source.dataBase64, let data = Data(base64Encoded: dataBase64) else {
                return nil
            }
            let image = UIImage(data: data)
            store(image, for: source)
            return image
        case .remoteURL:
            return cachedImage(for: source)
        }
    }

    func inlineSource(from image: UIImage, maxDimension: CGFloat = 1_800) -> CanvasAssetSource? {
        let preservesTransparency = image.containsVisibleTransparency
        let resizedImage = resizeIfNeeded(
            image: image,
            maxDimension: maxDimension,
            isOpaque: !preservesTransparency
        )
        let source: CanvasAssetSource?
        if preservesTransparency, let data = resizedImage.pngData() {
            source = .inlineImage(data: data, mimeType: "image/png")
        } else if let data = resizedImage.jpegData(compressionQuality: Self.inlineJPEGCompressionQuality) {
            source = .inlineImage(data: data, mimeType: "image/jpeg")
        } else if let data = resizedImage.pngData() {
            source = .inlineImage(data: data, mimeType: "image/png")
        } else {
            source = nil
        }

        guard let source else {
            return nil
        }
        store(resizedImage, for: source)
        return source
    }

    private func resizeIfNeeded(image: UIImage, maxDimension: CGFloat, isOpaque: Bool) -> UIImage {
        let pixelSize = image.pixelSize
        let maxSide = max(pixelSize.width, pixelSize.height)
        guard maxSide > maxDimension, maxSide > 0 else {
            return image
        }

        let scale = maxDimension / maxSide
        let targetSize = CGSize(
            width: max(1, floor(pixelSize.width * scale)),
            height: max(1, floor(pixelSize.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = isOpaque
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func store(_ image: UIImage?, for source: CanvasAssetSource) {
        guard let image else {
            return
        }
        cache.setObject(image, forKey: cacheKey(for: source))
    }

    private func cacheKey(for source: CanvasAssetSource) -> NSString {
        NSString(string: "\(source.kind.rawValue)|\(source.name ?? "")|\(source.url ?? "")|\(source.dataBase64?.prefix(32) ?? "")")
    }
}

private extension UIImage {
    var pixelSize: CGSize {
        if let cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    var containsVisibleTransparency: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else {
            return false
        }

        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }

        let sampleWidth: Int = max(1, min(Int(pixelSize.width.rounded()), CanvasAssetLoader.transparencySampleDimension))
        let sampleHeight: Int = max(1, min(Int(pixelSize.height.rounded()), CanvasAssetLoader.transparencySampleDimension))
        let bytesPerPixel = 4
        let bytesPerRow: Int = sampleWidth * bytesPerPixel
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )

        var pixels = [UInt8](repeating: 255, count: sampleHeight * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return true
        }

        return pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: sampleWidth,
                    height: sampleHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                  ) else {
                return true
            }

            context.interpolationQuality = .low
            context.draw(
                cgImage!,
                in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
            )

            let alphaBytes = rawBuffer.bindMemory(to: UInt8.self)
            for index in stride(from: 3, to: alphaBytes.count, by: bytesPerPixel) {
                if alphaBytes[index] < 255 {
                    return true
                }
            }
            return false
        }
    }
}
