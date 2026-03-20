import UIKit

final class CanvasAssetLoader {
    private let cache = NSCache<NSString, UIImage>()

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
            guard let dataBase64 = source.dataBase64, let data = Data(base64Encoded: dataBase64) else {
                completion(nil)
                return
            }
            let image = UIImage(data: data)
            store(image, for: source)
            completion(image)

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
        let resizedImage = resizeIfNeeded(image: image, maxDimension: maxDimension)
        guard let data = resizedImage.pngData() else {
            return nil
        }
        return .inlineImage(data: data, mimeType: "image/png")
    }

    private func resizeIfNeeded(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension, maxSide > 0 else {
            return image
        }

        let scale = maxDimension / maxSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
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
