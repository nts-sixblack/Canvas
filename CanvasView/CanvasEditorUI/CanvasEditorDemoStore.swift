import Combine
import Foundation
import UIKit

private enum SavedCanvasDocumentError: Error {
    case imageDecodingFailed
}

@MainActor
final class CanvasEditorDemoStore: ObservableObject {
    @Published private(set) var templates: [CanvasTemplate] = []
    @Published private(set) var savedDocument: SavedCanvasDocument?

    private var persistenceRequestID = UUID()

    init() {
        loadTemplates()
        loadSavedDocument()
    }

    func makeTransientDocument(
        id: UUID = UUID(),
        result: CanvasEditorResult,
        previewImage: UIImage,
        savedAt: Date = Date()
    ) -> SavedCanvasDocument {
        SavedCanvasDocument(
            id: id,
            imageURL: nil,
            projectURL: nil,
            previewImage: previewImage,
            project: nil,
            savedAt: savedAt,
            imageByteCount: result.imageData.count,
            projectByteCount: result.projectData.count,
            nodeCount: nil,
            canvasSize: nil,
            containsInlineImages: nil,
            isPersisted: false
        )
    }

    func save(documentID: UUID, result: CanvasEditorResult) {
        let requestID = UUID()
        persistenceRequestID = requestID
        let imageData = result.imageData
        let projectData = result.projectData

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let document = try Self.persistDocument(
                    documentID: documentID,
                    imageData: imageData,
                    projectData: projectData
                )

                DispatchQueue.main.async {
                    guard self.persistenceRequestID == requestID else {
                        return
                    }
                    self.savedDocument = document
                }
            } catch {
                print("Canvas save error: \(error)")
            }
        }
    }

    func clearSavedDocument() {
        persistenceRequestID = UUID()
        let fileManager = FileManager.default
        let folderURL = Self.storageDirectory()
        try? fileManager.removeItem(at: folderURL.appendingPathComponent("last-export.png"))
        try? fileManager.removeItem(at: folderURL.appendingPathComponent("last-project.json"))
        savedDocument = nil
    }

    private func loadTemplates() {
        let decoder = JSONDecoder()
        let bundleTemplates = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Templates") ?? [])
            .compactMap { url -> CanvasTemplate? in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? decoder.decode(CanvasTemplate.self, from: data)
            }
            .sorted(by: { $0.name < $1.name })

        templates = bundleTemplates.isEmpty ? CanvasTemplateFallbacks.all : bundleTemplates
    }

    private func loadSavedDocument() {
        let requestID = UUID()
        persistenceRequestID = requestID

        DispatchQueue.global(qos: .userInitiated).async {
            let imageURL = Self.storageDirectory().appendingPathComponent("last-export.png")
            let projectURL = Self.storageDirectory().appendingPathComponent("last-project.json")
            let document = try? Self.buildSavedDocument(
                documentID: UUID(),
                imageURL: imageURL,
                projectURL: projectURL
            )

            DispatchQueue.main.async {
                guard self.persistenceRequestID == requestID else {
                    return
                }
                self.savedDocument = document
            }
        }
    }

    nonisolated private static func persistDocument(
        documentID: UUID,
        imageData: Data,
        projectData: Data
    ) throws -> SavedCanvasDocument {
        let folderURL = storageDirectory()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)

        let imageURL = folderURL.appendingPathComponent("last-export.png")
        let projectURL = folderURL.appendingPathComponent("last-project.json")
        try imageData.write(to: imageURL, options: .atomic)
        try projectData.write(to: projectURL, options: .atomic)

        return try buildSavedDocument(
            documentID: documentID,
            imageURL: imageURL,
            projectURL: projectURL
        )
    }

    nonisolated private static func buildSavedDocument(
        documentID: UUID,
        imageURL: URL,
        projectURL: URL
    ) throws -> SavedCanvasDocument {
        guard let imageData = try? Data(contentsOf: imageURL),
              let projectData = try? Data(contentsOf: projectURL) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        guard let previewImage = UIImage(data: imageData) else {
            throw SavedCanvasDocumentError.imageDecodingFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try? decoder.decode(CanvasProject.self, from: projectData)
        let summary = project?.summary
        let savedAt = ((try? projectURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? Date()

        return SavedCanvasDocument(
            id: documentID,
            imageURL: imageURL,
            projectURL: projectURL,
            previewImage: previewImage,
            project: project,
            savedAt: savedAt,
            imageByteCount: imageData.count,
            projectByteCount: projectData.count,
            nodeCount: summary?.nodeCount,
            canvasSize: summary?.canvasSize,
            containsInlineImages: summary?.containsInlineImages,
            isPersisted: true
        )
    }

    nonisolated private static func storageDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CanvasEditorDemo", isDirectory: true)
    }
}

struct SavedCanvasDocument: Identifiable {
    let id: UUID
    let imageURL: URL?
    let projectURL: URL?
    let previewImage: UIImage
    let project: CanvasProject?
    let savedAt: Date
    let imageByteCount: Int
    let projectByteCount: Int
    let nodeCount: Int?
    let canvasSize: CanvasSize?
    let containsInlineImages: Bool?
    let isPersisted: Bool
}

private enum CanvasTemplateFallbacks {
    static var all: [CanvasTemplate] {
        [
            CanvasTemplate(
                id: "square-vibes",
                name: "Square Vibes",
                canvasSize: CanvasSize(width: 1080, height: 1080),
                background: .solid(CanvasColor(hex: "132238")),
                nodes: [
                    CanvasNode(
                        kind: .image,
                        name: "Hero",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 520)),
                        size: CanvasSize(width: 760, height: 760),
                        zIndex: 0,
                        source: .remoteURL("https://picsum.photos/seed/canvas-square/900/900")
                    ),
                    CanvasNode(
                        kind: .text,
                        name: "Headline",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 180)),
                        size: CanvasSize(width: 760, height: 180),
                        zIndex: 1,
                        text: "NEW DROP",
                        style: CanvasTextStyle(
                            fontFamily: "Avenir Next",
                            weight: .heavy,
                            fontSize: 76,
                            foregroundColor: .white,
                            alignment: .center,
                            letterSpacing: 2,
                            lineSpacing: 0,
                            shadow: CanvasShadowStyle(color: .black, radius: 20, offsetX: 0, offsetY: 12),
                            outline: CanvasOutlineStyle(color: CanvasColor(hex: "FF6A3D"), width: 8),
                            backgroundFill: nil,
                            opacity: 1
                        )
                    ),
                    CanvasNode(
                        kind: .sticker,
                        name: "Sparkles",
                        transform: CanvasTransform(position: CanvasPoint(x: 875, y: 860), rotation: -0.15, scale: 1),
                        size: CanvasSize(width: 180, height: 180),
                        zIndex: 2,
                        source: .symbol(named: "sparkles"),
                        style: CanvasTextStyle(
                            fontFamily: "Avenir Next",
                            weight: .bold,
                            fontSize: 40,
                            foregroundColor: .sunflower,
                            alignment: .center,
                            opacity: 1
                        )
                    )
                ]
            ),
            CanvasTemplate(
                id: "portrait-story",
                name: "Portrait Story",
                canvasSize: CanvasSize(width: 1080, height: 1920),
                background: .solid(CanvasColor(hex: "190E2C")),
                nodes: [
                    CanvasNode(
                        kind: .image,
                        name: "Mood",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 720)),
                        size: CanvasSize(width: 900, height: 1080),
                        zIndex: 0,
                        source: .remoteURL("https://picsum.photos/seed/canvas-portrait/900/1200")
                    ),
                    CanvasNode(
                        kind: .emoji,
                        name: "Emoji",
                        transform: CanvasTransform(position: CanvasPoint(x: 230, y: 260), rotation: -0.2, scale: 1),
                        size: CanvasSize(width: 220, height: 220),
                        zIndex: 1,
                        text: "🌙",
                        style: .defaultEmoji
                    ),
                    CanvasNode(
                        kind: .text,
                        name: "Story",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 1510)),
                        size: CanvasSize(width: 820, height: 260),
                        zIndex: 2,
                        text: "Tonight feels electric",
                        style: CanvasTextStyle(
                            fontFamily: "Georgia",
                            weight: .bold,
                            fontSize: 68,
                            foregroundColor: .white,
                            alignment: .center,
                            letterSpacing: 0.5,
                            lineSpacing: 10,
                            shadow: CanvasShadowStyle(color: .black, radius: 20, offsetX: 0, offsetY: 10),
                            outline: nil,
                            backgroundFill: CanvasFillStyle(color: CanvasColor(hex: "000000", alpha: 0.5)),
                            opacity: 1
                        )
                    )
                ]
            ),
            CanvasTemplate(
                id: "poster-45",
                name: "Poster 4:5",
                canvasSize: CanvasSize(width: 1080, height: 1350),
                background: .solid(CanvasColor(hex: "0F1A10")),
                nodes: [
                    CanvasNode(
                        kind: .text,
                        name: "Poster",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 210)),
                        size: CanvasSize(width: 860, height: 220),
                        zIndex: 0,
                        text: "Weekend launch",
                        style: CanvasTextStyle(
                            fontFamily: "Helvetica Neue",
                            weight: .heavy,
                            fontSize: 84,
                            foregroundColor: .mint,
                            alignment: .center,
                            letterSpacing: -1,
                            lineSpacing: 2,
                            shadow: nil,
                            outline: nil,
                            backgroundFill: nil,
                            opacity: 1
                        )
                    ),
                    CanvasNode(
                        kind: .sticker,
                        name: "Heart",
                        transform: CanvasTransform(position: CanvasPoint(x: 190, y: 1130), rotation: 0.2, scale: 1),
                        size: CanvasSize(width: 180, height: 180),
                        zIndex: 1,
                        source: .symbol(named: "heart.fill"),
                        style: CanvasTextStyle(
                            fontFamily: "Avenir Next",
                            weight: .bold,
                            fontSize: 40,
                            foregroundColor: .accent,
                            alignment: .center,
                            opacity: 1
                        )
                    ),
                    CanvasNode(
                        kind: .image,
                        name: "Preview",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 790)),
                        size: CanvasSize(width: 820, height: 820),
                        zIndex: 2,
                        source: .remoteURL("https://picsum.photos/seed/canvas-poster/900/900")
                    )
                ]
            )
        ]
    }
}
